//! Explicit local-link repair. Legacy commands delegate to the same core operation.
use crate::{
    application::{failure, storage},
    runtime, AppError, EventConfirmation, NativeApplication,
};
use reha_core::service::{calendar_mutations::Confirmation, calendar_repair as core};

#[derive(Clone, Debug, uniffi::Record)]
pub struct CalendarRepairSelection {
    pub id: String,
    pub fingerprint: String,
}
#[derive(Clone, Debug, uniffi::Record)]
pub struct CalendarRepairIssue {
    pub id: String,
    pub fingerprint: String,
    pub calendar_id: String,
    pub title: String,
    pub start_utc: String,
    pub end_utc: String,
    pub timezone: String,
    pub reason: String,
}
#[derive(Clone, Debug, uniffi::Record)]
pub struct CalendarRepairReport {
    pub issues: Vec<CalendarRepairIssue>,
    pub missing_calendar_ids: Vec<String>,
    pub relinked_count: u64,
    pub removed_count: u64,
    pub cleanup_blocked: bool,
    pub refresh_warning: Option<String>,
}
impl From<core::Report> for CalendarRepairReport {
    fn from(value: core::Report) -> Self {
        Self {
            issues: value
                .issues
                .into_iter()
                .map(|v| CalendarRepairIssue {
                    id: v.id,
                    fingerprint: v.fingerprint,
                    calendar_id: v.calendar_id,
                    title: v.title,
                    start_utc: v.start_utc,
                    end_utc: v.end_utc,
                    timezone: v.timezone,
                    reason: v.reason,
                })
                .collect(),
            missing_calendar_ids: value.missing_calendar_ids,
            relinked_count: value.relinked_count,
            removed_count: value.removed_count,
            cleanup_blocked: value.cleanup_blocked,
            refresh_warning: value.refresh_warning,
        }
    }
}
impl NativeApplication {
    async fn repair_calendar(
        &self,
        request: core::Request,
    ) -> Result<CalendarRepairReport, AppError> {
        let state = self.state.clone();
        let host = self.bridge.clone();
        runtime()
            .spawn(async move {
                core::execute(host, &state, request)
                    .await
                    .map(Into::into)
                    .map_err(failure)
            })
            .await
            .map_err(storage)?
    }
}
#[uniffi::export]
impl NativeApplication {
    pub async fn inspect_calendar_repair(&self) -> Result<CalendarRepairReport, AppError> {
        self.repair_calendar(core::Request::Inspect).await
    }
    pub async fn confirm_calendar_repair(
        &self,
        selection: Vec<CalendarRepairSelection>,
        confirmation: EventConfirmation,
    ) -> Result<CalendarRepairReport, AppError> {
        self.repair_calendar(core::Request::Confirm {
            selection: selection
                .into_iter()
                .map(|v| core::Selection {
                    id: v.id,
                    fingerprint: v.fingerprint,
                })
                .collect(),
            confirmation: match confirmation {
                EventConfirmation::Button => Confirmation::Button,
            },
        })
        .await
    }
}
