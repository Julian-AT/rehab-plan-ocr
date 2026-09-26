//! Live recognition registrations. A scan ID may be retried, but cancellation
//! always belongs to one attempt. No cancelled/completed ID tombstones survive.
use crate::AppError;
use std::{
    collections::HashMap,
    sync::{
        atomic::{AtomicBool, AtomicU8, Ordering},
        Arc, Mutex,
    },
};

const REGISTERED: u8 = 0;
const RUNNING: u8 = 1;
const FINISHED: u8 = 2;
type Result<T> = std::result::Result<T, AppError>;

struct Entry {
    attempt: String,
    cancelled: Arc<AtomicBool>,
    phase: Arc<AtomicU8>,
}
#[derive(Default)]
pub(crate) struct RecognitionJobs {
    // Only actual registrations occupy memory. The owning handle/worker removes
    // its entry on every exit, including an import that was never started.
    active: Mutex<HashMap<String, Entry>>,
}
impl RecognitionJobs {
    pub(crate) fn register(self: &Arc<Self>, scan_id: String) -> Result<Arc<RecognitionJob>> {
        uuid::Uuid::parse_str(&scan_id).map_err(|_| AppError::Validation {
            message: "Ungültige Aufnahme-ID.".into(),
        })?;
        let mut active = self.active.lock().map_err(storage)?;
        if active.contains_key(&scan_id) {
            return Err(AppError::Busy);
        }
        let job = Arc::new(RecognitionJob {
            scan_id: scan_id.clone(),
            attempt: uuid::Uuid::new_v4().to_string(),
            cancelled: Arc::new(AtomicBool::new(false)),
            phase: Arc::new(AtomicU8::new(REGISTERED)),
            registry: self.clone(),
        });
        active.insert(
            scan_id,
            Entry {
                attempt: job.attempt.clone(),
                cancelled: job.cancelled.clone(),
                phase: job.phase.clone(),
            },
        );
        Ok(job)
    }
    pub(crate) fn cancel(&self, attempt: &str) -> Result<()> {
        let active = self.active.lock().map_err(storage)?;
        if let Some(entry) = active.values().find(|entry| entry.attempt == attempt) {
            entry.cancelled.store(true, Ordering::Relaxed);
        }
        Ok(())
    }
    pub(crate) fn flag(&self, scan_id: &str) -> Option<Arc<AtomicBool>> {
        self.active
            .lock()
            .ok()?
            .get(scan_id)
            .map(|e| e.cancelled.clone())
    }
    pub(crate) fn running(&self) -> bool {
        self.active
            .lock()
            .map(|active| {
                active
                    .values()
                    .any(|entry| entry.phase.load(Ordering::Acquire) == RUNNING)
            })
            .unwrap_or(true)
    }
    fn remove(&self, scan_id: &str, attempt: &str) {
        // Cleanup must also run after unwinding; no externally visible effect is
        // performed while this mutex is held, so recovering its map is safe.
        let mut active = self.active.lock().unwrap_or_else(|e| e.into_inner());
        if active
            .get(scan_id)
            .is_some_and(|entry| entry.attempt == attempt)
        {
            active.remove(scan_id);
        }
    }
    #[cfg(test)]
    pub(crate) fn len(&self) -> usize {
        self.active.lock().unwrap().len()
    }
}
fn storage(error: impl std::fmt::Display) -> AppError {
    AppError::Storage {
        message: error.to_string(),
    }
}

