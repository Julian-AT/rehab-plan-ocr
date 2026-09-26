//! Import effects share the journal's domain values without routing by command strings.
use crate::contracts::{CalendarOperation, EventValues};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Snapshot {
    pub current: BTreeMap<String, EventValues>,
    // Older compatibility hosts did not report protected identities. A malformed
    // supplied list is an error; it must never silently become an empty list.
    #[serde(default)]
    pub protected_ids: Vec<String>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct ApplyRequest {
    pub operation: CalendarOperation,
    pub recovery_only: bool,
}

pub(super) fn invalid_response(error: impl std::fmt::Display) -> super::ServiceError {
    super::ServiceError::Storage(error.to_string())
}

#[cfg(test)]
mod tests {
    use crate::service::{Platform, Response, ServiceError};
    use serde_json::{json, Value};

    struct LegacyHost(Value);
    impl Platform for LegacyHost {
        fn call(&self, command: &str, arguments: Value) -> Response<Value> {
            assert_eq!(command, "snapshot");
            assert_eq!(arguments, json!({"records":[]}));
            Ok(self.0.clone())
        }
        fn progress(&self, _: Value) {}
    }

    #[test]
    fn legacy_snapshot_keeps_protection_and_rejects_malformed_protection() {
        let protected = LegacyHost(json!({"current":{}, "protected_ids":["external-series"]}));
        assert_eq!(
            protected.import_snapshot(vec![]).unwrap().protected_ids,
            ["external-series"]
        );
        assert!(LegacyHost(json!({"current":{}}))
            .import_snapshot(vec![])
            .unwrap()
            .protected_ids
            .is_empty());
        for protection in [
            json!(null),
            json!(true),
            json!("external-series"),
            json!([3]),
        ] {
            assert!(matches!(
                LegacyHost(json!({"current":{}, "protected_ids":protection}))
                    .import_snapshot(vec![]),
                Err(ServiceError::Storage(_))
            ));
        }
    }
}
