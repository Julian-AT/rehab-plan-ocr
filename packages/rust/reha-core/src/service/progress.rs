//! Transient recognition updates. The worker lease owns completion, not a progress message.
#[cfg(any(feature = "onnx", test))]
use std::time::{Duration, Instant};

pub const BUDGET_MS: u64 = 60_000;

#[derive(Clone, Debug, PartialEq)]
pub struct ProgressUpdate {
    pub id: String,
    pub stage: String,
    pub elapsed_ms: u64,
    pub budget_ms: u64,
    pub draft_available: bool,
}
impl ProgressUpdate {
    pub fn new(id: impl Into<String>, stage: impl Into<String>) -> Self {
        Self {
            id: id.into(),
            stage: stage.into(),
            elapsed_ms: 0,
            budget_ms: BUDGET_MS,
            draft_available: false,
        }
    }
    pub(super) fn legacy(self) -> serde_json::Value {
        serde_json::json!({
            "id": self.id,
            "stage": self.stage,
            "elapsed_ms": self.elapsed_ms,
            "budget_ms": self.budget_ms,
            "draft_available": self.draft_available,
        })
    }
}

#[derive(Default)]
#[cfg(any(feature = "onnx", test))]
pub(super) struct ProgressThrottle(Option<Instant>);
#[cfg(any(feature = "onnx", test))]
impl ProgressThrottle {
    pub(super) fn allows(&mut self, now: Instant) -> bool {
        if self
            .0
            .is_some_and(|last| now.saturating_duration_since(last) < Duration::from_millis(100))
        {
            return false;
        }
        self.0 = Some(now);
        true
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::service::{Platform, Response};
    use serde_json::{json, Value};
    use std::sync::{atomic::AtomicBool, Arc, Mutex};

    #[derive(Default)]
    struct LegacyHost(Mutex<Vec<Value>>);
    impl Platform for LegacyHost {
        fn call(&self, _: &str, _: Value) -> Response<Value> {
            panic!("Progress must not dispatch a command")
        }
        fn progress(&self, value: Value) {
            self.0.lock().unwrap().push(value);
        }
    }

    #[test]
    fn typed_updates_keep_explicit_defaults_and_legacy_field_values() {
        let host = LegacyHost::default();
        let attempt = Arc::new(AtomicBool::new(false));
        host.update_progress(
            &attempt,
            ProgressUpdate::new("scan", "Original gespeichert"),
        );
        host.update_progress(
            &attempt,
            ProgressUpdate {
                id: "scan".into(),
                stage: "Felder nachlesen".into(),
                elapsed_ms: 1234,
                budget_ms: BUDGET_MS,
                draft_available: true,
            },
        );
        assert_eq!(
            *host.0.lock().unwrap(),
            [
                json!({"id":"scan", "stage":"Original gespeichert", "elapsed_ms":0,
                    "budget_ms":60000, "draft_available":false}),
                json!({"id":"scan", "stage":"Felder nachlesen", "elapsed_ms":1234,
                    "budget_ms":60000, "draft_available":true}),
            ]
        );
    }

    #[test]
    fn throttle_emits_first_then_at_most_once_per_hundred_milliseconds() {
        let start = Instant::now();
        let mut throttle = ProgressThrottle::default();
        assert!(throttle.allows(start));
        for millis in [0, 1, 99] {
            assert!(!throttle.allows(start + Duration::from_millis(millis)));
        }
        assert!(throttle.allows(start + Duration::from_millis(100)));
        assert!(!throttle.allows(start + Duration::from_millis(199)));
        assert!(throttle.allows(start + Duration::from_millis(200)));
    }
}
