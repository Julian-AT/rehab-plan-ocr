use crate::{
    recognition_jobs::RecognitionJobs, records::*, runtime, AgendaOwnedRecord, AgendaSyncRequest,
    AgendaSyncResult, AppError, CalendarLinkInspection, CalendarPlatformStatus, CalendarReadEvent,
    CalendarReadQuery, CalendarReadReference, CalendarReadResult, EventCalendarDestination,
    EventMutationRequest, EventMutationResult, OwnedEventResolution, RecognitionJob,
    TextRecognitionRequest, TextRecognitionResult,
};
use base64::{engine::general_purpose::STANDARD, Engine};
use reha_core::{
    contracts as domain,
    service::{self, Application, Platform},
    store::Store,
};
use serde::{de::DeserializeOwned, Serialize};
use serde_json::{json, Value};
use std::{
    collections::HashMap,
    path::PathBuf,
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc, Mutex,
    },
};

type Result<T> = std::result::Result<T, AppError>;
fn read_photo_source(path: &std::path::Path) -> Result<Vec<u8>> {
    reha_core::photo_source::read(path).map_err(|error| match error {
        reha_core::Error::Invalid(message) => AppError::Validation { message },
        other => storage(other),
    })
}

fn convert<T: Serialize, U: DeserializeOwned>(value: T) -> Result<U> {
    serde_json::from_value(serde_json::to_value(value).map_err(storage)?).map_err(storage)
}
pub(crate) fn storage(e: impl std::fmt::Display) -> AppError {
    AppError::Storage {
        message: e.to_string(),
    }
}
pub(crate) fn failure(error: service::ServiceError) -> AppError {
    use service::ServiceError as E;
    let message = match error {
        E::Validation(message) => return AppError::Validation { message },
        E::Storage(message) => return AppError::Storage { message },
        E::PermissionDenied => return AppError::PermissionDenied,
        E::Timeout(operation) => return AppError::Timeout { operation },
        E::UncertainWrite => return AppError::UncertainWrite,
        E::ExpiredScan => return AppError::ExpiredScan,
        E::StaleRevision => return AppError::StaleRevision,
        E::StaleProposal => return AppError::StaleProposal,
        E::Busy => return AppError::Busy,
        E::Cancelled => return AppError::Cancelled,
        E::Legacy(message) => message,
    };
    if message == "Kalenderzugriff fehlt." {
        AppError::PermissionDenied
    } else if message == "stale_revision" {
        AppError::StaleRevision
    } else if message.contains("Vorschau abgelaufen")
        || message.contains("Prüfdaten wurden geändert")
    {
        AppError::StaleProposal
    } else if message.contains("gelöscht oder") {
        AppError::ExpiredScan
    } else if message.contains("läuft bereits") {
        AppError::Busy
    } else if message.contains("Unklare Schreibvorgänge") {
        AppError::UncertainWrite
    } else {
        AppError::Validation { message }
    }
}
fn platform_failure(error: AppError) -> service::ServiceError {
    use service::ServiceError as E;
    match error {
        AppError::Validation { message } => E::Validation(message),
        AppError::Storage { message } => E::Storage(message),
        AppError::PermissionDenied => E::PermissionDenied,
        AppError::Timeout { operation } => E::Timeout(operation),
        AppError::UncertainWrite => E::UncertainWrite,
        AppError::ExpiredScan => E::ExpiredScan,
        AppError::StaleRevision => E::StaleRevision,
        AppError::StaleProposal => E::StaleProposal,
        AppError::Busy => E::Busy,
        AppError::Cancelled => E::Cancelled,
    }
}
#[derive(Clone, uniffi::Record)]
pub struct Capabilities {
    pub recognition_available: bool,
    pub model_manifest_path: String,
    pub runtime: String,
    pub retention_days: Option<u32>,
}
#[derive(Clone, uniffi::Record)]
pub struct PlanCalendar {
    pub calendar_id: String,
    pub locked: bool,
}
#[derive(Clone, serde::Serialize, serde::Deserialize, uniffi::Record)]
#[serde(default)]
pub struct Preferences {
    pub timezone: String,
    pub reminder: Option<u32>,
    pub detailed_debug: bool,
    pub app_reminders_enabled: bool,
    pub app_reminder_minutes: Option<u32>,
    pub reminder_sound: bool,
    pub reminder_preview: bool,
    pub appearance: String,
    pub calendar_id: String,
    pub display_calendar_ids: Vec<String>,
    pub recent_calendar_ids: Vec<String>,
    pub completion_defaults: Vec<CompletionDefault>,
    pub retention_days: Option<u32>,
}
#[derive(Clone, uniffi::Record)]
pub struct PreferencesSaveResult {
    pub preferences: Preferences,
    pub maintenance_warnings: Vec<String>,
}
impl Default for Preferences {
    fn default() -> Self {
        Self {
            timezone: "Europe/Vienna".into(),
            reminder: Some(10),
            detailed_debug: false,
            app_reminders_enabled: false,
            app_reminder_minutes: Some(10),
            reminder_sound: true,
            reminder_preview: true,
            appearance: "system".into(),
            calendar_id: String::new(),
            display_calendar_ids: vec![],
            recent_calendar_ids: vec![],
            completion_defaults: vec![],
            retention_days: None,
        }
    }
}
#[derive(Clone, serde::Deserialize, uniffi::Record)]
pub struct ScanSummary {
    pub id: String,
    pub imported_at: i64,
    pub retained: bool,
    pub item_count: u64,
    pub pending_count: u64,
    pub dates: Vec<String>,
    pub schedule_id: Option<String>,
}
#[derive(Clone, uniffi::Record)]
pub struct PendingWrite {
    pub attempt_id: String,
    pub operation: CalendarOperation,
}
#[derive(Clone, uniffi::Record)]
pub struct History {
    pub scans: Vec<ScanSummary>,
    pub intakes: Vec<IntakeSummary>,
    pub batches: Vec<ImportBatch>,
    pub plans: Vec<Plan>,
    pub imports: Vec<ImportRecord>,
    pub pending: Vec<PendingWrite>,
    pub failures_json: String,
}
#[derive(Clone, serde::Deserialize, uniffi::Record)]
pub struct Plan {
    pub id: String,
    pub imported_at: i64,
    pub page_ids: Vec<String>,
}
#[derive(Clone, uniffi::Record)]
pub struct ArchiveCursor {
    pub imported_at: i64,
    pub id: String,
}
#[derive(Clone, uniffi::Enum)]
pub enum ArchiveStatus {
    ReconciliationNeeded,
    Undone,
    Saved,
    PartiallySaved,
    RecognitionPending,
    ReadyForReview,
}
#[derive(Clone, uniffi::Record)]
pub struct PlanSummary {
    pub id: String,
    pub imported_at: i64,
    pub page_ids: Vec<String>,
    pub item_count: u64,
    pub dates: Vec<String>,
    pub status: ArchiveStatus,
}
#[derive(Clone, uniffi::Record)]
pub struct ArchivePage {
    pub plans: Vec<PlanSummary>,
    pub next: Option<ArchiveCursor>,
}
#[derive(Clone, serde::Deserialize, uniffi::Record)]
pub struct ImportBatch {
    pub id: String,
    pub document_ids: Vec<String>,
    pub schedule_id: String,
    pub created_at: i64,
    pub undo_of: Option<String>,
    pub undone_by: Option<String>,
    pub operations: Vec<BatchOperation>,
}
#[derive(Clone, serde::Deserialize, uniffi::Record)]
pub struct BatchOperation {
    pub attempt_id: String,
    pub operation: CalendarOperation,
    pub status: String,
    pub result: Option<CalendarResult>,
}
#[derive(Clone, serde::Deserialize, uniffi::Record)]
pub struct IntakeSummary {
    pub id: String,
    pub filename: String,
    pub imported_at: i64,
    pub status: String,
    pub error: Option<String>,
}
#[derive(Clone, uniffi::Record)]
pub struct ReviewSnapshot {
    pub revision: String,
    pub document: Document,
    pub appointments: Vec<Appointment>,
    pub issues: Vec<Issue>,
    pub complete_page_confirmed: bool,
    pub timezone: String,
    pub page_width: u32,
    pub page_height: u32,
}
fn snapshot(run: domain::PipelineRun) -> Result<ReviewSnapshot> {
    Ok(ReviewSnapshot {
        revision: service::scan::revision(&run),
        document: convert(run.document)?,
        appointments: convert(run.appointments)?,
        issues: convert(run.issues)?,
        complete_page_confirmed: run.complete_page_confirmed,
        timezone: run.config.timezone,
        page_width: run.page_width,
        page_height: run.page_height,
    })
}
#[derive(Clone, uniffi::Record)]
pub struct Diagnostics {
    pub engine: String,
    pub manifest_json: String,
    pub stages: Vec<Stage>,
    pub source_hash: String,
    pub total_ms: u64,
}
#[derive(Clone, serde::Deserialize, uniffi::Record)]
pub struct Proposal {
    pub bindings: HashMap<String, String>,
    pub token: String,
    pub document_id: String,
    pub operations: Vec<CalendarOperation>,
    pub overlaps: Option<Vec<CalendarOverlap>>,
}
#[derive(Clone, serde::Serialize, serde::Deserialize, uniffi::Record)]
pub struct CalendarOverlap {
    pub appointment_id: String,
    pub external_id: String,
    pub title: String,
    pub start_utc: String,
    pub end_utc: String,
}
#[derive(Clone, uniffi::Record)]
pub struct LiveCalendar {
    pub current: HashMap<String, EventValues>,
    pub protected_ids: Vec<String>,
}
#[derive(Clone, uniffi::Record)]
pub struct PhotoRequest {
    pub id: String,
    pub path: String,
    pub timezone: String,
    pub quarter_turns: u8,
    pub mirrored: bool,
    pub page_corners: Vec<Point>,
    pub force: bool,
}
#[derive(Clone, uniffi::Record)]
pub struct ScanOutcome {
    pub scan: ReviewSnapshot,
    pub duplicate: bool,
}
#[derive(Clone, Copy, uniffi::Enum, PartialEq)]
pub enum JobState {
    Running,
    Completed,
    Cancelled,
    Failed,
}
#[derive(Clone, uniffi::Record)]
pub struct JobProgress {
    pub id: String,
    pub stage: String,
    pub elapsed_ms: u64,
    pub budget_ms: u64,
    pub draft_available: bool,
    pub state: JobState,
}
#[uniffi::export(callback_interface)]
pub trait AppleHost: Send + Sync {
    fn calendar_event_call(&self, command: String, arguments: String) -> Result<String>;
    fn calendar_status(&self) -> Result<CalendarPlatformStatus>;
    fn query_calendar(&self, request: CalendarReadQuery) -> Result<CalendarReadResult>;
    fn resolve_calendar_event(
        &self,
        reference: CalendarReadReference,
    ) -> Result<Option<CalendarReadEvent>>;
    fn event_calendars(&self) -> Result<Vec<EventCalendarDestination>>;
    fn mutate_event(&self, request: EventMutationRequest) -> Result<EventMutationResult>;
    fn snapshot(&self, records: Vec<ImportRecord>) -> Result<LiveCalendar>;
    fn apply(&self, operation: CalendarOperation, recovery_only: bool) -> Result<CalendarResult>;
    fn decode_photo(&self, bytes: Vec<u8>) -> Result<Vec<u8>>;
    fn recognize_text(&self, request: TextRecognitionRequest) -> Result<TextRecognitionResult>;
    fn sync_agenda(&self, request: AgendaSyncRequest) -> Result<AgendaSyncResult>;
    fn inspect_calendar_links(
        &self,
        records: Vec<AgendaOwnedRecord>,
    ) -> Result<CalendarLinkInspection>;
    fn resolve_owned_event(&self, record: AgendaOwnedRecord) -> Result<OwnedEventResolution>;
    fn forget_calendar(&self) -> Result<()>;
    fn overlaps(
        &self,
        events: HashMap<String, EventValues>,
        exclude: Vec<String>,
    ) -> Result<Vec<CalendarOverlap>>;
}
pub(crate) struct HostBridge {
    host: Box<dyn AppleHost>,
    progress: Mutex<HashMap<String, JobProgress>>,
    jobs: Arc<RecognitionJobs>,
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
                "forgetCalendar" => {
                    self.host.forget_calendar()?;
                    Ok(Value::Null)
                }
                _ => Err(AppError::Validation {
                    message: format!("Unsupported native effect: {command}"),
                }),
            }
        };
        run().map_err(platform_failure)
    }
    fn progress(&self, value: Value) {
        if let Some(id) = value["id"].as_str() {
            if let Ok(mut map) = self.progress.lock() {
                map.insert(
                    id.into(),
                    JobProgress {
                        id: id.into(),
                        stage: value["stage"].as_str().unwrap_or("").into(),
                        elapsed_ms: value["elapsed_ms"].as_u64().unwrap_or(0),
                        budget_ms: 60000,
                        draft_available: value["draft_available"].as_bool().unwrap_or(false),
                        state: JobState::Running,
                    },
                );
            }
        }
    }
}
#[derive(uniffi::Object)]
pub struct NativeApplication {
    pub(crate) state: Arc<Application>,
    pub(crate) bridge: Arc<HostBridge>,
}
impl NativeApplication {
    async fn blocking<T: Send + 'static>(
        &self,
        work: impl FnOnce(Arc<Application>) -> Result<T> + Send + 'static,
    ) -> Result<T> {
        let state = self.state.clone();
        runtime()
            .spawn_blocking(move || work(state))
            .await
            .map_err(storage)?
    }
}
#[uniffi::export]
pub async fn open_application(
    root: String,
    models: String,
    host: Box<dyn AppleHost>,
) -> Result<Arc<NativeApplication>> {
    runtime()
        .spawn_blocking(move || {
            let store = Store::open(&PathBuf::from(root)).map_err(storage)?;
            // A failed retry leaves the local journal intact and is surfaced by
            // calendarStatus. Opening the app must still allow viewing/export.
            let _ = reha_core::store::bookkeeping::recover(&store);
            store
                .cleanup(chrono::Utc::now().timestamp())
                .map_err(storage)?;
            Ok(Arc::new(NativeApplication {
                state: Arc::new(Application::new(store, PathBuf::from(models))),
                bridge: Arc::new(HostBridge {
                    host,
                    progress: Mutex::new(HashMap::new()),
                    jobs: Arc::new(RecognitionJobs::default()),
                }),
            }))
        })
        .await
        .map_err(storage)?
}
#[uniffi::export]
impl NativeApplication {
    pub async fn capabilities(&self) -> Result<Capabilities> {
        self.blocking(|s| {
            Ok(Capabilities {
                recognition_available: cfg!(feature = "onnx")
                    && s.models.join("manifest.json").exists(),
                model_manifest_path: s.models.join("manifest.json").to_string_lossy().into(),
                runtime: "ONNX Runtime 1.22.0 / ort 2.0.0-rc.10".into(),
                retention_days: None,
            })
        })
        .await
    }
    pub async fn history(&self) -> Result<History> {
        self.blocking(|s| {
            let store = s.store.lock().map_err(storage)?;
            Ok(History {
                scans: convert(store.list_scans().map_err(storage)?)?,
                intakes: convert(store.intakes().map_err(storage)?)?,
                batches: convert(store.batches().map_err(storage)?)?,
                plans: convert(store.plans().map_err(storage)?)?,
                imports: convert(store.records(None).map_err(storage)?)?,
                pending: store
                    .pending()
                    .map_err(storage)?
                    .into_iter()
                    .map(|(attempt_id, operation)| {
                        Ok(PendingWrite {
                            attempt_id,
                            operation: convert(operation)?,
                        })
                    })
                    .collect::<Result<_>>()?,
                failures_json: serde_json::to_string(&store.failures().map_err(storage)?)
                    .map_err(storage)?,
            })
        })
        .await
    }
    pub async fn archive_page(
        &self,
        after: Option<ArchiveCursor>,
        limit: u32,
    ) -> Result<ArchivePage> {
        self.blocking(move |s| {
            let after = after.map(|c| reha_core::store::ArchiveCursor {
                imported_at: c.imported_at,
                id: c.id,
            });
            let page = s
                .store
                .lock()
                .map_err(storage)?
                .archive_page(after.as_ref(), limit)
                .map_err(storage)?;
            Ok(ArchivePage {
                next: page.next.map(|c| ArchiveCursor {
                    imported_at: c.imported_at,
                    id: c.id,
                }),
                plans: page
                    .plans
                    .into_iter()
                    .map(|p| PlanSummary {
                        id: p.id,
                        imported_at: p.imported_at,
                        page_ids: p.page_ids,
                        item_count: p.item_count,
                        dates: p.dates,
                        status: match p.status {
                            reha_core::store::ArchiveStatus::ReconciliationNeeded => {
                                ArchiveStatus::ReconciliationNeeded
                            }
                            reha_core::store::ArchiveStatus::Undone => ArchiveStatus::Undone,
                            reha_core::store::ArchiveStatus::Saved => ArchiveStatus::Saved,
                            reha_core::store::ArchiveStatus::PartiallySaved => {
                                ArchiveStatus::PartiallySaved
                            }
                            reha_core::store::ArchiveStatus::RecognitionPending => {
                                ArchiveStatus::RecognitionPending
                            }
                            reha_core::store::ArchiveStatus::ReadyForReview => {
                                ArchiveStatus::ReadyForReview
                            }
                        },
                    })
                    .collect(),
            })
        })
        .await
    }
    pub async fn load_scan(&self, id: String) -> Result<ReviewSnapshot> {
        self.blocking(move |s| snapshot(service::scan::load_scan(&s, id).map_err(failure)?))
            .await
    }
    pub async fn page_group(&self, id: String) -> Result<Vec<String>> {
        self.blocking(move |s| service::calendar::page_group(&s, id).map_err(failure))
            .await
    }
    pub async fn associate_recheck(&self, id: String, previous: String) -> Result<()> {
        self.blocking(move |s| service::scan::associate_recheck(&s, id, previous).map_err(failure))
            .await
    }
    pub async fn set_page_group(&self, id: String, page_ids: Vec<String>) -> Result<u32> {
        self.blocking(move |s| {
            service::calendar::set_page_group(&s, id, page_ids)
                .map(|n| n as u32)
                .map_err(failure)
        })
        .await
    }
    pub async fn append_pages(&self, id: String, pages: Vec<String>) -> Result<u32> {
        if id.is_empty() {
            return Err(AppError::Validation {
                message: "id fehlt.".into(),
            });
        }
        self.blocking(move |s| {
            // The shared service retains admission, sibling order, source
            // lifetime checks and proposal invalidation. Groups are limited to 12.
            service::calendar::append_pages(&s, id, pages)
                .map(|count| count as u32)
                .map_err(failure)
        })
        .await
    }
    pub async fn pdf_pages(&self, id: String, count: u32) -> Result<Vec<String>> {
        self.blocking(move |s| {
            s.store
                .lock()
                .map_err(storage)?
                .pdf_pages(&id, count as usize)
                .map_err(storage)
        })
        .await
    }
    pub async fn retain_pdf_evidence(&self, page_id: String, evidence_json: String) -> Result<()> {
        self.blocking(move |s| {
            if evidence_json.len() > 5 * 1024 * 1024 {
                return Err(AppError::Validation {
                    message: "PDF-Textebene zu groß.".into(),
                });
            }
            let value: Value = serde_json::from_str(&evidence_json).map_err(storage)?;
            let store = s.store.lock().map_err(storage)?;
            store.scan_dir(&page_id).map_err(storage)?;
            store
                .set_setting(&format!("pdf-evidence:{page_id}"), &value.to_string())
                .map_err(storage)
        })
        .await
    }
    pub fn recognition_busy(&self) -> bool {
        self.bridge.jobs.running()
            || self
                .state
                .cancel
                .lock()
                .map(|jobs| !jobs.is_empty())
                .unwrap_or(true)
    }
    pub async fn retry_capture(
        &self,
        id: String,
        job: Arc<RecognitionJob>,
    ) -> Result<ReviewSnapshot> {
        let state = self.state.clone();
        let bridge = self.bridge.clone();
        self.recognition_job(job.clone(), id.clone(), async move {
            if !state.cancel.lock().map_err(storage)?.is_empty() {
                return Err(AppError::Busy);
            }
            let staged = {
                let store = state.store.lock().map_err(storage)?;
                if store.load_run(&id).is_ok() {
                    None
                } else {
                    let intake = store
                        .intake(&id)
                        .map_err(storage)?
                        .filter(|i| i.status != "deleted")
                        .ok_or(AppError::ExpiredScan)?;
                    Some((
                        intake,
                        read_photo_source(&store.source_path(&id).map_err(storage)?)?,
                    ))
                }
            };
            if job.is_cancelled() {
                return Err(AppError::Cancelled);
            }
            if let Some((intake, bytes)) = staged {
                let value = service::scan::import_image(
                    bridge,
                    &state,
                    service::inference::ImportRequest {
                        id,
                        filename: intake.filename,
                        base64: STANDARD.encode(bytes),
                        config: intake.config,
                        force: true,
                    },
                )
                .await
                .map_err(failure)?;
                snapshot(serde_json::from_value(value["run"].clone()).map_err(storage)?)
            } else {
                snapshot(
                    service::scan::retry_scan(bridge, &state, id)
                        .await
                        .map_err(failure)?,
                )
            }
        })
        .await
    }
    pub async fn diagnostics(&self, id: String) -> Result<Diagnostics> {
        self.blocking(move |s| {
            let run = service::scan::load_scan(&s, id).map_err(failure)?;
            Ok(Diagnostics {
                engine: run.engine,
                manifest_json: run.model_manifest.to_string(),
                stages: convert(run.stages)?,
                source_hash: run.document.source_hash,
                total_ms: run.total_ms,
            })
        })
        .await
    }
    /// Full, local recognition evidence for the explicitly opened tracing workspace.
    pub async fn recognition_trace(&self, id: String) -> Result<String> {
        self.blocking(move |s| {
            let run = service::scan::load_scan(&s, id).map_err(failure)?;
            serde_json::to_string(&run).map_err(storage)
        })
        .await
    }
    pub async fn trace_artifact_path(&self, id: String, artifact: String) -> Result<String> {
        self.blocking(move |s| {
            let store = s.store.lock().map_err(storage)?;
            let run = store.load_run(&id).map_err(storage)?;
            if !allowed_trace_artifact(&run, &artifact) {
                return Err(AppError::Validation {
                    message: "Unbekannter Tracing-Ausschnitt.".into(),
                });
            }
            let path = store.scan_dir(&id).map_err(storage)?.join(artifact);
            if !path.is_file() {
                return Err(AppError::ExpiredScan);
            }
            Ok(path.to_string_lossy().into())
        })
        .await
    }
    pub async fn artifact_path(&self, id: String, artifact: String) -> Result<String> {
        self.blocking(move |s| {
            if !["source.bin", "original.png", "page.png"].contains(&artifact.as_str()) {
                return Err(AppError::Validation {
                    message: "Unbekanntes Bildartefakt.".into(),
                });
            }
            let store = s.store.lock().map_err(storage)?;
            let path = if artifact == "source.bin" {
                store.source_path(&id).map_err(storage)?
            } else {
                store.scan_dir(&id).map_err(storage)?.join(artifact)
            };
            if !path.is_file() {
                return Err(AppError::ExpiredScan);
            }
            Ok(path.to_string_lossy().into())
        })
        .await
    }
    pub async fn preferences(&self) -> Result<Preferences> {
        self.blocking(|s| convert(service::settings::settings_value(&s, None).map_err(failure)?))
            .await
    }
    /// Versioned JSON transport for the shared calendar application contract.
    /// The same Application and SQLite connection serve photo and voice actions.
    pub async fn calendar_request(&self, command: String, arguments: String) -> Result<String> {
        let args: Value = serde_json::from_str(&arguments).map_err(storage)?;
        let state = self.state.clone();
        let bridge = self.bridge.clone();
        runtime()
            .spawn(async move {
                service::events::dispatch(bridge, &state, &command, args)
                    .await
                    .map(|v| v.to_string())
                    .map_err(failure)
            })
            .await
            .map_err(storage)?
    }
    pub async fn plan_calendar(&self, id: String) -> Result<PlanCalendar> {
        self.blocking(move |s| {
            let (calendar_id, locked) = s
                .store
                .lock()
                .map_err(storage)?
                .plan_calendar(&id)
                .map_err(storage)?;
            Ok(PlanCalendar {
                calendar_id,
                locked,
            })
        })
        .await
    }
    pub async fn select_plan_calendar(&self, id: String, calendar_id: String) -> Result<()> {
        self.blocking(move |s| {
            let _guard = s.calendar_lock.try_lock().map_err(|_| AppError::Busy)?;
            s.store
                .lock()
                .map_err(storage)?
                .select_plan_calendar(&id, &calendar_id)
                .map_err(storage)?;
            s.proposals.lock().map_err(storage)?.clear();
            Ok(())
        })
        .await
    }
    pub async fn save_preferences(&self, value: Preferences) -> Result<Preferences> {
        Ok(self.save_preferences_detailed(value).await?.preferences)
    }
    pub async fn save_preferences_detailed(
        &self,
        value: Preferences,
    ) -> Result<PreferencesSaveResult> {
        let bridge = self.bridge.clone();
        self.blocking(move |s| {
            let _guard = s.calendar_lock.try_lock().map_err(|_| AppError::Busy)?;
            let mut existing = service::settings::settings_value(&s, None).map_err(failure)?;
            existing
                .as_object_mut()
                .ok_or_else(|| storage("Invalid preferences"))?
                .extend(
                    serde_json::to_value(&value)
                        .map_err(storage)?
                        .as_object()
                        .unwrap()
                        .clone(),
                );
            let persisted =
                service::settings::settings_value(&s, Some(existing)).map_err(failure)?;
            let preferences = convert(persisted)?;
            // Preferences are durable. Neither cache preparation nor an OS
            // reminder/widget failure may report the user's save as rejected.
            let maintenance = service::agenda::sync_request(&s)
                .and_then(|request| bridge.synchronize_agenda(request));
            let maintenance_warnings = match maintenance {
                Ok(response) => response.maintenance_warnings,
                Err(error) => vec![error.to_string()],
            };
            Ok(PreferencesSaveResult {
                preferences,
                maintenance_warnings,
            })
        })
        .await
    }
    pub async fn save_review(
        &self,
        id: String,
        revision: String,
        appointments: Vec<Appointment>,
        complete: bool,
        selection: Vec<String>,
    ) -> Result<ReviewSnapshot> {
        self.blocking(move |s| {
            snapshot(
                service::scan::save_review(
                    &s,
                    id,
                    convert(appointments)?,
                    complete,
                    false,
                    Some(selection),
                    Some(revision),
                )
                .map_err(failure)?,
            )
        })
        .await
    }
    pub async fn export_ics(
        &self,
        id: String,
        timezone: String,
        reminder: Option<u32>,
        selection: Vec<String>,
    ) -> Result<String> {
        self.blocking(move |s| {
            service::calendar::export_ics(&s, id, timezone, reminder, Some(selection))
                .map_err(failure)
        })
        .await
    }
    pub async fn delete_scan(&self, id: String) -> Result<()> {
        self.blocking(move |s| {
            if !s.cancel.lock().map_err(storage)?.is_empty() {
                return Err(AppError::Busy);
            }
            service::scan::delete_scan(&s, id).map_err(failure)
        })
        .await
    }
    pub async fn erase_all(&self) -> Result<()> {
        let state = self.state.clone();
        let bridge = self.bridge.clone();
        runtime()
            .spawn(async move {
                service::settings::erase_all(bridge, &state)
                    .await
                    .map_err(failure)
            })
            .await
            .map_err(storage)?
    }
    pub async fn assess_draft(&self, id: String, timezone: String) -> Result<DraftAssessment> {
        self.blocking(move |s| convert(service::draft::assess(&s, id, timezone).map_err(failure)?))
            .await
    }
    pub async fn preview_draft(
        &self,
        id: String,
        calendar_id: String,
        timezone: String,
        reminder: Option<u32>,
    ) -> Result<DraftPreview> {
        let state = self.state.clone();
        let bridge = self.bridge.clone();
        runtime()
            .spawn(async move {
                convert(
                    service::draft::preview(bridge, &state, id, calendar_id, timezone, reminder)
                        .await
                        .map_err(failure)?,
                )
            })
            .await
            .map_err(storage)?
    }
    pub async fn preview_replacement(
        &self,
        id: String,
        calendar_id: String,
        timezone: String,
        reminder: Option<u32>,
    ) -> Result<DraftPreview> {
        let state = self.state.clone();
        let bridge = self.bridge.clone();
        runtime()
            .spawn(async move {
                convert(
                    service::draft::preview_replacement(
                        bridge,
                        &state,
                        id,
                        calendar_id,
                        timezone,
                        reminder,
                    )
                    .await
                    .map_err(failure)?,
                )
            })
            .await
            .map_err(storage)?
    }
    pub async fn export_draft_ics(
        &self,
        id: String,
        revision: String,
        timezone: String,
        reminder: Option<u32>,
        selection: Vec<String>,
    ) -> Result<String> {
        self.blocking(move |s| {
            service::draft::export_ics(&s, id, revision, timezone, reminder, selection)
                .map_err(failure)
        })
        .await
    }
    pub async fn answer_draft_question(
        &self,
        id: String,
        revision: String,
        question_id: String,
        value: Option<FieldValue>,
        timezone: String,
    ) -> Result<()> {
        self.blocking(move |s| {
            service::draft::answer(
                &s,
                id,
                revision,
                question_id,
                value
                    .map(serde_json::to_value)
                    .transpose()
                    .map_err(storage)?,
                timezone,
            )
            .map_err(failure)
        })
        .await
    }
    /// Acceptance and write intent survive a dropped Swift future.
    pub async fn accept_and_save(
        &self,
        token: String,
        selection: Vec<String>,
        approve_removals: bool,
    ) -> Result<SaveOutcome> {
        let state = self.state.clone();
        let bridge = self.bridge.clone();
        runtime()
            .spawn(async move {
                convert(
                    service::draft::accept_and_save(
                        bridge,
                        &state,
                        token,
                        selection,
                        approve_removals,
                    )
                    .await
                    .map_err(failure)?,
                )
            })
            .await
            .map_err(storage)?
    }
    pub async fn prepare_calendar(
        &self,
        id: String,
        calendar_id: String,
        timezone: String,
        reminder: Option<u32>,
        selection: Vec<String>,
        replacement: bool,
    ) -> Result<Proposal> {
        let state = self.state.clone();
        let bridge = self.bridge.clone();
        runtime()
            .spawn(async move {
                convert(
                    service::calendar::prepare_calendar(
                        bridge,
                        &state,
                        id,
                        calendar_id,
                        None,
                        timezone,
                        reminder,
                        Some(selection),
                        Some(replacement),
                    )
                    .await
                    .map_err(failure)?,
                )
            })
            .await
            .map_err(storage)?
    }
    pub async fn resolve_proposal(
        &self,
        token: String,
        event_id: String,
        choice: String,
    ) -> Result<Proposal> {
        self.blocking(move |s| {
            convert(
                service::calendar::resolve_proposal(&s, token, event_id, choice)
                    .map_err(failure)?,
            )
        })
        .await
    }
    pub async fn prepare_undo(&self, batch_id: String) -> Result<Proposal> {
        let state = self.state.clone();
        let bridge = self.bridge.clone();
        runtime()
            .spawn(async move {
                convert(
                    service::undo::prepare(bridge, &state, batch_id)
                        .await
                        .map_err(failure)?,
                )
            })
            .await
            .map_err(storage)?
    }
    /// Owned runtime task continues journal bookkeeping if Swift drops this future.
    pub async fn approve_calendar(
        &self,
        token: String,
        approve_removals: bool,
    ) -> Result<Vec<CalendarResult>> {
        let state = self.state.clone();
        let bridge = self.bridge.clone();
        runtime()
            .spawn(async move {
                convert(
                    service::calendar::approve_calendar(bridge, &state, token, approve_removals)
                        .await
                        .map_err(failure)?,
                )
            })
            .await
            .map_err(storage)?
    }
    pub async fn reconcile_calendar(&self) -> Result<Vec<CalendarResult>> {
        let state = self.state.clone();
        let bridge = self.bridge.clone();
        runtime()
            .spawn(async move {
                convert(
                    service::calendar::reconcile_calendar(bridge, &state)
                        .await
                        .map_err(failure)?,
                )
            })
            .await
            .map_err(storage)?
    }
    pub async fn resolve_pending(&self, attempt_id: String, removal_applied: bool) -> Result<()> {
        let state = self.state.clone();
        runtime()
            .spawn(async move {
                service::calendar::resolve_pending_write(
                    &state,
                    attempt_id,
                    if removal_applied {
                        "removal_applied"
                    } else {
                        "not_applied"
                    }
                    .into(),
                )
                .await
                .map_err(failure)
            })
            .await
            .map_err(storage)?
    }
    /// Register before installing a cancellation handler or publishing the job.
    pub fn register_job(&self, id: String) -> Result<Arc<RecognitionJob>> {
        self.bridge.jobs.register(id)
    }
    /// The ID is an opaque attempt ID from RecognitionJob, never a scan ID.
    /// Unknown and completed attempts are harmless and allocate no state.
    pub fn cancel_job(&self, id: String) -> Result<()> {
        self.bridge.jobs.cancel(&id)
    }
    pub fn job_progress(&self, id: String) -> Option<JobProgress> {
        self.bridge.progress.lock().ok()?.get(&id).cloned()
    }
    /// Independent of decoding/model availability. Safe to acknowledge only after this returns.
    pub async fn stage_photo(&self, id: String, path: String) -> Result<IntakeSummary> {
        self.blocking(move |s| {
            let path = PathBuf::from(path);
            let bytes = read_photo_source(&path)?;
            let store = s.store.lock().map_err(storage)?;
            convert(
                store
                    .stage_intake(
                        &id,
                        &path.file_name().unwrap_or_default().to_string_lossy(),
                        &bytes,
                        &domain::PipelineConfig::default(),
                        chrono::Utc::now().timestamp(),
                    )
                    .map_err(storage)?,
            )
        })
        .await
    }
    pub async fn import_photo(
        &self,
        request: PhotoRequest,
        job: Arc<RecognitionJob>,
    ) -> Result<ScanOutcome> {
        self.import_photo_with_debug(request, job, false).await
    }
    /// Same pipeline as a regular import, with retained detector crops for tracing.
    pub async fn import_trace_photo(
        &self,
        request: PhotoRequest,
        job: Arc<RecognitionJob>,
    ) -> Result<ScanOutcome> {
        self.import_photo_with_debug(request, job, true).await
    }
}
impl NativeApplication {
    /// The inner worker owns cleanup even when UniFFI drops the caller's future.
    /// Its flag is also the Core worker's flag, so late cancellation cannot leak
    /// into a later attempt for the same retained scan.
    async fn recognition_job<T: Send + 'static>(
        &self,
        job: Arc<RecognitionJob>,
        id: String,
        work: impl std::future::Future<Output = Result<T>> + Send + 'static,
    ) -> Result<T> {
        let lease = job.start(&self.bridge.jobs, &id)?;
        struct CancelOnDrop {
            job: Arc<RecognitionJob>,
            armed: bool,
        }
        impl Drop for CancelOnDrop {
            fn drop(&mut self) {
                if self.armed {
                    self.job.cancel();
                }
            }
        }
        struct ProgressFinish {
            bridge: Arc<HostBridge>,
            id: String,
            job: Arc<RecognitionJob>,
            state: JobState,
        }
        impl Drop for ProgressFinish {
            fn drop(&mut self) {
                if let Ok(mut progress) = self.bridge.progress.lock() {
                    if let Some(p) = progress.get_mut(&self.id) {
                        p.state = if self.job.is_cancelled() {
                            JobState::Cancelled
                        } else {
                            self.state
                        };
                    }
                }
            }
        }
        let mut guard = CancelOnDrop {
            job: job.clone(),
            armed: true,
        };
        let bridge = self.bridge.clone();
        let result = runtime()
            .spawn(async move {
                let _lease = lease;
                if let Ok(mut progress) = bridge.progress.lock() {
                    progress.retain(|_, p| p.state == JobState::Running);
                }
                bridge.progress(json!({"id":id,"stage":"Foto vorbereiten"}));
                let mut progress = ProgressFinish {
                    bridge,
                    id,
                    job: job.clone(),
                    state: JobState::Failed,
                };
                let result = if job.is_cancelled() {
                    Err(AppError::Cancelled)
                } else {
                    work.await
                };
                if result.is_ok() {
                    progress.state = JobState::Completed;
                }
                result
            })
            .await
            .map_err(storage);
        guard.armed = false;
        result?
    }
    async fn import_photo_with_debug(
        &self,
        request: PhotoRequest,
        job: Arc<RecognitionJob>,
        detailed_debug: bool,
    ) -> Result<ScanOutcome> {
        let state = self.state.clone();
        let bridge = self.bridge.clone();
        let id = request.id.clone();
        self.recognition_job(job.clone(), id.clone(), async move {
            let path = PathBuf::from(&request.path);
            let bytes = tokio::task::spawn_blocking(move || read_photo_source(&path))
                .await
                .map_err(storage)??;
            let corners = if request.page_corners.is_empty() {
                None
            } else {
                let points: Vec<domain::Point> = convert(request.page_corners)?;
                Some(points.try_into().map_err(|_| AppError::Validation {
                    message: "Vier Seitenecken erforderlich.".into(),
                })?)
            };
            let config = domain::PipelineConfig {
                detailed_debug,
                timezone: request.timezone,
                quarter_turns: request.quarter_turns,
                mirrored: request.mirrored,
                page_corners: corners,
                ..Default::default()
            };
            let request = service::inference::ImportRequest {
                id: id.clone(),
                filename: PathBuf::from(&request.path)
                    .file_name()
                    .unwrap_or_default()
                    .to_string_lossy()
                    .into(),
                base64: STANDARD.encode(bytes),
                config,
                force: request.force,
            };
            if job.is_cancelled() {
                return Err(AppError::Cancelled);
            }
            let value = service::scan::import_image(bridge, &state, request)
                .await
                .map_err(failure)?;
            Ok(ScanOutcome {
                duplicate: value["duplicate"].as_bool().unwrap_or(false),
                scan: snapshot(serde_json::from_value(value["run"].clone()).map_err(storage)?)?,
            })
        })
        .await
    }
}

