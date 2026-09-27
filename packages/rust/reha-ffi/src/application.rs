#[path = "application_errors.rs"]
mod errors;
#[path = "application_host.rs"]
mod host;
pub(crate) use errors::{failure, storage};
use host::{HostBridge, ProgressEntry};

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
    service::{self, Application},
    store::Store,
};
use serde_json::{json, Value};
use std::{
    collections::HashMap,
    path::PathBuf,
    sync::{Arc, Mutex},
};

type Result<T> = std::result::Result<T, AppError>;
fn read_photo_source(path: &std::path::Path) -> Result<Vec<u8>> {
    reha_core::photo_source::read(path).map_err(|error| match error {
        reha_core::Error::Invalid(message) => AppError::Validation { message },
        other => storage(other),
    })
}

// Preferences retain their version-compatible JSON storage boundary.
fn decode_stored_preferences(value: Value) -> Result<Preferences> {
    serde_json::from_value(value).map_err(storage)
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
        document: run.document.into(),
        appointments: run
            .appointments
            .into_iter()
            .map(TryInto::try_into)
            .collect::<Result<_>>()?,
        issues: run.issues.into_iter().map(Into::into).collect(),
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
                scans: store
                    .list_scans()
                    .map_err(storage)?
                    .into_iter()
                    .map(TryInto::try_into)
                    .collect::<Result<_>>()?,
                intakes: store
                    .intakes()
                    .map_err(storage)?
                    .into_iter()
                    .map(Into::into)
                    .collect(),
                batches: store
                    .batches()
                    .map_err(storage)?
                    .into_iter()
                    .map(TryInto::try_into)
                    .collect::<Result<_>>()?,
                plans: store
                    .plans()
                    .map_err(storage)?
                    .into_iter()
                    .map(Into::into)
                    .collect(),
                imports: store
                    .records(None)
                    .map_err(storage)?
                    .into_iter()
                    .map(Into::into)
                    .collect(),
                pending: store
                    .pending()
                    .map_err(storage)?
                    .into_iter()
                    .map(|(attempt_id, operation)| {
                        Ok(PendingWrite {
                            attempt_id,
                            operation: operation.try_into()?,
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
                let outcome = service::scan::import_image(
                    bridge,
                    &state,
                    service::inference::ImportRequest {
                        id,
                        filename: intake.filename,
                        bytes,
                        config: intake.config,
                        force: true,
                    },
                )
                .await
                .map_err(failure)?;
                snapshot(outcome.run)
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
                stages: run.stages.into_iter().map(Into::into).collect(),
                source_hash: run.document.source_hash,
                total_ms: run.total_ms,
            })
        })
        .await
    }
    /// Read retained evidence without refreshing extraction or invoking calendar effects.
    pub async fn plan_evidence(
        &self,
        request: crate::PlanEvidenceRequest,
    ) -> Result<crate::PlanEvidenceResponse> {
        self.blocking(move |s| {
            uuid::Uuid::parse_str(&request.document_id).map_err(storage)?;
            let store = s.store.lock().map_err(storage)?;
            let run = store
                .load_run(&request.document_id)
                .map_err(|error| failure(service::domain_failure(error)))?;
            crate::plan_evidence::project(&run, &request)
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
        self.blocking(|s| {
            decode_stored_preferences(service::settings::settings_value(&s, None).map_err(failure)?)
        })
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
            let preferences = decode_stored_preferences(persisted)?;
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
                    appointments
                        .into_iter()
                        .map(TryInto::try_into)
                        .collect::<Result<_>>()?,
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
        self.blocking(move |s| {
            service::draft::assess(&s, id, timezone)
                .map_err(failure)?
                .try_into()
        })
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
                service::draft::preview(bridge, &state, id, calendar_id, timezone, reminder)
                    .await
                    .map_err(failure)?
                    .try_into()
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
                service::draft::preview_replacement(
                    bridge,
                    &state,
                    id,
                    calendar_id,
                    timezone,
                    reminder,
                )
                .await
                .map_err(failure)?
                .try_into()
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
                value.map(Into::into),
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
                service::draft::accept_and_save(bridge, &state, token, selection, approve_removals)
                    .await
                    .map_err(failure)?
                    .try_into()
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
                .map_err(failure)?
                .try_into()
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
            service::calendar::resolve_proposal(&s, token, event_id, choice)
                .map_err(failure)?
                .try_into()
        })
        .await
    }
    pub async fn prepare_undo(&self, batch_id: String) -> Result<Proposal> {
        let state = self.state.clone();
        let bridge = self.bridge.clone();
        runtime()
            .spawn(async move {
                service::undo::prepare(bridge, &state, batch_id)
                    .await
                    .map_err(failure)?
                    .try_into()
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
                service::calendar::approve_calendar(bridge, &state, token, approve_removals)
                    .await
                    .map_err(failure)?
                    .into_iter()
                    .map(TryInto::try_into)
                    .collect::<Result<_>>()
            })
            .await
            .map_err(storage)?
    }
    pub async fn reconcile_calendar(&self) -> Result<Vec<CalendarResult>> {
        let state = self.state.clone();
        let bridge = self.bridge.clone();
        runtime()
            .spawn(async move {
                service::calendar::reconcile_calendar(bridge, &state)
                    .await
                    .map_err(failure)?
                    .into_iter()
                    .map(TryInto::try_into)
                    .collect::<Result<_>>()
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
        self.bridge
            .progress
            .lock()
            .ok()?
            .get(&id)
            .map(|entry| entry.value.clone())
    }
    /// Independent of decoding/model availability. Safe to acknowledge only after this returns.
    pub async fn stage_photo(&self, id: String, path: String) -> Result<IntakeSummary> {
        self.blocking(move |s| {
            let path = PathBuf::from(path);
            let bytes = read_photo_source(&path)?;
            let store = s.store.lock().map_err(storage)?;
            Ok(store
                .stage_intake(
                    &id,
                    &path.file_name().unwrap_or_default().to_string_lossy(),
                    &bytes,
                    &domain::PipelineConfig::default(),
                    chrono::Utc::now().timestamp(),
                )
                .map_err(storage)?
                .into())
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
                self.bridge.finish_progress(
                    &self.id,
                    &self.job.cancellation_flag(),
                    if self.job.is_cancelled() {
                        JobState::Cancelled
                    } else {
                        self.state
                    },
                );
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
                    progress.retain(|_, entry| entry.value.state == JobState::Running);
                    let update = service::progress::ProgressUpdate::new(&id, "Foto vorbereiten");
                    progress.insert(
                        id.clone(),
                        ProgressEntry {
                            attempt: job.cancellation_flag(),
                            value: JobProgress {
                                id: update.id,
                                stage: update.stage,
                                elapsed_ms: update.elapsed_ms,
                                budget_ms: update.budget_ms,
                                draft_available: update.draft_available,
                                state: JobState::Running,
                            },
                        },
                    );
                }
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
                let points: Vec<domain::Point> = request
                    .page_corners
                    .into_iter()
                    .map(TryInto::try_into)
                    .collect::<Result<_>>()?;
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
                bytes,
                config,
                force: request.force,
            };
            if job.is_cancelled() {
                return Err(AppError::Cancelled);
            }
            let outcome = service::scan::import_image(bridge, &state, request)
                .await
                .map_err(failure)?;
            Ok(ScanOutcome {
                duplicate: outcome.duplicate,
                scan: snapshot(outcome.run)?,
            })
        })
        .await
    }
}