#[derive(uniffi::Object)]
pub struct RecognitionJob {
    scan_id: String,
    attempt: String,
    cancelled: Arc<AtomicBool>,
    phase: Arc<AtomicU8>,
    registry: Arc<RecognitionJobs>,
}
#[uniffi::export]
impl RecognitionJob {
    /// Opaque attempt identity, deliberately different from the retained scan ID.
    pub fn attempt_id(&self) -> String {
        self.attempt.clone()
    }
    pub fn cancel(&self) {
        self.cancelled.store(true, Ordering::Relaxed);
    }
    /// Releases an unstarted registration. A started worker keeps its lease
    /// until it actually returns; closing its UI owner signals cancellation.
    pub fn close(&self) {
        self.cancel();
        if self
            .phase
            .compare_exchange(REGISTERED, FINISHED, Ordering::AcqRel, Ordering::Acquire)
            .is_ok()
        {
            self.registry.remove(&self.scan_id, &self.attempt);
        }
    }
}
impl RecognitionJob {
    pub(crate) fn start(
        self: &Arc<Self>,
        registry: &Arc<RecognitionJobs>,
        scan_id: &str,
    ) -> Result<JobLease> {
        if !Arc::ptr_eq(registry, &self.registry) || self.scan_id != scan_id {
            return Err(AppError::Validation {
                message: "Erkennungsauftrag gehört zu einer anderen Aufnahme.".into(),
            });
        }
        self.phase
            .compare_exchange(REGISTERED, RUNNING, Ordering::AcqRel, Ordering::Acquire)
            .map_err(|_| AppError::Validation {
                message: "Erkennungsauftrag wurde bereits gestartet oder geschlossen.".into(),
            })?;
        Ok(JobLease { job: self.clone() })
    }
    pub(crate) fn is_cancelled(&self) -> bool {
        self.cancelled.load(Ordering::Relaxed)
    }
}
impl Drop for RecognitionJob {
    fn drop(&mut self) {
        self.close();
    }
}
pub(crate) struct JobLease {
    job: Arc<RecognitionJob>,
}
impl Drop for JobLease {
    fn drop(&mut self) {
        self.job.phase.store(FINISHED, Ordering::Release);
        self.job
            .registry
            .remove(&self.job.scan_id, &self.job.attempt);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn id() -> String {
        uuid::Uuid::new_v4().to_string()
    }
    #[test]
    fn abandoned_registrations_and_unknown_cancellation_do_not_accumulate() {
        let jobs = Arc::new(RecognitionJobs::default());
        for _ in 0..1000 {
            jobs.cancel(&id()).unwrap();
            drop(jobs.register(id()).unwrap());
        }
        assert_eq!(jobs.len(), 0);
        let job = jobs.register(id()).unwrap();
        job.close();
        assert_eq!(jobs.len(), 0);
        assert!(job.start(&jobs, &job.scan_id).is_err());
    }
    #[test]
    fn cancellation_before_start_and_after_close_belongs_only_to_that_attempt() {
        let jobs = Arc::new(RecognitionJobs::default());
        let scan = id();
        let first = jobs.register(scan.clone()).unwrap();
        assert!(matches!(jobs.register(scan.clone()), Err(AppError::Busy)));
        jobs.cancel(&first.attempt_id()).unwrap();
        let lease = first.start(&jobs, &scan).unwrap();
        assert!(first.is_cancelled());
        assert!(Arc::ptr_eq(&jobs.flag(&scan).unwrap(), &first.cancelled));
        assert!(first.start(&jobs, &scan).is_err());
        first.close();
        assert!(jobs.running());
        drop(lease);
        assert_eq!(jobs.len(), 0);
        let second = jobs.register(scan.clone()).unwrap();
        assert_ne!(first.attempt_id(), second.attempt_id());
        jobs.cancel(&first.attempt_id()).unwrap();
        first.cancel();
        drop(first);
        assert!(!second.is_cancelled());
        assert_eq!(jobs.len(), 1);
        assert!(!jobs.running());
        second.close();
        assert_eq!(jobs.len(), 0);
    }
    #[test]
    fn an_attempt_cannot_start_for_a_different_scan_or_application() {
        let jobs = Arc::new(RecognitionJobs::default());
        let other = Arc::new(RecognitionJobs::default());
        let scan = id();
        let job = jobs.register(scan.clone()).unwrap();
        assert!(job.start(&jobs, &id()).is_err());
        assert!(job.start(&other, &scan).is_err());
        let lease = job.start(&jobs, &scan).unwrap();
        drop(job);
        assert_eq!(jobs.len(), 1);
        drop(lease);
        assert_eq!(jobs.len(), 0);
    }
}