#[uniffi::export]
pub fn new_appointment(date: Option<String>) -> Result<Appointment> {
    let mut appointment = domain::Appointment::empty(uuid::Uuid::new_v4().to_string());
    appointment.date = date;
    convert(appointment)
}
#[uniffi::export]
pub fn confirm_appointment_fields(appointment: Appointment) -> Result<Appointment> {
    let mut a: domain::Appointment = convert(appointment)?;
    for field in reha_core::review::FIELDS {
        let value = reha_core::review::value(&a, field);
        let empty = value.is_null() || value.as_str().is_some_and(|s| s.is_empty());
        let assessment = a.fields.entry((*field).into()).or_default();
        assessment.state = if empty {
            domain::PrintedState::NotPrinted
        } else {
            domain::PrintedState::Legible
        };
        assessment.confirmed_value = Some(value);
        assessment.confirmed_at = Some(chrono::Utc::now().timestamp());
    }
    convert(a)
}
#[uniffi::export]
pub fn accept_suggestion(
    appointment: Appointment,
    suggestion_id: String,
    accept: bool,
) -> Result<Appointment> {
    let mut a: domain::Appointment = convert(appointment)?;
    let suggestion = a
        .suggestions
        .iter_mut()
        .find(|s| s.id == suggestion_id)
        .ok_or_else(|| failure("Vorschlag fehlt.".into()))?;
    suggestion.status = if accept { "accepted" } else { "rejected" }.into();
    let (field, value) = (suggestion.field.clone(), suggestion.value.clone());
    if accept {
        reha_core::review::set_value(&mut a, &field, value)
            .map_err(|e| failure(e.to_string().into()))?;
    }
    convert(a)
}
#[uniffi::export]
pub fn appointment_issues(appointment: Appointment, timezone: String) -> Result<Vec<Issue>> {
    let a: domain::Appointment = convert(appointment)?;
    let assessment = reha_core::readiness::appointment(&a, "", &timezone);
    convert(
        assessment
            .issues
            .into_iter()
            .chain(assessment.warnings)
            .collect::<Vec<_>>(),
    )
}