#[uniffi::export]
pub fn new_appointment(date: Option<String>) -> Result<Appointment> {
    let mut appointment = domain::Appointment::empty(uuid::Uuid::new_v4().to_string());
    appointment.date = date;
    appointment.try_into()
}
#[uniffi::export]
pub fn confirm_appointment_fields(appointment: Appointment) -> Result<Appointment> {
    let mut a: domain::Appointment = appointment.try_into()?;
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
    a.try_into()
}
#[uniffi::export]
pub fn accept_suggestion(
    appointment: Appointment,
    suggestion_id: String,
    accept: bool,
) -> Result<Appointment> {
    let mut a: domain::Appointment = appointment.try_into()?;
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
    a.try_into()
}
#[uniffi::export]
pub fn appointment_issues(appointment: Appointment, timezone: String) -> Result<Vec<Issue>> {
    let a: domain::Appointment = appointment.try_into()?;
    let assessment = reha_core::readiness::appointment(&a, "", &timezone);
    Ok(assessment
        .issues
        .into_iter()
        .chain(assessment.warnings)
        .map(Into::into)
        .collect())
}

#[cfg(test)]
#[path = "application_host_routing_tests.rs"]
mod host_routing_tests;

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
#[path = "application_preference_storage_tests.rs"]
mod preference_storage_tests;

#[cfg(test)]
#[path = "application_trace_tests.rs"]
mod trace_tests;
