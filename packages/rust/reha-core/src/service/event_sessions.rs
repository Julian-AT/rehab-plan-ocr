//! Server-issued editing sessions have a bounded live registry, not an ever-growing
//! list of revoked client IDs. In-flight work retains its revoked lease independently.
use super::Response;
use std::{
    collections::HashMap,
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc,
    },
};

const MAX_SESSIONS: usize = 32;

#[derive(Default)]
pub struct EventSessions {
    active: HashMap<String, Arc<AtomicBool>>,
}

pub(crate) struct EventSessionLease(Arc<AtomicBool>);

impl EventSessionLease {
    pub(crate) fn check(&self) -> Response<()> {
        if self.0.load(Ordering::Acquire) {
            Ok(())
        } else {
            Err("Sitzung unterbrochen. Neu beginnen.".into())
        }
    }
}

impl EventSessions {
    pub fn register(&mut self) -> Response<String> {
        if self.active.len() >= MAX_SESSIONS {
            return Err("Zu viele offene Terminbearbeitungen. Eine Bearbeitung schließen.".into());
        }
        let token = uuid::Uuid::new_v4().to_string();
        self.active
            .insert(token.clone(), Arc::new(AtomicBool::new(true)));
        Ok(token)
    }

    pub(crate) fn lease(&self, token: &str) -> Response<EventSessionLease> {
        self.active
            .get(token)
            .cloned()
            .map(EventSessionLease)
            .ok_or_else(|| "Sitzung unterbrochen. Neu beginnen.".into())
    }

    pub fn revoke(&mut self, token: &str) {
        if let Some(active) = self.active.remove(token) {
            active.store(false, Ordering::Release);
        }
    }

    pub fn revoke_all(&mut self) {
        for (_, active) in self.active.drain() {
            active.store(false, Ordering::Release);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn revocation_does_not_retain_tombstones_or_reenable_inflight_work() {
        let mut sessions = EventSessions::default();
        let old = sessions.register().unwrap();
        let pending = sessions.lease(&old).unwrap();
        sessions.revoke(&old);
        for _ in 0..10_000 {
            let token = sessions.register().unwrap();
            assert_ne!(token, old);
            sessions.revoke(&token);
            assert!(sessions.active.is_empty());
        }
        assert!(sessions.lease(&old).is_err());
        assert!(pending.check().is_err());
    }

    #[test]
    fn capacity_rejects_admission_without_evicting_a_live_session() {
        let mut sessions = EventSessions::default();
        let tokens: Vec<_> = (0..MAX_SESSIONS)
            .map(|_| sessions.register().unwrap())
            .collect();
        assert!(sessions.register().is_err());
        for token in &tokens {
            sessions.lease(token).unwrap().check().unwrap();
        }
        sessions.revoke(&tokens[0]);
        sessions.register().unwrap();
        assert_eq!(sessions.active.len(), MAX_SESSIONS);
    }

    #[test]
    fn local_erasure_revokes_inflight_leases_and_releases_all_admissions() {
        let mut sessions = EventSessions::default();
        let token = sessions.register().unwrap();
        let pending = sessions.lease(&token).unwrap();
        sessions.revoke_all();
        assert!(sessions.active.is_empty());
        assert!(sessions.lease(&token).is_err());
        assert!(pending.check().is_err());
        sessions.register().unwrap();
    }
}