#[cfg(test)]
mod host_routing_tests {
    use super::*;
    use crate::{CalendarLinkResult, CalendarLinkState};
    type HostCalls = Arc<Mutex<Vec<(String, Value)>>>;
    #[derive(Default)]
    pub(super) struct Host {
        failure: Option<service::ServiceError>,
        calls: Option<HostCalls>,
        response: Option<Value>,
        recognition: Option<TextRecognitionResult>,
        overlap_response: Vec<CalendarOverlap>,
    }
    impl AppleHost for Host {
        fn recognize_text(&self, request: TextRecognitionRequest) -> Result<TextRecognitionResult> {
            if let Some(calls) = &self.calls {
                calls.lock().unwrap().push((
                    "typedRecognition".into(),
                    json!({
                        "image":request.image,"budget_ms":request.budget_ms
                    }),
                ));
            }
            if let Some(error) = &self.failure {
                return Err(failure(error.clone()));
            }
            Ok(self
                .recognition
                .clone()
                .expect("Recognition fixture missing"))
        }
        fn calendar_status(&self) -> Result<CalendarPlatformStatus> {
            if let Some(error) = &self.failure {
                return Err(failure(error.clone()));
            }
            Ok(CalendarPlatformStatus {
                access: crate::CalendarAccessStatus::FullAccess,
                last_read_at: None,
                calendars: vec![],
                unavailable_calendar_ids: vec![],
            })
        }

