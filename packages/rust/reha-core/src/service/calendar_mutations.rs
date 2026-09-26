//! Typed editing contracts. Serde is retained for existing journals and legacy adapters.
use super::{calendar_reads::Event, Response, ServiceError};
use serde::{Deserialize, Deserializer, Serialize, Serializer};

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Kind {
    Create,
    Update,
    Remove,
}

/// Missing, explicit null and an integer have different meanings in an edit.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum ReminderChange {
    #[default]
    Unchanged,
    Disabled,
    Minutes(u32),
}
impl ReminderChange {
    pub fn is_unchanged(&self) -> bool {
        *self == Self::Unchanged
    }
}
impl Serialize for ReminderChange {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        match self {
            Self::Minutes(minutes) => serializer.serialize_u32(*minutes),
            Self::Disabled | Self::Unchanged => serializer.serialize_none(),
        }
    }
}
impl<'de> Deserialize<'de> for ReminderChange {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        Ok(Option::<u32>::deserialize(deserializer)?
            .map(Self::Minutes)
            .unwrap_or(Self::Disabled))
    }
}
#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Patch {
    #[serde(
        default,
        deserialize_with = "text_change",
        skip_serializing_if = "Option::is_none"
    )]
    pub title: Option<String>,
    #[serde(
        default,
        deserialize_with = "text_change",
        skip_serializing_if = "Option::is_none"
    )]
    pub start_utc: Option<String>,
    #[serde(
        default,
        deserialize_with = "text_change",
        skip_serializing_if = "Option::is_none"
    )]
    pub end_utc: Option<String>,
    #[serde(
        default,
        deserialize_with = "text_change",
        skip_serializing_if = "Option::is_none"
    )]
    pub timezone: Option<String>,
    #[serde(
        default,
        deserialize_with = "text_change",
        skip_serializing_if = "Option::is_none"
    )]
    pub location: Option<String>,
    #[serde(default, skip_serializing_if = "ReminderChange::is_unchanged")]
    pub reminder_minutes: ReminderChange,
}
fn previous_reminder(value: Option<i64>) -> Response<ReminderChange> {
    match value {
        None => Ok(ReminderChange::Disabled),
        Some(minutes) if (0..=10080).contains(&minutes) => {
            Ok(ReminderChange::Minutes(minutes as u32))
        }
        Some(_) => Err(ServiceError::Validation("Erinnerung ungültig.".into())),
    }
}
fn text_change<'de, D: Deserializer<'de>>(d: D) -> Result<Option<String>, D::Error> {
    String::deserialize(d).map(Some)
}
impl Patch {
    pub fn is_empty(&self) -> bool {
        *self == Self::default()
    }
    pub fn reversed(&self, before: &super::calendar_reads::Values) -> Response<Self> {
        Ok(Self {
            title: self.title.as_ref().map(|_| before.title.clone()),
            start_utc: self.start_utc.as_ref().map(|_| before.start_utc.clone()),
            end_utc: self.end_utc.as_ref().map(|_| before.end_utc.clone()),
            timezone: self.timezone.as_ref().map(|_| before.timezone.clone()),
            location: self.location.as_ref().map(|_| before.location.clone()),
            reminder_minutes: if self.reminder_minutes.is_unchanged() {
                ReminderChange::Unchanged
            } else {
                previous_reminder(before.reminder_minutes)?
            },
        })
    }
    pub fn restoring(before: &super::calendar_reads::Values) -> Response<Self> {
        Ok(Self {
            title: Some(before.title.clone()),
            start_utc: Some(before.start_utc.clone()),
            end_utc: Some(before.end_utc.clone()),
            timezone: Some(before.timezone.clone()),
            location: Some(before.location.clone()),
            reminder_minutes: previous_reminder(before.reminder_minutes)?,
        })
    }
    pub fn validate(&self, kind: Kind, before: Option<&Event>) -> Response<()> {
        let invalid = |message: &str| ServiceError::Validation(message.into());
        if kind == Kind::Remove {
            return if self.is_empty() {
                Ok(())
            } else {
                Err(invalid("Löschung enthält neue Werte."))
            };
        }
        if self.is_empty() {
            return Err(invalid("Aktion fehlt."));
        }
        let old = before.map(|e| &e.values);
        let field =
            |new: &Option<String>, old: Option<&String>| new.clone().or_else(|| old.cloned());
        let title =
            field(&self.title, old.map(|v| &v.title)).ok_or_else(|| invalid("title fehlt."))?;
        if title.trim().is_empty() {
            return Err(invalid("Bezeichnung fehlt."));
        }
        if title.len() > 4000
            || field(&self.location, old.map(|v| &v.location))
                .as_ref()
                .is_some_and(|v| v.len() > 4000)
        {
            return Err(invalid("Termintext ungültig."));
        }
        let start = field(&self.start_utc, old.map(|v| &v.start_utc))
            .ok_or_else(|| invalid("Beginn fehlt."))?;
        let end =
            field(&self.end_utc, old.map(|v| &v.end_utc)).ok_or_else(|| invalid("Ende fehlt."))?;
        let start = chrono::DateTime::parse_from_rfc3339(&start)
            .map_err(|_| invalid("Beginn ungültig."))?;
        let end =
            chrono::DateTime::parse_from_rfc3339(&end).map_err(|_| invalid("Ende ungültig."))?;
        if end <= start || end.signed_duration_since(start).num_days() > 366 {
            return Err(invalid("Ende muss nach Beginn liegen (maximal ein Jahr)."));
        }
        field(&self.timezone, old.map(|v| &v.timezone))
            .ok_or_else(|| invalid("Zeitzone fehlt."))?
            .parse::<chrono_tz::Tz>()
            .map_err(|_| invalid("Zeitzone ungültig."))?;
        let reminder = match self.reminder_minutes {
            ReminderChange::Unchanged => old.and_then(|v| v.reminder_minutes),
            ReminderChange::Disabled => None,
            ReminderChange::Minutes(v) => Some(i64::from(v)),
        };
        if reminder.is_some_and(|v| !(0..=10080).contains(&v)) {
            return Err(invalid("Erinnerung ungültig."));
        }
        Ok(())
    }
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct PreviewRequest {
    pub session: String,
    #[serde(default)]
    pub revision: u64,
    pub kind: Kind,
    pub calendar_id: String,
    pub event: Option<Event>,
    pub patch: Patch,
    #[serde(default = "manual_origin")]
    pub origin: String,
}
fn manual_origin() -> String {
    "manual".into()
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct ConfirmRequest {
    pub token: String,
    pub session: String,
    pub revision: u64,
    pub confirmation: Confirmation,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Confirmation {
    Button,
    /// Legacy adapters may report a spoken or otherwise unsupported confirmation.
    /// It must consume the volatile proposal without authorizing a write.
    #[serde(other)]
    MissingVisibleButton,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct UndoRequest {
    pub id: String,
    pub session: String,
    #[serde(default)]
    pub revision: u64,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Proposal {
    pub token: String,
    pub session: String,
    pub revision: u64,
    pub expires_at: i64,
    pub kind: Kind,
    pub calendar_id: String,
    pub calendar_title: String,
    pub before: Option<Event>,
    pub patch: Patch,
    pub undo_of: Option<String>,
    #[serde(default)]
    pub owned_id: Option<String>,
    #[serde(default = "unknown_origin")]
    pub origin: String,
}
fn unknown_origin() -> String {
    "unknown".into()
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(untagged)]
pub enum PreviewResult {
    Proposal { proposal: Box<Proposal> },
    SystemEditor { system_editor: Box<Event> },
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Status {
    Saved,
    Failed,
    Uncertain,
    Conflict,
    Acknowledged,
}
#[derive(Clone, Debug, Deserialize)]
pub struct MutationResult {
    pub status: Status,
    #[serde(default)]
    pub event: Option<Event>,
    #[serde(default)]
    pub operation_id: Option<String>,
    #[serde(default)]
    pub message: Option<String>,
    #[serde(default)]
    pub maintenance_warnings: Vec<String>,
}
impl MutationResult {
    pub fn uncertain() -> Self {
        Self {
            status: Status::Uncertain,
            event: None,
            operation_id: None,
            message: Some("Schreibstatus unklar. Abgleich erforderlich.".into()),
            maintenance_warnings: vec![],
        }
    }
}
impl Serialize for MutationResult {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        use serde::ser::SerializeMap;
        let mut value = serializer.serialize_map(None)?;
        value.serialize_entry("status", &self.status)?;
        if self.status == Status::Saved || self.event.is_some() {
            value.serialize_entry("event", &self.event)?;
        }
        if let Some(id) = &self.operation_id {
            value.serialize_entry("operation_id", id)?;
        }
        if let Some(message) = &self.message {
            value.serialize_entry("message", message)?;
        }
        if !self.maintenance_warnings.is_empty() {
            value.serialize_entry("maintenance_warnings", &self.maintenance_warnings)?;
        }
        value.end()
    }
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct MutationRequest {
    pub proposal: Proposal,
    pub recovery_only: bool,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Destination {
    pub id: String,
    pub title: String,
    pub source: String,
    pub writable: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub color_components: Option<Vec<f64>>,
}

use super::{failure, AppState, Platform};
use serde_json::Value;
use std::sync::Arc;

fn preferences(state: &AppState) -> Response<Value> {
    super::settings::settings_value(state, None)
}
fn selected(p: &Value, id: &str) -> bool {
    p["display_calendar_ids"]
        .as_array()
        .is_some_and(|ids| ids.iter().any(|v| v.as_str() == Some(id)))
}
pub async fn destinations(platform: Arc<dyn Platform>) -> Response<Vec<Destination>> {
    tokio::task::spawn_blocking(move || platform.event_calendars())
        .await
        .map_err(failure)?
}
async fn check_calendar(
    platform: &Arc<dyn Platform>,
    state: &AppState,
    id: &str,
    create: bool,
) -> Response<String> {
    let p = preferences(state)?;
    let imported = state
        .store
        .lock()
        .map_err(failure)?
        .owned_records()
        .map_err(failure)?
        .iter()
        .any(|r| r.calendar_id == id && r.status == "saved");
    if !(selected(&p, id) || !create && imported || create && p["calendar_id"].as_str() == Some(id))
    {
        return Err("Kalenderauswahl enthält diesen Kalender nicht.".into());
    }
    let all = destinations(platform.clone()).await?;
    let target = all
        .iter()
        .find(|c| c.id == id)
        .ok_or("Kalender nicht verfügbar.")?;
    if !target.writable {
        return Err("Dieser Kalender ist schreibgeschützt.".into());
    }
    Ok(format!("{} · {}", target.title, target.source))
}
fn require_selected_event(state: &AppState, calendar: &str, event: &Event) -> Response<()> {
    if !selected(&preferences(state)?, calendar) {
        let records = state
            .store
            .lock()
            .map_err(failure)?
            .owned_records()
            .map_err(failure)?;
        if !records.iter().any(|r| {
            r.status == "saved"
                && r.calendar_id == calendar
                && r.external_id.as_deref() == Some(event.external_id.as_str())
                && event.metadata["url"].as_str()
                    == Some(format!("reha-calendar://event/{}", r.id).as_str())
        }) {
            return Err("Dieser Termin gehört nicht zur Kalenderauswahl.".into());
        }
    }
    Ok(())
}
pub fn register(state: &AppState) -> Response<String> {
    state.event_sessions.lock().map_err(failure)?.register()
}
pub fn invalidate(state: &AppState, session: &str) -> Response<()> {
    let mut sessions = state.event_sessions.lock().map_err(failure)?;
    sessions.revoke(session);
    state
        .event_proposals
        .lock()
        .map_err(failure)?
        .retain(|_, p| p.session != session);
    Ok(())
}
pub async fn preview(
    platform: Arc<dyn Platform>,
    state: &AppState,
    request: PreviewRequest,
) -> Response<PreviewResult> {
    preview_impl(platform, state, request, None).await
}
async fn preview_impl(
    platform: Arc<dyn Platform>,
    state: &AppState,
    request: PreviewRequest,
    undo_of: Option<String>,
) -> Response<PreviewResult> {
    let lease = state
        .event_sessions
        .lock()
        .map_err(failure)?
        .lease(&request.session)?;
    let _guard = state.calendar_lock.lock().await;
    lease.check()?;
    let title = check_calendar(
        &platform,
        state,
        &request.calendar_id,
        request.kind == Kind::Create,
    )
    .await?;
    let before = if request.kind == Kind::Create {
        None
    } else {
        let supplied = request.event.as_ref().ok_or("Termin fehlt.")?;
        if supplied.calendar_id != request.calendar_id {
            return Err("Kalenderzuordnung geändert.".into());
        }
        let event = super::calendar_reads::resolve(&platform, supplied)
            .await?
            .ok_or("Termin nicht verfügbar. Kalender neu laden.")?;
        if undo_of.is_some() && event != *supplied {
            return Err("Spätere Kalenderänderung geschützt. Rückgängig nicht möglich.".into());
        }
        require_selected_event(state, &request.calendar_id, &event)?;
        if event.system_only {
            lease.check()?;
            return Ok(PreviewResult::SystemEditor {
                system_editor: Box::new(event),
            });
        }
        Some(event)
    };
    request.patch.validate(request.kind, before.as_ref())?;
    let owned_id = if let Some(id) = &undo_of {
        let old = state
            .store
            .lock()
            .map_err(failure)?
            .event_mutation(id)
            .map_err(failure)?
            .ok_or("Verlaufseintrag fehlt.")?;
        serde_json::from_value::<Proposal>(old["proposal"].clone())
            .map_err(failure)?
            .owned_id
    } else if request.kind == Kind::Create {
        Some(uuid::Uuid::new_v4().to_string())
    } else {
        let event = before.as_ref().ok_or("Termin fehlt.")?;
        state
            .store
            .lock()
            .map_err(failure)?
            .owned_records()
            .map_err(failure)?
            .into_iter()
            .find(|r| {
                r.external_id.as_deref() == Some(event.external_id.as_str())
                    && event.metadata["url"].as_str()
                        == Some(format!("reha-calendar://event/{}", r.id).as_str())
            })
            .map(|r| r.id)
    };
    let origin = if undo_of.is_some() {
        "unknown"
    } else if request.origin == "voice" {
        "voice"
    } else {
        "manual"
    }
    .into();
    let proposal = Proposal {
        token: uuid::Uuid::new_v4().to_string(),
        session: request.session.clone(),
        revision: request.revision,
        expires_at: chrono::Utc::now().timestamp() + 300,
        kind: request.kind,
        calendar_id: request.calendar_id,
        calendar_title: title,
        before,
        patch: request.patch,
        undo_of,
        owned_id,
        origin,
    };
    // Publication and revocation share the registry lock; a retired lease stays revoked.
    let _sessions = state.event_sessions.lock().map_err(failure)?;
    lease.check()?;
    let mut proposals = state.event_proposals.lock().map_err(failure)?;
    proposals.retain(|_, p| {
        p.session != request.session && p.expires_at > chrono::Utc::now().timestamp()
    });
    proposals.insert(proposal.token.clone(), proposal.clone());
    Ok(PreviewResult::Proposal {
        proposal: Box::new(proposal),
    })
}
pub async fn mutate(
    platform: Arc<dyn Platform>,
    request: MutationRequest,
) -> Response<MutationResult> {
    tokio::task::spawn_blocking(move || platform.mutate_event(request))
        .await
        .map_err(failure)?
}
pub async fn confirm(
    platform: Arc<dyn Platform>,
    state: &AppState,
    request: ConfirmRequest,
) -> Response<MutationResult> {
    let _guard = state.calendar_lock.lock().await;
    // Exact retries read the durable result before checking a retired UI session.
    if let Some(item) = state
        .store
        .lock()
        .map_err(failure)?
        .event_mutation(&request.token)
        .map_err(failure)?
    {
        return if item["result"].is_object() {
            serde_json::from_value(item["result"].clone()).map_err(failure)
        } else {
            Ok(MutationResult::uncertain())
        };
    }
    let proposal = state
        .event_proposals
        .lock()
        .map_err(failure)?
        .remove(&request.token)
        .ok_or("Vorschau abgelaufen. Erneut prüfen.")?;
    if request.confirmation != Confirmation::Button
        || request.session != proposal.session
        || request.revision != proposal.revision
        || proposal.expires_at < chrono::Utc::now().timestamp()
    {
        return Err("Freigabe abgelaufen. Erneut prüfen und Schaltfläche betätigen.".into());
    }
    let lease = state
        .event_sessions
        .lock()
        .map_err(failure)?
        .lease(&proposal.session)?;
    check_calendar(
        &platform,
        state,
        &proposal.calendar_id,
        proposal.kind == Kind::Create,
    )
    .await?;
    if let Some(before) = &proposal.before {
        require_selected_event(state, &proposal.calendar_id, before)?;
        if super::calendar_reads::resolve(&platform, before)
            .await?
            .as_ref()
            != Some(before)
        {
            return Err(
                "Termin wurde geändert. Neue Vorschau und Bestätigung erforderlich.".into(),
            );
        }
    }
    {
        let _sessions = state.event_sessions.lock().map_err(failure)?;
        lease.check()?;
        let store = state.store.lock().map_err(failure)?;
        if !store.pending().map_err(failure)?.is_empty()
            || store.event_history().map_err(failure)?.iter().any(|h| {
                ["pending", "uncertain"].contains(&h["status"].as_str().unwrap_or_default())
            })
        {
            return Err("Unklare Schreibvorgänge zuerst abgleichen.".into());
        }
        store.begin_event_mutation(&proposal).map_err(failure)?;
    }
    let mut result = mutate(
        platform.clone(),
        MutationRequest {
            proposal,
            recovery_only: false,
        },
    )
    .await
    .unwrap_or_else(|_| MutationResult::uncertain());
    state
        .store
        .lock()
        .map_err(failure)?
        .finish_event_mutation(
            &request.token,
            &serde_json::to_value(&result).map_err(failure)?,
        )
        .map_err(failure)?;
    result
        .maintenance_warnings
        .extend(super::agenda::sync_warnings(&platform, state).await);
    Ok(result)
}
pub async fn undo(
    platform: Arc<dyn Platform>,
    state: &AppState,
    request: UndoRequest,
) -> Response<PreviewResult> {
    let history = state
        .store
        .lock()
        .map_err(failure)?
        .event_history()
        .map_err(failure)?;
    let item = history
        .iter()
        .find(|h| h["id"] == request.id)
        .ok_or("Verlaufseintrag fehlt.")?;
    if item["status"] != "saved" || !item["undone_by"].is_null() {
        return Err("Dieser Vorgang kann nicht erneut rückgängig gemacht werden.".into());
    }
    let old: Proposal = serde_json::from_value(item["proposal"].clone()).map_err(failure)?;
    let after: Option<Event> =
        serde_json::from_value(item["result"]["event"].clone()).map_err(failure)?;
    let (kind, event, patch) = match old.kind {
        Kind::Create => (Kind::Remove, after, Patch::default()),
        Kind::Update => (
            Kind::Update,
            after,
            old.patch.reversed(
                &old.before
                    .as_ref()
                    .ok_or("Wiederherstellungsdaten fehlen.")?
                    .values,
            )?,
        ),
        Kind::Remove => (
            Kind::Create,
            None,
            Patch::restoring(
                &old.before
                    .as_ref()
                    .ok_or("Wiederherstellungsdaten fehlen.")?
                    .values,
            )?,
        ),
    };
    if kind != Kind::Create {
        let supplied = event.as_ref().ok_or("Termin fehlt.")?;
        if super::calendar_reads::resolve(&platform, supplied)
            .await?
            .as_ref()
            != Some(supplied)
        {
            return Err("Spätere Kalenderänderung geschützt. Rückgängig nicht möglich.".into());
        }
    }
    preview_impl(
        platform,
        state,
        PreviewRequest {
            session: request.session,
            revision: request.revision,
            kind,
            calendar_id: old.calendar_id,
            event,
            patch,
            origin: "unknown".into(),
        },
        Some(old.token),
    )
    .await
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn unsupported_historical_reminders_are_not_silently_disabled_during_undo() {
        assert!(previous_reminder(Some(-1)).is_err());
        assert!(previous_reminder(Some(10081)).is_err());
        assert_eq!(previous_reminder(None).unwrap(), ReminderChange::Disabled);
        assert_eq!(
            previous_reminder(Some(0)).unwrap(),
            ReminderChange::Minutes(0)
        );
    }

    #[test]
    fn patch_journal_preserves_absent_null_and_explicit_zero() {
        for (value, expected) in [
            (json!({"location":""}), ReminderChange::Unchanged),
            (json!({"reminder_minutes":null}), ReminderChange::Disabled),
            (json!({"reminder_minutes":0}), ReminderChange::Minutes(0)),
            (json!({"reminder_minutes":60}), ReminderChange::Minutes(60)),
        ] {
            let patch: Patch = serde_json::from_value(value.clone()).unwrap();
            assert_eq!(patch.reminder_minutes, expected);
            assert_eq!(serde_json::to_value(patch).unwrap(), value);
        }
        for invalid in [
            json!({"title":null}),
            json!({"location":false}),
            json!({"notes":"invented"}),
            json!({"reminder_minutes":1.5}),
            json!({"reminder_minutes":-1}),
        ] {
            assert!(serde_json::from_value::<Patch>(invalid).is_err());
        }
    }

    #[test]
    fn historical_results_keep_acknowledged_and_saved_deletion_shapes() {
        for value in [
            json!({"status":"acknowledged","message":"Checked by the user"}),
            json!({"status":"saved","event":null,"operation_id":"saved-id"}),
            json!({"status":"uncertain","message":"Interrupted"}),
            json!({"status":"saved","event":null,"maintenance_warnings":["Reminder warning"]}),
        ] {
            let result: MutationResult = serde_json::from_value(value.clone()).unwrap();
            assert_eq!(serde_json::to_value(result).unwrap(), value);
        }
    }
}
