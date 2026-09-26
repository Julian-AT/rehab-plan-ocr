use crate::{
    application::{failure, storage},
    runtime, AppError, EventValues, NativeApplication,
};
use reha_core::service::{agenda as core, Platform};
use serde::Serialize;
use std::sync::Arc;

#[derive(Clone, Debug, Serialize, uniffi::Record)]
pub struct AgendaReminderPreferences {
    pub enabled: bool,
    pub minutes: Option<u32>,
    pub sound: bool,
    pub preview: bool,
}
#[derive(Clone, Debug, Serialize, uniffi::Record)]
pub struct AgendaOwnedRecord {
    pub id: String,
    pub calendar_id: String,
    pub external_id: Option<String>,
    pub approved: EventValues,
    pub status: String,
    pub origin: String,
    pub import_id: Option<String>,
    pub operation_id: String,
}
impl From<reha_core::store::OwnedEventRecord> for AgendaOwnedRecord {
    fn from(value: reha_core::store::OwnedEventRecord) -> Self {
        Self {
            id: value.id,
            calendar_id: value.calendar_id,
            external_id: value.external_id,
            approved: value.approved.into(),
            status: value.status,
            origin: value.origin,
            import_id: value.import_id,
            operation_id: value.operation_id,
        }
    }
}
#[derive(Clone, Debug, Serialize, uniffi::Record)]
pub struct AgendaSyncRequest {
    pub records: Vec<AgendaOwnedRecord>,
    pub preferences: AgendaReminderPreferences,
    pub display_calendar_ids: Vec<String>,
}
#[derive(Clone, Debug, Default, uniffi::Record)]
pub struct AgendaSyncResult {
    pub maintenance_warnings: Vec<String>,
}
impl From<core::SyncRequest> for AgendaSyncRequest {
    fn from(value: core::SyncRequest) -> Self {
        Self {
            records: value.records.into_iter().map(Into::into).collect(),
            preferences: AgendaReminderPreferences {
                enabled: value.preferences.enabled,
                minutes: value.preferences.minutes,
                sound: value.preferences.sound,
                preview: value.preferences.preview,
            },
            display_calendar_ids: value.display_calendar_ids,
        }
    }
}
impl From<AgendaSyncResult> for core::SyncResult {
    fn from(value: AgendaSyncResult) -> Self {
        Self {
            maintenance_warnings: value.maintenance_warnings,
        }
    }
}
impl From<core::SyncResult> for AgendaSyncResult {
    fn from(value: core::SyncResult) -> Self {
        Self {
            maintenance_warnings: value.maintenance_warnings,
        }
    }
}
#[uniffi::export]
impl NativeApplication {
    pub async fn refresh_agenda(&self) -> Result<AgendaSyncResult, AppError> {
        let state = self.state.clone();
        let host: Arc<dyn Platform> = self.bridge.clone();
        runtime()
            .spawn(async move {
                let _guard = state.calendar_lock.lock().await;
                core::sync(&host, &state)
                    .await
                    .map(Into::into)
                    .map_err(failure)
            })
            .await
            .map_err(storage)?
    }
}