        fn query_calendar(&self, _: CalendarReadQuery) -> Result<CalendarReadResult> {
            if let Some(error) = &self.failure {
                return Err(failure(error.clone()));
            }
            Ok(CalendarReadResult {
                events: vec![],
                unavailable_calendar_ids: vec![],
                unavailable_events: vec![],
            })
        }
        fn resolve_calendar_event(
            &self,
            _: CalendarReadReference,
        ) -> Result<Option<CalendarReadEvent>> {
            if let Some(error) = &self.failure {
                return Err(failure(error.clone()));
            }
            Ok(None)
        }
        fn event_calendars(&self) -> Result<Vec<EventCalendarDestination>> {
            if let Some(error) = &self.failure {
                return Err(failure(error.clone()));
            }
            Ok(vec![])
        }
        fn mutate_event(&self, _: EventMutationRequest) -> Result<EventMutationResult> {
            if let Some(error) = &self.failure {
                return Err(failure(error.clone()));
            }
            Ok(service::calendar_mutations::MutationResult::uncertain().into())
        }
        fn calendar_event_call(&self, command: String, arguments: String) -> Result<String> {
            if let Some(calls) = &self.calls {
                calls
                    .lock()
                    .unwrap()
                    .push((command.clone(), serde_json::from_str(&arguments).unwrap()));
            }
            if let Some(error) = &self.failure {
                return Err(failure(error.clone()));
            }
            Ok(self.response.clone().unwrap_or_else(|| json!({"received_command": command, "arguments": serde_json::from_str::<Value>(&arguments).unwrap()})).to_string())
        }
        fn resolve_owned_event(&self, record: AgendaOwnedRecord) -> Result<OwnedEventResolution> {
            if let Some(error) = &self.failure {
                return Err(failure(error.clone()));
            }
            if let Some(calls) = &self.calls {
                calls
                    .lock()
                    .unwrap()
                    .push(("typedOwnedEvent".into(), json!(record)));
            }
            Ok(OwnedEventResolution::Unavailable)
        }
        fn inspect_calendar_links(
            &self,
            records: Vec<AgendaOwnedRecord>,
        ) -> Result<CalendarLinkInspection> {
            if let Some(error) = &self.failure {
                return Err(failure(error.clone()));
            }
            if let Some(calls) = &self.calls {
                calls
                    .lock()
                    .unwrap()
                    .push(("typedCalendarLinks".into(), json!(records)));
            }
            Ok(CalendarLinkInspection {
                calendar_ids: vec!["visible".into()],
                results: records
                    .into_iter()
                    .map(|r| CalendarLinkResult {
                        id: r.id,
                        state: CalendarLinkState::Unavailable { reason: None },
                    })
                    .collect(),
            })
        }
        fn snapshot(&self, records: Vec<ImportRecord>) -> Result<LiveCalendar> {
            if let Some(error) = &self.failure {
                return Err(failure(error.clone()));
            }
            if let Some(calls) = &self.calls {
                calls
                    .lock()
                    .unwrap()
                    .push(("typedSnapshot".into(), json!(records)));
            }
            Ok(LiveCalendar {
                current: records.into_iter().map(|r| (r.id, r.approved)).collect(),
                protected_ids: vec!["protected-series".into()],
            })
        }
        fn apply(
            &self,
            operation: CalendarOperation,
            recovery_only: bool,
        ) -> Result<CalendarResult> {
            if let Some(error) = &self.failure {
                return Err(failure(error.clone()));
            }
            if let Some(calls) = &self.calls {
                calls.lock().unwrap().push((
                    "typedApply".into(),
                    json!({"operation":operation,"recovery_only":recovery_only}),
                ));
            }
            Ok(CalendarResult {
                id: operation.id,
                status: if recovery_only {
                    WriteStatus::Uncertain
                } else {
                    WriteStatus::Saved
                },
                external_id: operation.external_id,
                error: recovery_only.then(|| "Unclear durable status".into()),
                maintenance_warnings: vec!["Separate maintenance warning".into()],
            })
        }
        fn decode_photo(&self, bytes: Vec<u8>) -> Result<Vec<u8>> {
            Ok(bytes.into_iter().rev().collect())
        }
        fn sync_agenda(&self, request: AgendaSyncRequest) -> Result<AgendaSyncResult> {
            if let Some(calls) = &self.calls {
                calls
                    .lock()
                    .unwrap()
                    .push(("typedAgenda".into(), json!(request)));
            }
            if let Some(error) = &self.failure {
                return Err(failure(error.clone()));
            }
            Ok(AgendaSyncResult {
                maintenance_warnings: service::agenda::maintenance_warnings(
                    self.response.as_ref().unwrap_or(&Value::Null),
                ),
            })
        }
        fn forget_calendar(&self) -> Result<()> {
            unreachable!()
        }
        fn overlaps(
            &self,
            events: HashMap<String, EventValues>,
            exclude: Vec<String>,
        ) -> Result<Vec<CalendarOverlap>> {
            if let Some(calls) = &self.calls {
                calls.lock().unwrap().push((
                    "typedOverlaps".into(),
                    json!({"events":events,"exclude":exclude}),
                ));
            }
            if let Some(error) = &self.failure {
                return Err(failure(error.clone()));
            }
            Ok(self.overlap_response.clone())
        }
    }
    #[test]
    fn typed_overlap_effect_preserves_values_exclusions_and_response_order() {
        let calls = Arc::new(Mutex::new(vec![]));
        let bridge = HostBridge {
            host: Box::new(Host {
                calls: Some(calls.clone()),
                overlap_response: vec![
                    CalendarOverlap {
                        appointment_id: "later".into(),
                        external_id: "native-later".into(),
                        title: "Spätere Überschneidung".into(),
                        start_utc: "2031-05-17T09:00:00Z".into(),
                        end_utc: "2031-05-17T09:30:00Z".into(),
                    },
                    CalendarOverlap {
                        appointment_id: "earlier".into(),
                        external_id: "native-earlier".into(),
                        title: "Frühere Überschneidung".into(),
                        start_utc: "2031-05-17T08:00:00Z".into(),
                        end_utc: "2031-05-17T08:30:00Z".into(),
                    },
                ],
                ..Host::default()
            }),
            progress: Mutex::new(HashMap::new()),
            jobs: Arc::new(RecognitionJobs::default()),
        };
        let values = domain::EventValues {
            title: "Erfundene Therapie".into(),
            start_utc: "2031-05-17T08:00:00Z".into(),
            end_utc: "2031-05-17T08:30:00Z".into(),
            timezone: "Europe/Vienna".into(),
            location: "Raum 204".into(),
            notes: "Bestätigte Notiz\nmit zweiter Zeile".into(),
            reminder_minutes: Some(u32::MAX),
        };
        let events = std::collections::BTreeMap::from([
            ("with-reminder".into(), values.clone()),
            (
                "without-reminder".into(),
                domain::EventValues {
                    reminder_minutes: None,
                    ..values
                },
            ),
        ]);
        let exclusions = vec!["second".into(), "first".into(), "second".into()];
        let result = bridge.overlaps(events.clone(), exclusions.clone()).unwrap();
        assert_eq!(
            result,
            Some(vec![
                domain::CalendarOverlap {
                    appointment_id: "later".into(),
                    external_id: "native-later".into(),
                    title: "Spätere Überschneidung".into(),
                    start_utc: "2031-05-17T09:00:00Z".into(),
                    end_utc: "2031-05-17T09:30:00Z".into(),
                },
                domain::CalendarOverlap {
                    appointment_id: "earlier".into(),
                    external_id: "native-earlier".into(),
                    title: "Frühere Überschneidung".into(),
                    start_utc: "2031-05-17T08:00:00Z".into(),
                    end_utc: "2031-05-17T08:30:00Z".into(),
                },
            ])
        );
        assert_eq!(
            calls.lock().unwrap().as_slice(),
            [(
                "typedOverlaps".into(),
                json!({"events":events,"exclude":exclusions}),
            )]
        );
        let empty = HostBridge {
            host: Box::new(Host::default()),
            progress: Mutex::new(HashMap::new()),
            jobs: Arc::new(RecognitionJobs::default()),
        };
        assert_eq!(
            empty.overlaps(Default::default(), vec![]).unwrap(),
            Some(vec![])
        );
    }
    #[test]
    fn typed_import_effects_preserve_identity_recovery_and_maintenance_warnings() {
        let calls = Arc::new(Mutex::new(vec![]));
        let bridge = HostBridge {
            host: Box::new(Host {
                calls: Some(calls.clone()),
                ..Host::default()
            }),
            progress: Mutex::new(HashMap::new()),
            jobs: Arc::new(RecognitionJobs::default()),
        };
        let values = domain::EventValues {
            title: "Erfundene Therapie".into(),
            start_utc: "2031-05-17T08:00:00Z".into(),
            end_utc: "2031-05-17T08:30:00Z".into(),
            timezone: "Europe/Vienna".into(),
            location: "Raum 204".into(),
            notes: "Bestätigte Notiz".into(),
            reminder_minutes: None,
        };
        let record = domain::ImportRecord {
            id: "owned".into(),
            schedule_id: "schedule".into(),
            calendar_id: "hidden".into(),
            external_id: Some("native-event".into()),
            approved: values.clone(),
            status: "saved".into(),
            operation_id: "durable-attempt".into(),
        };
        let snapshot = bridge.import_snapshot(vec![record.clone()]).unwrap();
        assert_eq!(snapshot.current["owned"], values);
        assert_eq!(snapshot.protected_ids, ["protected-series"]);
        let mut operation = domain::CalendarOperation {
            kind: "update".into(),
            id: record.id,
            calendar_id: record.calendar_id,
            external_id: record.external_id,
            before: Some(values.clone()),
            after: Some(values),
            requires_resolution: true,
            reason: "Fremde Änderung prüfen".into(),
        };
        for recovery_only in [false, true] {
            let result = bridge
                .apply_import(service::calendar_imports::ApplyRequest {
                    operation: operation.clone(),
                    recovery_only,
                })
                .unwrap();
            assert_eq!(result.id, "owned");
            assert_eq!(result.external_id.as_deref(), Some("native-event"));
            assert_eq!(
                result.status,
                if recovery_only { "uncertain" } else { "saved" }
            );
            assert_eq!(result.error.is_some(), recovery_only);
            assert_eq!(
                result.maintenance_warnings,
                ["Separate maintenance warning"]
            );
        }
        let observed = calls.lock().unwrap().clone();
        assert_eq!(observed.len(), 3);
        assert_eq!(observed[0].0, "typedSnapshot");
        assert_eq!(observed[0].1[0]["operation_id"], "durable-attempt");
        for (index, recovery_only) in [(1, false), (2, true)] {
            assert_eq!(observed[index].0, "typedApply");
            assert_eq!(
                observed[index].1,
                json!({"operation":operation,"recovery_only":recovery_only})
            );
        }
        for command in ["snapshot", "apply"] {
            assert!(bridge.call(command, json!({})).is_err());
        }
        operation.kind = "unsupported-kind".into();
        assert!(matches!(
            bridge.apply_import(service::calendar_imports::ApplyRequest {
                operation,
                recovery_only: false,
            }),
            Err(service::ServiceError::Storage(_))
        ));
        assert_eq!(
            calls.lock().unwrap().len(),
            3,
            "Invalid operation reached the host"
        );
    }
    #[test]
    fn typed_recognition_keeps_binary_input_and_complete_evidence_without_legacy_calls() {
        let calls = Arc::new(Mutex::new(vec![]));
        let regions = vec![Region {
            id: "r1".into(),
            polygon: vec![Point { x: 1.25, y: 7.5 }],
            frame: "page".into(),
            kind: "text".into(),
            parent: Some("page".into()),
            children: vec!["r2".into()],
        }];
        let observations = vec![OcrObservation {
            id: "o1".into(),
            text: "Raum 204".into(),
            region_ids: vec!["r1".into()],
            engine: "Apple Vision".into(),
            score: Some(0.75),
            alternatives: vec!["Raum 2O4".into()],
        }];
        let bridge = HostBridge {
            host: Box::new(Host {
                calls: Some(calls.clone()),
                recognition: Some(TextRecognitionResult {
                    regions: regions.clone(),
                    observations: observations.clone(),
                    duration_ms: 123,
                    identity: crate::TextRecognitionIdentity {
                        engine: "Apple Vision".into(),
                        revision: 3,
                        system_version: "fixture".into(),
                        language_correction: false,
                    },
                }),
                ..Host::default()
            }),
            progress: Mutex::new(HashMap::new()),
            jobs: Arc::new(RecognitionJobs::default()),
        };
        let input = service::text_recognition::Request {
            image: vec![0, 255, 128, 1],
            budget_ms: 1234,
        };
        let output = bridge.recognize_text(input.clone()).unwrap();
        assert_eq!(
            serde_json::to_value(output.regions).unwrap(),
            json!(regions)
        );
        assert_eq!(
            serde_json::to_value(output.observations).unwrap(),
            json!(observations)
        );
        assert_eq!(output.duration_ms, 123);
        assert_eq!(
            output.manifest,
            json!({"engine":"Apple Vision","revision":3,
            "system_version":"fixture","language_correction":false})
        );
        assert_eq!(
            calls.lock().unwrap().as_slice(),
            [(
                "typedRecognition".into(),
                json!({"image":[0,255,128,1],"budget_ms":1234})
            )]
        );
        for request in [
            service::text_recognition::Request {
                image: vec![],
                ..input.clone()
            },
            service::text_recognition::Request {
                budget_ms: 0,
                ..input.clone()
            },
            service::text_recognition::Request {
                budget_ms: 60_001,
                ..input
            },
        ] {
            assert!(bridge.recognize_text(request).is_err());
        }
        assert!(bridge.call("recognize", json!({})).is_err());
        assert_eq!(
            calls.lock().unwrap().len(),
            1,
            "Invalid/legacy input reached native host"
        );
    }
    #[test]
    fn current_event_effect_reaches_the_legacy_callback() {
        let bridge = HostBridge {
            host: Box::new(Host::default()),
            progress: Mutex::new(HashMap::new()),
            jobs: Arc::new(RecognitionJobs::default()),
        };
        let args = json!({"external_id":"synthetic-event"});
        let result = bridge.call("editSystemEvent", args.clone()).unwrap();
        assert_eq!(result["received_command"], "editSystemEvent");
        assert_eq!(result["arguments"], args);
        for command in [
            "unregistered-effect",
            "recognize",
            "resolveOwnedEvent",
            "queryEvents",
            "getEvent",
            "eventCalendars",
            "mutateEvent",
            "calendarStatus",
        ] {
            assert!(bridge.call(command, json!({})).is_err());
        }
    }
    #[test]
    fn every_native_failure_preserves_identity_through_service_dispatch() {
        use service::ServiceError as E;
        for expected in [
            E::Validation("Kalenderzugriff fehlt.".into()),
            E::Storage("Vorschau abgelaufen; läuft bereits".into()),
            E::PermissionDenied,
            E::Timeout("queryEvents".into()),
            E::UncertainWrite,
            E::ExpiredScan,
            E::StaleRevision,
            E::StaleProposal,
            E::Busy,
            E::Cancelled,
        ] {
            let bridge = HostBridge {
                host: Box::new(Host {
                    failure: Some(expected.clone()),
                    ..Host::default()
                }),
                progress: Mutex::new(HashMap::new()),
                jobs: Arc::new(RecognitionJobs::default()),
            };
            let actual = bridge
                .query_calendar(service::calendar_reads::Query {
                    calendar_ids: vec![],
                    start_utc: "2026-09-18T00:00:00Z".into(),
                    end_utc: "2026-09-19T00:00:00Z".into(),
                    timezone: "Europe/Vienna".into(),
                    selection_revision: 2,
                    records: vec![],
                })
                .unwrap_err();
            assert_eq!(actual, expected);
            assert_eq!(
                bridge
                    .resolve_calendar_event(service::calendar_reads::Reference {
                        calendar_id: "selected".into(),
                        external_id: "native".into(),
                        occurrence: "2026-09-18T08:00:00Z".into(),
                        expected_start_utc: "2026-09-18T08:00:00Z".into(),
                    })
                    .unwrap_err(),
                expected
            );
            assert_eq!(bridge.event_calendars().unwrap_err(), expected);
            assert_eq!(bridge.calendar_status().unwrap_err(), expected);
            assert_eq!(
                bridge.overlaps(Default::default(), vec![]).unwrap_err(),
                expected
            );
            assert_eq!(
                bridge
                    .recognize_text(service::text_recognition::Request {
                        image: vec![1],
                        budget_ms: 1234,
                    })
                    .unwrap_err(),
                expected
            );
            assert_eq!(platform_failure(failure(actual.clone())), expected);
            // Journal/maintenance projections keep their original string schema.
            assert_eq!(
                serde_json::to_value(actual).unwrap(),
                json!(expected.to_string())
            );
        }
    }
    #[test]
    fn native_photo_uses_binary_callback_without_json_effect() {
        let bridge = HostBridge {
            // Any JSON effect would fail; only the binary photo callback succeeds.
            host: Box::new(Host {
                failure: Some(service::ServiceError::Cancelled),
                ..Host::default()
            }),
            progress: Mutex::new(HashMap::new()),
            jobs: Arc::new(RecognitionJobs::default()),
        };
        let bytes = [0, 255, 128, b'{', b'"', 0];
        assert_eq!(
            bridge.decode_photo(&bytes).unwrap(),
            bytes.into_iter().rev().collect::<Vec<_>>()
        );
    }
    #[tokio::test]
    async fn saved_preferences_keep_widget_scope_and_separate_maintenance_failures() {
        for (failure, response, warned) in [
            (None, json!({}), false),
            (
                Some(service::ServiceError::PermissionDenied),
                json!({}),
                true,
            ),
            (
                None,
                json!({"reminders":{"error":"Synthetic notification failure"}}),
                true,
            ),
        ] {
            let directory = tempfile::tempdir().unwrap();
            let calls = Arc::new(Mutex::new(vec![]));
            let app = open_application(
                directory.path().to_str().unwrap().into(),
                "missing".into(),
                Box::new(Host {
                    failure,
                    calls: Some(calls.clone()),
                    response: Some(response),
                    recognition: None,
                    ..Host::default()
                }),
            )
            .await
            .unwrap();
            for selected in [vec!["selected-calendar".to_string()], vec![]] {
                let mut preferences = app.preferences().await.unwrap();
                preferences.display_calendar_ids = selected.clone();
                preferences.appearance = "dark".into();
                let saved = app
                    .save_preferences_detailed(preferences.clone())
                    .await
                    .unwrap();
                assert_eq!(
                    serde_json::to_value(&saved.preferences).unwrap(),
                    serde_json::to_value(&preferences).unwrap()
                );
                assert_eq!(!saved.maintenance_warnings.is_empty(), warned);
                assert_eq!(
                    serde_json::to_value(app.preferences().await.unwrap()).unwrap(),
                    serde_json::to_value(preferences).unwrap()
                );
                let call = calls.lock().unwrap().last().unwrap().clone();
                assert_eq!(call.0, "typedAgenda");
                assert_eq!(call.1["display_calendar_ids"], json!(selected));
            }
            assert_eq!(
                calls.lock().unwrap().len(),
                2,
                "Maintenance failure must not repeat a save"
            );
            let mut invalid = app.preferences().await.unwrap();
            invalid.timezone = "invalid-timezone".into();
            assert!(app.save_preferences_detailed(invalid).await.is_err());
            assert_eq!(
                calls.lock().unwrap().len(),
                2,
                "Rejected preferences must not change native caches"
            );
            assert_eq!(app.preferences().await.unwrap().timezone, "Europe/Vienna");
        }
    }
}

