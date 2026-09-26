use crate::{records::*, runtime, AppError};
use base64::{engine::general_purpose::STANDARD, Engine};
use reha_core::{
    contracts as domain,
    service::{self, Application, Platform},
    store::Store,
};
use serde::{de::DeserializeOwned, Serialize};
use serde_json::{json, Value};
use std::{
    collections::{HashMap, HashSet},
    path::PathBuf,
    sync::{Arc, Mutex},
};

type Result<T> = std::result::Result<T, AppError>;
fn convert<T: Serialize, U: DeserializeOwned>(value: T) -> Result<U> {
    serde_json::from_value(serde_json::to_value(value).map_err(storage)?).map_err(storage)
}
fn storage(e: impl std::fmt::Display) -> AppError {
    AppError::Storage {
        message: e.to_string(),
    }
}
fn failure(message: String) -> AppError {
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
    fn snapshot(&self, records: Vec<ImportRecord>) -> Result<LiveCalendar>;
    fn apply(&self, operation: CalendarOperation, recovery_only: bool) -> Result<CalendarResult>;
    fn decode_photo(&self, bytes: Vec<u8>) -> Result<Vec<u8>>;
    fn sync_agenda(&self, records: Vec<ImportRecord>, preferences: Preferences) -> Result<()>;
    fn forget_calendar(&self) -> Result<()>;
    fn overlaps(
        &self,
        events: HashMap<String, EventValues>,
        exclude: Vec<String>,
    ) -> Result<Vec<CalendarOverlap>>;
}
struct HostBridge {
    host: Box<dyn AppleHost>,
    progress: Mutex<HashMap<String, JobProgress>>,
    cancelled: Mutex<HashSet<String>>,
}
impl Platform for HostBridge {
    fn overlaps(
        &self,
        events: std::collections::BTreeMap<String, domain::EventValues>,
        exclude: Vec<String>,
    ) -> service::Response<Option<Vec<domain::CalendarOverlap>>> {
        let result =
            (|| -> Result<_> { convert(self.host.overlaps(convert(events)?, exclude)?) })();
        result.map(Some).map_err(|e| e.to_string())
    }
    fn cancelled(&self, id: &str) -> bool {
        self.cancelled
            .lock()
            .map(|ids| ids.contains(id))
            .unwrap_or(true)
    }
    fn call(&self, command: &str, args: Value) -> service::Response<Value> {
        let run = || -> Result<Value> {
            match command {
                "calendarStatus"
                | "eventCalendars"
                | "queryEvents"
                | "getEvent"
                | "mutateEvent"
                | "editSystemEvent"
                | "resolveOwnedEvent"
                | "inspectCalendarLinks"
                | "recognize" => serde_json::from_str(
                    &self
                        .host
                        .calendar_event_call(command.into(), args.to_string())?,
                )
                .map_err(storage),
                "snapshot" => {
                    let live = self.host.snapshot(convert(args["records"].clone())?)?;
                    Ok(json!({"current":live.current, "protected_ids":live.protected_ids}))
                }
                "apply" => Ok(serde_json::to_value(self.host.apply(
                    convert(args["operation"].clone())?,
                    args["recovery_only"].as_bool().unwrap_or(true),
                )?)
                .map_err(storage)?),
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
        run().map_err(|e| e.to_string())
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
    state: Arc<Application>,
    bridge: Arc<HostBridge>,
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
            store
                .cleanup(chrono::Utc::now().timestamp())
                .map_err(storage)?;
            Ok(Arc::new(NativeApplication {
                state: Arc::new(Application::new(store, PathBuf::from(models))),
                bridge: Arc::new(HostBridge {
                    host,
                    progress: Mutex::new(HashMap::new()),
                    cancelled: Mutex::new(HashSet::new()),
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
        self.state
            .cancel
            .lock()
            .map(|jobs| !jobs.is_empty())
            .unwrap_or(true)
    }
    pub async fn retry_capture(&self, id: String) -> Result<ReviewSnapshot> {
        if self.recognition_busy() {
            return Err(AppError::Busy);
        }
        self.bridge.cancelled.lock().map_err(storage)?.remove(&id);
        let state = self.state.clone();
        let bridge = self.bridge.clone();
        runtime()
            .spawn(async move {
                let staged = {
                    let store = state.store.lock().map_err(storage)?;
                    if store.load_run(&id).is_ok() {
                        None
                    } else {
                        let intake = store
                            .intakes()
                            .map_err(storage)?
                            .into_iter()
                            .find(|i| i.id == id && i.status != "deleted")
                            .ok_or(AppError::ExpiredScan)?;
                        Some((
                            intake,
                            std::fs::read(store.source_path(&id).map_err(storage)?)
                                .map_err(storage)?,
                        ))
                    }
                };
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
            .map_err(storage)?
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
            service::settings::settings_value(&s, Some(existing)).map_err(failure)?;
            let records = {
                let store = s.store.lock().map_err(storage)?;
                store.owned_records().map_err(storage)?
            };
            bridge.host.calendar_event_call(
                "agenda".into(),
                json!({"records":records,"preferences":{
                    "enabled":value.app_reminders_enabled,"minutes":value.app_reminder_minutes,
                    "sound":value.reminder_sound,"preview":value.reminder_preview
                }})
                .to_string(),
            )?;
            Ok(value)
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
    pub fn cancel_job(&self, id: String) -> Result<()> {
        self.bridge
            .cancelled
            .lock()
            .map_err(storage)?
            .insert(id.clone());
        self.state.cancel_job(&id).map_err(failure)
    }
    pub fn job_progress(&self, id: String) -> Option<JobProgress> {
        self.bridge.progress.lock().ok()?.get(&id).cloned()
    }
    /// Independent of decoding/model availability. Safe to acknowledge only after this returns.
    pub async fn stage_photo(&self, id: String, path: String) -> Result<IntakeSummary> {
        self.blocking(move |s| {
            let path = PathBuf::from(path);
            if std::fs::metadata(&path).map_err(storage)?.len() > 40 * 1024 * 1024 {
                return Err(AppError::Validation {
                    message: "Foto maximal 40 MB.".into(),
                });
            }
            let bytes = std::fs::read(&path).map_err(storage)?;
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
    pub async fn import_photo(&self, request: PhotoRequest) -> Result<ScanOutcome> {
        self.import_photo_with_debug(request, false).await
    }
    /// Same pipeline as a regular import, with retained detector crops for tracing.
    pub async fn import_trace_photo(&self, request: PhotoRequest) -> Result<ScanOutcome> {
        self.import_photo_with_debug(request, true).await
    }
}
impl NativeApplication {
    async fn import_photo_with_debug(
        &self,
        request: PhotoRequest,
        detailed_debug: bool,
    ) -> Result<ScanOutcome> {
        let state = self.state.clone();
        let bridge = self.bridge.clone();
        let id = request.id.clone();
        struct CancelOnDrop {
            state: Arc<Application>,
            bridge: Arc<HostBridge>,
            id: String,
            armed: bool,
        }
        impl Drop for CancelOnDrop {
            fn drop(&mut self) {
                if self.armed {
                    if let Ok(mut ids) = self.bridge.cancelled.lock() {
                        ids.insert(self.id.clone());
                    }
                    let _ = self.state.cancel_job(&self.id);
                }
            }
        }
        let mut guard = CancelOnDrop {
            state: state.clone(),
            bridge: bridge.clone(),
            id: id.clone(),
            armed: true,
        };
        let result = runtime()
            .spawn(async move {
                if bridge.cancelled(&id) {
                    return Err(AppError::Cancelled);
                }
                let path = PathBuf::from(&request.path);
                let bytes = tokio::task::spawn_blocking(move || {
                    let metadata = std::fs::metadata(&path).map_err(storage)?;
                    if metadata.len() > 40 * 1024 * 1024 {
                        return Err(AppError::Validation {
                            message: "Foto maximal 40 MB.".into(),
                        });
                    }
                    std::fs::read(path).map_err(storage)
                })
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
                if bridge.cancelled(&id) {
                    return Err(AppError::Cancelled);
                }
                bridge
                    .progress
                    .lock()
                    .map_err(storage)?
                    .retain(|_, p| p.state == JobState::Running);
                bridge.progress(json!({"id":id,"stage":"Foto vorbereiten"}));
                let result = service::scan::import_image(bridge.clone(), &state, request)
                    .await
                    .map_err(failure);
                if let Ok(mut progress) = bridge.progress.lock() {
                    if let Some(p) = progress.get_mut(&id) {
                        p.state = if bridge.cancelled(&id) {
                            JobState::Cancelled
                        } else if result.is_ok() {
                            JobState::Completed
                        } else {
                            JobState::Failed
                        };
                    }
                }
                bridge.cancelled.lock().map_err(storage)?.remove(&id);
                let value = result?;
                Ok(ScanOutcome {
                    duplicate: value["duplicate"].as_bool().unwrap_or(false),
                    scan: snapshot(serde_json::from_value(value["run"].clone()).map_err(storage)?)?,
                })
            })
            .await
            .map_err(storage)?;
        guard.armed = false;
        result
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
        reha_core::review::set_value(&mut a, &field, value).map_err(|e| failure(e.to_string()))?;
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
    struct Host;
    impl AppleHost for Host {
        fn calendar_event_call(&self, command: String, arguments: String) -> Result<String> {
            Ok(json!({"received_command": command, "arguments": serde_json::from_str::<Value>(&arguments).unwrap()}).to_string())
        }
        fn snapshot(&self, _: Vec<ImportRecord>) -> Result<LiveCalendar> {
            unreachable!()
        }
        fn apply(&self, _: CalendarOperation, _: bool) -> Result<CalendarResult> {
            unreachable!()
        }
        fn decode_photo(&self, _: Vec<u8>) -> Result<Vec<u8>> {
            unreachable!()
        }
        fn sync_agenda(&self, _: Vec<ImportRecord>, _: Preferences) -> Result<()> {
            unreachable!()
        }
        fn forget_calendar(&self) -> Result<()> {
            unreachable!()
        }
        fn overlaps(
            &self,
            _: HashMap<String, EventValues>,
            _: Vec<String>,
        ) -> Result<Vec<CalendarOverlap>> {
            unreachable!()
        }
    }
    #[test]
    fn vision_and_current_event_effects_reach_the_native_callback() {
        let bridge = HostBridge {
            host: Box::new(Host),
            progress: Mutex::new(HashMap::new()),
            cancelled: Mutex::new(HashSet::new()),
        };
        for command in ["recognize", "resolveOwnedEvent", "editSystemEvent"] {
            let args = json!({"base64":"synthetic-crop", "budget_ms":1234});
            let result = bridge.call(command, args.clone()).unwrap();
            assert_eq!(result["received_command"], command);
            assert_eq!(result["arguments"], args);
        }
        assert!(bridge.call("unregistered-effect", json!({})).is_err());
    }
}

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
        let mut run: domain::PipelineRun =
            serde_json::from_str(include_str!("../../../tests/fixtures/sample-run.json")).unwrap();
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
