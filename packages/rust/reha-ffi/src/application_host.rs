use super::errors::platform_failure;
use super::*;
use reha_core::service::Platform;
use std::sync::atomic::{AtomicBool, Ordering};

pub(super) struct ProgressEntry {
    pub(super) attempt: Arc<AtomicBool>,
    pub(super) value: JobProgress,
}
pub(crate) struct HostBridge {
    pub(super) host: Box<dyn AppleHost>,
    pub(super) progress: Mutex<HashMap<String, ProgressEntry>>,
    pub(super) jobs: Arc<RecognitionJobs>,
}
impl HostBridge {
    pub(super) fn finish_progress(&self, id: &str, attempt: &Arc<AtomicBool>, state: JobState) {
        if let Ok(mut progress) = self.progress.lock() {
            if let Some(entry) = progress.get_mut(id) {
                if Arc::ptr_eq(&entry.attempt, attempt) && entry.value.state == JobState::Running {
                    entry.value.state = state;
                }
            }
        }
    }
}
impl Platform for HostBridge {
    fn recognize_text(
        &self,
        request: service::text_recognition::Request,
    ) -> service::Response<service::text_recognition::Output> {
        request.validate()?;
        self.host
            .recognize_text(request.into())
            .map(Into::into)
            .map_err(platform_failure)
    }
    fn resolve_owned_event(
        &self,
        record: reha_core::store::OwnedEventRecord,
    ) -> service::Response<service::calendar_links::OwnedResolution> {
        self.host
            .resolve_owned_event(record.into())
            .and_then(TryInto::try_into)
            .map_err(platform_failure)
    }
    fn inspect_calendar_links(
        &self,
        records: Vec<reha_core::store::OwnedEventRecord>,
    ) -> service::Response<service::calendar_links::Inspection> {
        self.host
            .inspect_calendar_links(records.into_iter().map(Into::into).collect())
            .map(Into::into)
            .map_err(platform_failure)
    }
    fn import_snapshot(
        &self,
        records: Vec<domain::ImportRecord>,
    ) -> service::Response<service::calendar_imports::Snapshot> {
        let snapshot = self
            .host
            .snapshot(records.into_iter().map(Into::into).collect())
            .map_err(platform_failure)?;
        Ok(service::calendar_imports::Snapshot {
            current: snapshot
                .current
                .into_iter()
                .map(|(id, value)| (id, value.into()))
                .collect(),
            protected_ids: snapshot.protected_ids,
        })
    }
    fn apply_import(
        &self,
        request: service::calendar_imports::ApplyRequest,
    ) -> service::Response<domain::CalendarResult> {
        let operation = request.operation.try_into().map_err(platform_failure)?;
        self.host
            .apply(operation, request.recovery_only)
            .map(Into::into)
            .map_err(platform_failure)
    }
    fn synchronize_agenda(
        &self,
        request: service::agenda::SyncRequest,
    ) -> service::Response<service::agenda::SyncResult> {
        self.host
            .sync_agenda(request.into())
            .map(Into::into)
            .map_err(platform_failure)
    }
    fn calendar_status(
        &self,
    ) -> service::Response<service::calendar_administration::PlatformStatus> {
        self.host
            .calendar_status()
            .map(Into::into)
            .map_err(platform_failure)
    }

    fn forget_calendar(&self) -> service::Response<()> {
        self.host.forget_calendar().map_err(platform_failure)
    }

    fn query_calendar(
        &self,
        request: service::calendar_reads::Query,
    ) -> service::Response<service::calendar_reads::QueryResult> {
        self.host
            .query_calendar(request.into())
            .and_then(TryInto::try_into)
            .map_err(platform_failure)
    }
    fn resolve_calendar_event(
        &self,
        reference: service::calendar_reads::Reference,
    ) -> service::Response<Option<service::calendar_reads::Event>> {
        self.host
            .resolve_calendar_event(reference.into())
            .and_then(|event| event.map(TryInto::try_into).transpose())
            .map_err(platform_failure)
    }
    fn event_calendars(&self) -> service::Response<Vec<service::calendar_mutations::Destination>> {
        self.host
            .event_calendars()
            .map(|items| items.into_iter().map(Into::into).collect())
            .map_err(platform_failure)
    }
    fn mutate_event(
        &self,
        request: service::calendar_mutations::MutationRequest,
    ) -> service::Response<service::calendar_mutations::MutationResult> {
        self.host
            .mutate_event(request.into())
            .and_then(TryInto::try_into)
            .map_err(platform_failure)
    }
    fn decode_photo(&self, bytes: &[u8]) -> service::Response<Vec<u8>> {
        self.host
            .decode_photo(bytes.to_vec())
            .map_err(platform_failure)
    }
    fn overlaps(
        &self,
        events: std::collections::BTreeMap<String, domain::EventValues>,
        exclude: Vec<String>,
    ) -> service::Response<Option<Vec<domain::CalendarOverlap>>> {
        self.host
            .overlaps(
                events
                    .into_iter()
                    .map(|(id, values)| (id, values.into()))
                    .collect(),
                exclude,
            )
            .map(|overlaps| Some(overlaps.into_iter().map(Into::into).collect()))
            .map_err(platform_failure)
    }
    fn cancellation_flag(&self, id: &str) -> Option<Arc<AtomicBool>> {
        self.jobs.flag(id)
    }
    fn cancelled(&self, id: &str) -> bool {
        self.jobs
            .flag(id)
            .is_some_and(|flag| flag.load(Ordering::Relaxed))
    }
    fn call(&self, command: &str, args: Value) -> service::Response<Value> {
        let run = || -> Result<Value> {
            match command {
                "editSystemEvent" => serde_json::from_str(
                    &self
                        .host
                        .calendar_event_call(command.into(), args.to_string())?,
                )
                .map_err(storage),
                "decodePhoto" => {
                    let bytes = STANDARD
                        .decode(args["base64"].as_str().unwrap_or(""))
                        .map_err(storage)?;
                    Ok(json!({"base64":STANDARD.encode(self.host.decode_photo(bytes)?)}))
                }
                "agenda" => serde_json::from_str(
                    &self
                        .host
                        .calendar_event_call("agenda".into(), args.to_string())?,
                )
                .map_err(storage),
                _ => Err(AppError::Validation {
                    message: format!("Unsupported native effect: {command}"),
                }),
            }
        };
        run().map_err(platform_failure)
    }
    // Legacy notifications have no attempt identity. Only the typed path may
    // update native progress; a delayed notification cannot revive a finished job.
    fn progress(&self, _: Value) {}
    fn update_progress(
        &self,
        attempt: &Arc<AtomicBool>,
        update: service::progress::ProgressUpdate,
    ) {
        if let Ok(mut progress) = self.progress.lock() {
            if let Some(entry) = progress.get_mut(&update.id) {
                if Arc::ptr_eq(&entry.attempt, attempt) && entry.value.state == JobState::Running {
                    entry.value.stage = update.stage;
                    entry.value.elapsed_ms = update.elapsed_ms;
                    entry.value.budget_ms = update.budget_ms;
                    entry.value.draft_available = update.draft_available;
                }
            }
        }
    }
}