#[cfg(test)]
#[path = "recognition_job_tests.rs"]
mod recognition_job_tests;

fn allowed_trace_artifact(run: &domain::PipelineRun, artifact: &str) -> bool {
    run.config.detailed_debug
        && artifact.ends_with(".png")
        && artifact
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'-' | b'_' | b'.'))
        && !artifact.contains("..")
        && (run
            .stages
            .iter()
            .any(|stage| stage.artifacts.iter().any(|name| name == artifact))
            || run
                .refinement_attempts
                .iter()
                .any(|attempt| artifact == format!("region-{}.png", attempt.id)))
}

#[cfg(test)]
mod trace_tests {
    use super::*;
    #[test]
    fn trace_artifacts_require_debug_evidence_and_a_local_filename() {
        let mut run: domain::PipelineRun = serde_json::from_str(include_str!(
            "../../../../ml/evaluation/fixtures/sample-run.json"
        ))
        .unwrap();
        run.stages[0].artifacts = vec![
            "region-1.png".into(),
            "../private.png".into(),
            "/private.png".into(),
        ];
        assert!(!allowed_trace_artifact(&run, "region-1.png"));
        run.config.detailed_debug = true;
        assert!(allowed_trace_artifact(&run, "region-1.png"));
        run.refinement_attempts.push(
            serde_json::from_value(serde_json::json!({
                "id": "reread-0000", "target_ids": [], "reason": "unclear", "variant": "crop",
                "crop_to_original": [1,0,0,0,1,0,0,0,1], "crop_to_page": [1,0,0,0,1,0,0,0,1],
                "width": 20, "height": 10, "duration_ms": 1, "status": "complete",
                "observation_ids": [], "detail": "Synthetic test"
            }))
            .unwrap(),
        );
        assert!(allowed_trace_artifact(&run, "region-reread-0000.png"));
        for name in [
            "../private.png",
            "/private.png",
            "unlisted.png",
            "ledger.sqlite",
            "",
            "region-1.png/extra",
            "region-reread-0001.png",
        ] {
            assert!(!allowed_trace_artifact(&run, name));
        }
    }
}
