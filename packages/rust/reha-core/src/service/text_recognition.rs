//! Binary native recognition boundary. Only old hosts serialize the effect.
//! The manifest remains opaque provenance for the existing persisted pipeline run.
use super::{Response, ServiceError};
use crate::contracts::{Observation, Region};
use base64::{engine::general_purpose::STANDARD, Engine};
use serde_json::{json, Value};

pub const MAXIMUM_BYTES: usize = 256 * 1024 * 1024;
pub const MAXIMUM_BUDGET_MS: u64 = 60_000;

#[derive(Clone, Debug)]
pub struct Request {
    /// Upright encoded page/crop, already prepared by the common photo pipeline.
    pub image: Vec<u8>,
    pub budget_ms: u64,
}

impl Request {
    pub fn validate(&self) -> Response<()> {
        if self.image.is_empty() || self.image.len() > MAXIMUM_BYTES {
            return Err(ServiceError::Validation(
                "Bild für Vision fehlt oder ist zu groß.".into(),
            ));
        }
        if self.budget_ms == 0 {
            return Err(ServiceError::Timeout("recognize".into()));
        }
        if self.budget_ms > MAXIMUM_BUDGET_MS {
            return Err(ServiceError::Validation("Zeitbudget ungültig.".into()));
        }
        Ok(())
    }

    pub fn legacy_arguments(&self) -> Response<Value> {
        self.validate()?;
        Ok(json!({"base64":STANDARD.encode(&self.image), "budget_ms":self.budget_ms}))
    }
}

#[derive(Clone, Debug)]
pub struct Output {
    pub regions: Vec<Region>,
    pub observations: Vec<Observation>,
    pub duration_ms: u64,
    pub manifest: Value,
}

impl Output {
    pub fn from_legacy(value: Value) -> Response<Self> {
        let invalid =
            |error| ServiceError::Storage(format!("Ungültige Erkennungsantwort: {error}"));
        Ok(Self {
            regions: serde_json::from_value(value["regions"].clone()).map_err(invalid)?,
            observations: serde_json::from_value(value["observations"].clone()).map_err(invalid)?,
            duration_ms: value["duration_ms"].as_u64().unwrap_or(0),
            manifest: value["manifest"].clone(),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::service::Platform;
    use std::sync::Mutex;

    struct LegacyHost {
        calls: Mutex<Vec<(String, Value)>>,
        result: Response<Value>,
    }
    impl Platform for LegacyHost {
        fn call(&self, command: &str, arguments: Value) -> Response<Value> {
            self.calls.lock().unwrap().push((command.into(), arguments));
            self.result.clone()
        }
        fn progress(&self, _: Value) {}
    }
    fn request() -> Request {
        Request {
            image: vec![0, 255, 1, 128],
            budget_ms: 1234,
        }
    }
    #[test]
    fn legacy_adapter_retains_image_budget_geometry_alternatives_and_provenance() {
        let response = json!({
            "regions":[{"id":"r1","polygon":[{"x":1.25,"y":7.5}],
                "frame":"page","kind":"text","parent":"page","children":[]}],
            "observations":[{"id":"o1","text":"Raum 204","region_ids":["r1"],
                "engine":"Apple Vision","score":0.75,"alternatives":["Raum 2O4"]}],
            "duration_ms":123,"manifest":{"engine":"Apple Vision","revision":3,
                "system_version":"fixture","language_correction":false,"future":[1,null]}
        });
        let host = LegacyHost {
            calls: Mutex::new(vec![]),
            result: Ok(response.clone()),
        };
        let output = host.recognize_text(request()).unwrap();
        let calls = host.calls.lock().unwrap();
        assert_eq!(
            calls.as_slice(),
            [("recognize".into(), request().legacy_arguments().unwrap())]
        );
        assert_eq!(
            STANDARD
                .decode(calls[0].1["base64"].as_str().unwrap())
                .unwrap(),
            request().image
        );
        assert_eq!(
            serde_json::to_value(output.regions).unwrap(),
            response["regions"]
        );
        assert_eq!(
            serde_json::to_value(output.observations).unwrap(),
            response["observations"]
        );
        assert_eq!(output.duration_ms, 123);
        assert_eq!(output.manifest, response["manifest"]);
    }
    #[test]
    fn malformed_output_is_storage_failure_without_discarding_native_error_identity() {
        for response in [json!({}), json!({"regions":[],"observations":"corrupt"})] {
            assert!(matches!(
                Output::from_legacy(response),
                Err(ServiceError::Storage(_))
            ));
        }
        for error in [
            ServiceError::PermissionDenied,
            ServiceError::Timeout("recognize".into()),
            ServiceError::Cancelled,
        ] {
            let host = LegacyHost {
                calls: Mutex::new(vec![]),
                result: Err(error.clone()),
            };
            assert!(matches!(host.recognize_text(request()),Err(actual) if actual == error));
        }
        let output = Output::from_legacy(json!({"regions":[],"observations":[]})).unwrap();
        assert_eq!(output.duration_ms, 0);
        assert_eq!(output.manifest, Value::Null);
    }
    #[test]
    fn invalid_input_never_reaches_legacy_host() {
        let host = LegacyHost {
            calls: Mutex::new(vec![]),
            result: Ok(Value::Null),
        };
        for input in [
            Request {
                image: vec![],
                ..request()
            },
            Request {
                budget_ms: 0,
                ..request()
            },
            Request {
                budget_ms: 60_001,
                ..request()
            },
        ] {
            assert!(host.recognize_text(input).is_err());
        }
        assert!(host.calls.lock().unwrap().is_empty());
    }
}
