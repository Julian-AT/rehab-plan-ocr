use super::*;

#[test]
fn stored_preferences_keep_defaults_unknown_keys_and_explicit_nulls() {
    let empty = decode_stored_preferences(json!({})).unwrap();
    assert_eq!(
        serde_json::to_value(empty).unwrap(),
        serde_json::to_value(Preferences::default()).unwrap()
    );
    let stored = json!({
        "future_preference": {"nested": [1, "kept in storage", null]},
        "display_selection_revision": u64::MAX,
        "timezone": "UTC", "reminder": null, "app_reminder_minutes": null,
        "calendar_id": "calendar-fixture", "display_calendar_ids": ["b", "a"],
        "completion_defaults": [{
            "id": "default-fixture", "clinic": "Testklinik", "treatment": "Test",
            "field": "duration_minutes", "value": u64::MAX,
            "future_default_metadata": {"enabled": true}
        }]
    });
    let previous: Preferences =
        serde_json::from_value(serde_json::to_value(&stored).unwrap()).unwrap();
    let decoded = decode_stored_preferences(stored).unwrap();
    assert_eq!(decoded.timezone, "UTC");
    assert_eq!(decoded.reminder, None);
    assert_eq!(decoded.app_reminder_minutes, None);
    assert!(decoded.reminder_sound);
    assert_eq!(decoded.appearance, "system");
    assert_eq!(decoded.display_calendar_ids, ["b", "a"]);
    assert_eq!(
        decoded.completion_defaults[0].value,
        FieldValue::Unsigned { value: u64::MAX }
    );
    assert_eq!(
        serde_json::to_value(decoded).unwrap(),
        serde_json::to_value(previous).unwrap()
    );
}

#[test]
fn malformed_known_preferences_remain_storage_errors() {
    for stored in [
        Value::Null,
        json!({"timezone": null}),
        json!({"reminder": -1}),
        json!({"display_calendar_ids": "invalid"}),
        json!({"completion_defaults": [{
            "id": "fixture", "clinic": "", "treatment": "", "field": "location",
            "value": {"unsupported": true}
        }]}),
    ] {
        let previous =
            serde_json::from_value::<Preferences>(serde_json::to_value(&stored).unwrap());
        let previous_error = match previous {
            Err(error) => error.to_string(),
            Ok(_) => panic!("invalid fixture unexpectedly decoded"),
        };
        match decode_stored_preferences(stored) {
            Err(AppError::Storage { message }) => assert_eq!(message, previous_error),
            _ => panic!("invalid stored preferences must remain a storage error"),
        }
    }
}
