//! Calendar editing independent of photo ownership. Only an explicit UI confirmation
//! consumes a volatile proposal; confirmed requests alone enter the durable journal.
use super::{failure, AppState, Platform, Response};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::sync::Arc;

#[derive(Clone, Serialize, Deserialize, Debug)]
pub struct EventProposal {
    pub token: String,
    pub session: String,
    pub revision: u64,
    pub expires_at: i64,
    pub kind: String,
    pub calendar_id: String,
    pub calendar_title: String,
    pub before: Option<Value>,
    pub patch: Value,
    pub undo_of: Option<String>,
    #[serde(default)]
    pub owned_id: Option<String>,
    #[serde(default = "unknown_origin")]
    pub origin: String,
}
fn unknown_origin() -> String {
    "unknown".into()
}
fn required<'a>(v: &'a Value, key: &str) -> Response<&'a str> {
    v[key]
        .as_str()
        .filter(|s| !s.is_empty())
        .ok_or_else(|| format!("{key} fehlt.").into())
}
fn preferences(state: &AppState) -> Response<Value> {
    super::settings::settings_value(state, None)
}
fn ids(p: &Value) -> Vec<String> {
    p["display_calendar_ids"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|s| s.as_str().map(str::to_string))
        .collect()
}

/// A read is bound to one visible selection, independently of the save target
/// and reminder ownership. The revision also detects A -> B -> A changes.
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct AgendaScope {
    pub calendar_ids: Vec<String>,
    pub timezone: String,
    pub revision: u64,
}
impl AgendaScope {
    fn current(state: &AppState) -> Response<Self> {
        let p = preferences(state)?;
        let mut calendar_ids = ids(&p);
        calendar_ids.sort();
        calendar_ids.dedup();
        Ok(Self {
            calendar_ids,
            timezone: p["timezone"].as_str().unwrap_or("Europe/Vienna").into(),
            revision: p["display_selection_revision"].as_u64().unwrap_or(0),
        })
    }
}
async fn native(platform: &Arc<dyn Platform>, name: &'static str, args: Value) -> Response<Value> {
    let platform = platform.clone();
    tokio::task::spawn_blocking(move || platform.call(name, args))
        .await
        .map_err(failure)?
}
fn check_patch(kind: &str, patch: &Value, before: Option<&Value>) -> Response<()> {
    let fields = patch.as_object().ok_or("Terminwerte fehlen.")?;
    if fields.keys().any(|k| {
        ![
            "title",
            "start_utc",
            "end_utc",
            "timezone",
            "location",
            "reminder_minutes",
        ]
        .contains(&k.as_str())
    }) {
        return Err("Nicht unterstützte Terminänderung.".into());
    }
    if kind == "remove" {
        if !fields.is_empty() {
            return Err("Löschung enthält neue Werte.".into());
        }
        return Ok(());
    }
    if !["create", "update"].contains(&kind) || fields.is_empty() {
        return Err("Aktion fehlt.".into());
    }
    let mut values = before.map(|b| b["values"].clone()).unwrap_or(json!({}));
    if !values.is_object() {
        return Err("Ausgangswerte fehlen.".into());
    }
    values.as_object_mut().unwrap().extend(fields.clone());
    if required(&values, "title")?.trim().is_empty() {
        return Err("Bezeichnung fehlt.".into());
    }
    let start = chrono::DateTime::parse_from_rfc3339(required(&values, "start_utc")?)
        .map_err(|_| "Beginn ungültig.")?;
    let end = chrono::DateTime::parse_from_rfc3339(required(&values, "end_utc")?)
        .map_err(|_| "Ende ungültig.")?;
    if end <= start || end.signed_duration_since(start).num_days() > 366 {
        return Err("Ende muss nach Beginn liegen (maximal ein Jahr).".into());
    }
    required(&values, "timezone")?
        .parse::<chrono_tz::Tz>()
        .map_err(|_| "Zeitzone ungültig.")?;
    if let Some(m) = values.get("reminder_minutes").filter(|v| !v.is_null()) {
        if !m.as_u64().is_some_and(|m| m <= 10080) {
            return Err("Erinnerung ungültig.".into());
        }
    }
    for k in ["title", "location"] {
        if values
            .get(k)
            .is_some_and(|v| v.as_str().is_none_or(|s| s.len() > 4000))
        {
            return Err("Termintext ungültig.".into());
        }
    }
    Ok(())
}
async fn check_calendar(
    platform: &Arc<dyn Platform>,
    state: &AppState,
    calendar: &str,
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
        .any(|r| r.calendar_id == calendar && r.status == "saved");
    if !(ids(&p).contains(&calendar.to_string())
        || !create && imported
        || create && p["calendar_id"].as_str() == Some(calendar))
    {
        return Err("Kalenderauswahl enthält diesen Kalender nicht.".into());
    }
    let all = native(platform, "eventCalendars", json!({})).await?;
    let selected = all["calendars"]
        .as_array()
        .and_then(|a| a.iter().find(|v| v["id"] == calendar))
        .ok_or("Kalender nicht verfügbar.")?;
    if selected["writable"] != true {
        return Err("Dieser Kalender ist schreibgeschützt.".into());
    }
    Ok(format!(
        "{} · {}",
        selected["title"].as_str().unwrap_or("Kalender"),
        selected["source"].as_str().unwrap_or_default()
    ))
}
pub async fn query(platform: Arc<dyn Platform>, state: &AppState, args: Value) -> Response<Value> {
    let start = chrono::DateTime::parse_from_rfc3339(required(&args, "start_utc")?)
        .map_err(|_| "Suchbeginn ungültig.")?;
    let end = chrono::DateTime::parse_from_rfc3339(required(&args, "end_utc")?)
        .map_err(|_| "Suchende ungültig.")?;
    if end <= start || end - start > chrono::Duration::days(366) {
        return Err("Suchzeitraum: maximal ein Jahr.".into());
    }
    let scope = AgendaScope::current(state)?;
    if let Some(requested) = args.get("scope") {
        let requested: AgendaScope = serde_json::from_value(requested.clone()).map_err(failure)?;
        if requested != scope {
            return Err("Kalenderauswahl wurde geändert. Erneut laden.".into());
        }
    }
    if scope.calendar_ids.is_empty() {
        return Ok(
            json!({"events":[],"unavailable_calendar_ids":[],"unavailable_events":[],"scope":scope}),
        );
    }
    let selected = &scope.calendar_ids;
    let records: Vec<_> = state
        .store
        .lock()
        .map_err(failure)?
        .owned_records()
        .map_err(failure)?
        .into_iter()
        .filter(|r| r.status == "saved" && r.external_id.is_some())
        .collect();
    let mut result = super::calendar_reads::query(
        &platform,
        super::calendar_reads::Query {
            calendar_ids: selected.clone(),
            records,
            start_utc: required(&args, "start_utc")?.into(),
            end_utc: required(&args, "end_utc")?.into(),
            timezone: scope.timezone.clone(),
            selection_revision: scope.revision,
        },
    )
    .await?;
    if AgendaScope::current(state)? != scope {
        return Err("Kalenderauswahl wurde während des Ladens geändert. Erneut laden.".into());
    }
    if result["events"].as_array().is_none_or(|a| {
        a.iter()
            .any(|e| !selected.contains(&e["calendar_id"].as_str().unwrap_or_default().to_string()))
    }) {
        return Err("Kalenderantwort außerhalb der Auswahl.".into());
    }
    result["scope"] = serde_json::to_value(scope).map_err(failure)?;
    Ok(result)
}
fn require_selected_event(state: &AppState, calendar: &str, event: &Value) -> Response<()> {
    if !ids(&preferences(state)?).contains(&calendar.to_string()) {
        let records = state
            .store
            .lock()
            .map_err(failure)?
            .owned_records()
            .map_err(failure)?;
        if !records.iter().any(|r| {
            r.status == "saved"
                && r.calendar_id == calendar
                && r.external_id.as_deref() == event["external_id"].as_str()
                && event["metadata"]["url"].as_str()
                    == Some(format!("reha-calendar://event/{}", r.id).as_str())
        }) {
            return Err("Dieser Termin gehört nicht zur Kalenderauswahl.".into());
        }
    }
    Ok(())
}
async fn preview(
    platform: Arc<dyn Platform>,
    state: &AppState,
    args: Value,
    undo_of: Option<String>,
) -> Response<Value> {
    let session = required(&args, "session")?.to_string();
    let lease = state
        .event_sessions
        .lock()
        .map_err(failure)?
        .lease(&session)?;
    let _guard = state.calendar_lock.lock().await;
    lease.check()?;
    let kind = required(&args, "kind")?.to_string();
    let calendar = required(&args, "calendar_id")?.to_string();
    let title = check_calendar(&platform, state, &calendar, kind == "create").await?;
    let before = if kind == "create" {
        None
    } else {
        let supplied = args.get("event").ok_or("Termin fehlt.")?;
        if supplied["calendar_id"] != calendar {
            return Err("Kalenderzuordnung geändert.".into());
        }
        let current = super::calendar_reads::resolve(&platform, supplied).await?;
        if current["event"].is_null() {
            return Err("Termin nicht verfügbar. Kalender neu laden.".into());
        }
        let event = current["event"].clone();
        if undo_of.is_some() && event != *supplied {
            return Err("Spätere Kalenderänderung geschützt. Rückgängig nicht möglich.".into());
        }
        require_selected_event(state, &calendar, &event)?;
        if event["system_only"] == true {
            lease.check()?;
            return Ok(json!({"system_editor":event}));
        }
        Some(event)
    };
    check_patch(&kind, &args["patch"], before.as_ref())?;
    let owned_id = if let Some(id) = &undo_of {
        let old = state
            .store
            .lock()
            .map_err(failure)?
            .event_mutation(id)
            .map_err(failure)?
            .ok_or("Verlaufseintrag fehlt.")?;
        serde_json::from_value::<EventProposal>(old["proposal"].clone())
            .map_err(failure)?
            .owned_id
    } else if kind == "create" {
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
                r.external_id.as_deref() == event["external_id"].as_str()
                    && event["metadata"]["url"].as_str()
                        == Some(format!("reha-calendar://event/{}", r.id).as_str())
            })
            .map(|r| r.id)
    };
    let origin = if undo_of.is_some() {
        "unknown"
    } else if args["origin"] == "voice" {
        "voice"
    } else {
        "manual"
    }
    .to_string();
    let proposal = EventProposal {
        owned_id,
        origin,
        token: uuid::Uuid::new_v4().to_string(),
        session: session.clone(),
        revision: args["revision"].as_u64().unwrap_or(0),
        expires_at: chrono::Utc::now().timestamp() + 300,
        kind,
        calendar_id: calendar,
        calendar_title: title,
        before,
        patch: args["patch"].clone(),
        undo_of,
    };
    // Serialize this final check/publication with revocation; the lease remains
    // revoked even after its registry entry has been removed.
    let _sessions = state.event_sessions.lock().map_err(failure)?;
    lease.check()?;
    let mut proposals = state.event_proposals.lock().map_err(failure)?;
    proposals.retain(|_, p| p.session != session && p.expires_at > chrono::Utc::now().timestamp());
    proposals.insert(proposal.token.clone(), proposal.clone());
    Ok(json!({"proposal":proposal}))
}
async fn confirm(platform: Arc<dyn Platform>, state: &AppState, args: Value) -> Response<Value> {
    let _guard = state.calendar_lock.lock().await;
    let token = required(&args, "token")?;
    // An exact replay returns the journalled result and never invokes EventKit again.
    if let Some(item) = state
        .store
        .lock()
        .map_err(failure)?
        .event_mutation(token)
        .map_err(failure)?
    {
        return Ok(item["result"]
            .as_object()
            .map(|_| item["result"].clone())
            .unwrap_or(json!({"status":"uncertain"})));
    }
    let proposal = state
        .event_proposals
        .lock()
        .map_err(failure)?
        .remove(token)
        .ok_or("Vorschau abgelaufen. Erneut prüfen.")?;
    if args["confirmation"] != "button"
        || args["session"] != proposal.session
        || args["revision"] != proposal.revision
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
        proposal.kind == "create",
    )
    .await?;
    if let Some(before) = &proposal.before {
        require_selected_event(state, &proposal.calendar_id, before)?;
        let current = super::calendar_reads::resolve(&platform, before).await?;
        if current["event"] != *before {
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
    let mut result = native(
        &platform,
        "mutateEvent",
        json!({"proposal":proposal,"recovery_only":false}),
    )
    .await
    .unwrap_or(
        json!({"status":"uncertain","message":"Schreibstatus unklar. Abgleich erforderlich."}),
    );
    state
        .store
        .lock()
        .map_err(failure)?
        .finish_event_mutation(token, &result)
        .map_err(failure)?;
    // Ownership and the durable journal are committed before reminder reconciliation.
    for warning in super::agenda::sync_warnings(&platform, state).await {
        let mut warnings = result["maintenance_warnings"]
            .as_array()
            .cloned()
            .unwrap_or_default();
        warnings.push(json!(warning));
        result["maintenance_warnings"] = json!(warnings);
    }
    Ok(result)
}
async fn undo(platform: Arc<dyn Platform>, state: &AppState, args: Value) -> Response<Value> {
    let history = state
        .store
        .lock()
        .map_err(failure)?
        .event_history()
        .map_err(failure)?;
    let item = history
        .iter()
        .find(|h| h["id"] == args["id"])
        .ok_or("Verlaufseintrag fehlt.")?;
    if item["status"] != "saved" || !item["undone_by"].is_null() {
        return Err("Dieser Vorgang kann nicht erneut rückgängig gemacht werden.".into());
    }
    let old: EventProposal = serde_json::from_value(item["proposal"].clone()).map_err(failure)?;
    let after = &item["result"]["event"];
    let (kind, event, patch) = match old.kind.as_str() {
        "create" => ("remove", after.clone(), json!({})),
        "update" => {
            let before = old
                .before
                .as_ref()
                .ok_or("Wiederherstellungsdaten fehlen.")?;
            let mut patch = json!({});
            for key in old.patch.as_object().unwrap().keys() {
                patch[key] = before["values"][key].clone();
            }
            ("update", after.clone(), patch)
        }
        "remove" => (
            "create",
            Value::Null,
            old.before
                .as_ref()
                .ok_or("Wiederherstellungsdaten fehlen.")?["values"]
                .clone(),
        ),
        _ => return Err("Ungültiger Verlaufseintrag.".into()),
    };
    if kind != "create" {
        let current = super::calendar_reads::resolve(&platform, &event).await?;
        if current["event"] != event {
            return Err("Spätere Kalenderänderung geschützt. Rückgängig nicht möglich.".into());
        }
    }
    // Only editable fields form the preview. Restoration metadata is recovered
    // by the native adapter from the confirmed original journal receipt.
    let mut patch = patch;
    patch
        .as_object_mut()
        .ok_or("Werte fehlen.")?
        .retain(|k, _| {
            [
                "title",
                "start_utc",
                "end_utc",
                "timezone",
                "location",
                "reminder_minutes",
            ]
            .contains(&k.as_str())
        });
    preview(platform,state,json!({"kind":kind,"calendar_id":old.calendar_id,"event":event,"patch":patch,"session":args["session"],"revision":args["revision"]}),Some(old.token)).await
}
pub async fn dispatch(
    platform: Arc<dyn Platform>,
    state: &AppState,
    command: &str,
    args: Value,
) -> Response<Value> {
    match command {
        "activityPage" => serde_json::to_value(
            state
                .store
                .lock()
                .map_err(failure)?
                .activity_page(
                    args["limit"].as_u64().map(|n| n.min(100) as u32),
                    args["cursor"].as_str(),
                    args["source"].as_str(),
                )
                .map_err(failure)?,
        )
        .map_err(failure),
        "activityDetail" => {
            let id = required(&args, "id")?;
            let (source, id) = id.split_once(':').ok_or("Ungültiger Verlaufseintrag.")?;
            let store = state.store.lock().map_err(failure)?;
            match source {
                "import" => {
                    serde_json::to_value(store.batch(id).map_err(failure)?).map_err(failure)
                }
                "event" => Ok(store
                    .event_mutation(id)
                    .map_err(failure)?
                    .unwrap_or(Value::Null)),
                "capture" => Ok(json!({"document_id":id})),
                "recognition" => {
                    let result: (String, String, Option<String>) = store
                        .connection
                        .query_row(
                            "SELECT scan_id,status,error FROM processing_attempts WHERE id=?1",
                            [id],
                            |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
                        )
                        .map_err(failure)?;
                    Ok(json!({"document_id":result.0,"status":result.1,"error":result.2}))
                }
                _ => Err("Unbekannter Verlaufseintrag.".into()),
            }
        }
        "ownedEventRecords" => Ok(
            json!({"records":state.store.lock().map_err(failure)?.owned_records().map_err(failure)?}),
        ),
        "resolveOwnedEvent" => {
            let id = required(&args, "id")?;
            uuid::Uuid::parse_str(id).map_err(failure)?;
            let _guard = state.calendar_lock.lock().await;
            let record = state
                .store
                .lock()
                .map_err(failure)?
                .owned_record(id)
                .map_err(failure)?;
            match record {
                Some(record) if record.status == "saved" => {
                    native(&platform, "resolveOwnedEvent", json!({"record":record})).await
                }
                Some(_) => Ok(json!({"status":"deleted"})),
                None => Ok(json!({"status":"missing"})),
            }
        }
        "inspectCalendarRepair" | "confirmCalendarRepair" => {
            super::calendar_repair::run(platform, state, command, args).await
        }
        "calendarStatus" => {
            let mut status = native(&platform, "calendarStatus", json!({})).await?;
            let store = state.store.lock().map_err(failure)?;
            let prefs: Value = store
                .setting("preferences")
                .map_err(failure)?
                .and_then(|s| serde_json::from_str(&s).ok())
                .unwrap_or(json!({}));
            status["calendar_id"] = prefs["calendar_id"].clone();
            status["display_calendar_ids"] = prefs["display_calendar_ids"].clone();
            status["pending_imports"] = json!(store.pending().map_err(failure)?.len());
            let pending: u32 = store
                .connection
                .query_row(
                    "SELECT count(*) FROM event_mutations WHERE status IN ('pending','uncertain')",
                    [],
                    |r| r.get(0),
                )
                .map_err(failure)?;
            status["pending_events"] = json!(pending);
            status["pending_bookkeeping"] =
                json!(crate::store::bookkeeping::pending_count(&store).map_err(failure)?);
            Ok(status)
        }
        "reconcileCalendarBookkeeping" => {
            let _guard = state.calendar_lock.lock().await;
            let store = state.store.lock().map_err(failure)?;
            crate::store::bookkeeping::recover(&store).map_err(|_| {
                super::ServiceError::Storage(crate::store::bookkeeping::WARNING.into())
            })?;
            Ok(
                json!({"pending_bookkeeping":crate::store::bookkeeping::pending_count(&store).map_err(failure)?}),
            )
        }
        "refreshAgenda" => {
            let _guard = state.calendar_lock.lock().await;
            super::agenda::sync(&platform, state).await
        }
        "appendPlanPages" => {
            let pages: Vec<String> =
                serde_json::from_value(args["pages"].clone()).map_err(failure)?;
            Ok(
                json!({"count": super::calendar::append_pages(state, required(&args, "id")?.into(), pages)?}),
            )
        }
        "agendaSelection" => serde_json::to_value(AgendaScope::current(state)?).map_err(failure),
        "queryCalendarEvents" => query(platform, state, args).await,
        "previewEventMutation" => preview(platform, state, args, None).await,
        "confirmProposal" => confirm(platform, state, args).await,
        "previewEventUndo" => undo(platform, state, args).await,
        "eventHistory" => Ok(
            json!({"history":state.store.lock().map_err(failure)?.event_history().map_err(failure)?}),
        ),
        "registerEventSession" => {
            let session = state.event_sessions.lock().map_err(failure)?.register()?;
            Ok(json!({"session":session}))
        }
        "invalidateEventSession" => {
            let session = required(&args, "session")?;
            let mut sessions = state.event_sessions.lock().map_err(failure)?;
            sessions.revoke(session);
            state
                .event_proposals
                .lock()
                .map_err(failure)?
                .retain(|_, p| p.session != session);
            Ok(json!({}))
        }
        "resolveEventUncertainty" => {
            let _guard = state.calendar_lock.lock().await;
            if args["confirmation"] != "button" {
                return Err("Kalenderprüfung ausdrücklich bestätigen.".into());
            }
            let id = required(&args, "id")?;
            let store = state.store.lock().map_err(failure)?;
            let history = store.event_history().map_err(failure)?;
            let item = history
                .iter()
                .find(|h| h["id"] == id)
                .ok_or("Verlaufseintrag fehlt.")?;
            if !matches!(item["status"].as_str(), Some("pending" | "uncertain")) {
                return Err("Nur unklare Vorgänge manuell abschließen.".into());
            }
            let result = json!({"status":"acknowledged","message":"Nach manueller Kalenderprüfung abgeschlossen. Kein erneuter Schreibversuch und kein App-Rückgängig."});
            store.finish_event_mutation(id, &result).map_err(failure)?;
            Ok(result)
        }
        "reconcileEventMutations" => {
            let _guard = state.calendar_lock.lock().await;
            let history = state
                .store
                .lock()
                .map_err(failure)?
                .event_history()
                .map_err(failure)?;
            for item in history.iter().filter(|h| {
                ["pending", "uncertain"].contains(&h["status"].as_str().unwrap_or_default())
            }) {
                let result = native(
                    &platform,
                    "mutateEvent",
                    json!({"proposal":item["proposal"],"recovery_only":true}),
                )
                .await?;
                state
                    .store
                    .lock()
                    .map_err(failure)?
                    .finish_event_mutation(required(item, "id")?, &result)
                    .map_err(failure)?;
            }
            let warnings = super::agenda::sync_warnings(&platform, state).await;
            Ok(json!({"maintenance_warnings":warnings}))
        }
        _ => Err("Unbekannte Kalenderfunktion.".into()),
    }
}
