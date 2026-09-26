import Foundation
import os

final class TestHost: AppleHost, Sendable {
  let failure = OSAllocatedUnfairLock<AppError?>(initialState: nil)
  let mutationOutcome = OSAllocatedUnfairLock<EventMutationStatus>(initialState: .failed)
  let mutationCalls = OSAllocatedUnfairLock<Int>(initialState: 0)
  let queries = OSAllocatedUnfairLock<[CalendarReadQuery]>(initialState: [])
  func calendarStatus() throws -> CalendarPlatformStatus {
    precondition(!Thread.isMainThread)
    if let error = failure.withLock({ $0 }) { throw error }
    return CalendarPlatformStatus(
      access: .fullAccess, lastReadAt: "2026-09-18T08:00:00Z",
      calendars: [CalendarStatusItem(id: "selected", title: "Therapie", writable: true)],
      unavailableCalendarIds: ["missing-calendar"])
  }
  func queryCalendar(request: CalendarReadQuery) throws -> CalendarReadResult {
    precondition(!Thread.isMainThread)
    queries.withLock { $0.append(request) }
    if let error = failure.withLock({ $0 }) { throw error }
    precondition(request.calendarIds == ["selected"] && request.timezone == "Europe/Vienna")
    precondition(request.selectionRevision > 0)
    let event = CalendarReadEvent(
      id: "stable-occurrence", externalId: "native",
      calendarId: "selected", calendarTitle: "Therapie", source: "Local",
      occurrence: "2026-09-18T08:00:00Z", recurring: true, systemOnly: true, writable: false,
      values: CalendarReadValues(
        title: "Termin", startUtc: "2026-09-18T08:00:00Z",
        endUtc: "2026-09-18T09:00:00Z", timezone: "Europe/Vienna", location: "Raum 2",
        reminderMinutes: nil),
      metadataJson: #"{"notes":"Unverändert","alarms":[{"absolute":null}],"future":[1,true,null]}"#,
      fingerprint: "original-fingerprint", importId: nil)
    return CalendarReadResult(
      events: [event], unavailableCalendarIds: ["selected"],
      unavailableEvents: [
        CalendarReadUnavailableEvent(
          id: "missing", startUtc: "2026-09-18T10:00:00Z", endUtc: "2026-09-18T11:00:00Z")
      ])
  }
  func resolveCalendarEvent(reference: CalendarReadReference) throws -> CalendarReadEvent? {
    if let error = failure.withLock({ $0 }) { throw error }
    return nil
  }
  func eventCalendars() throws -> [EventCalendarDestination] {
    if let error = failure.withLock({ $0 }) { throw error }
    return [
      EventCalendarDestination(
        id: "selected", title: "Therapie", source: "Local", writable: true, colorComponents: nil)
    ]
  }
  func mutateEvent(request: EventMutationRequest) throws -> EventMutationResult {
    if let error = failure.withLock({ $0 }) { throw error }
    precondition(!Thread.isMainThread)
    mutationCalls.withLock { $0 += 1 }
    return EventMutationResult(
      status: mutationOutcome.withLock { $0 }, event: nil, operationId: request.proposal.token,
      message: "Synthetic host does not write", maintenanceWarnings: [])
  }
  func calendarEventCall(command: String, arguments: String) throws -> String {
    precondition(
      !["queryEvents", "getEvent", "eventCalendars", "mutateEvent", "calendarStatus"].contains(
        command),
      "Typed effect used JSON callback")
    if let error = failure.withLock({ $0 }) { throw error }
    return "{}"
  }
  func overlaps(events: [String: EventValues], exclude: [String]) throws -> [CalendarOverlap] { [] }
  func snapshot(records: [ImportRecord]) throws -> LiveCalendar {
    precondition(!Thread.isMainThread)
    return LiveCalendar(current: [:], protectedIds: [])
  }
  func apply(operation: CalendarOperation, recoveryOnly: Bool) throws -> CalendarResult {
    precondition(!Thread.isMainThread)
    return CalendarResult(
      id: operation.id, status: recoveryOnly ? .saved : .uncertain,
      externalId: recoveryOnly ? "synthetic-external" : nil, error: nil,
      maintenanceWarnings: recoveryOnly ? ["Erfundener Wartungshinweis"] : [])
  }
  func decodePhoto(bytes: Data) throws -> Data { bytes }
  func syncAgenda(records: [ImportRecord], preferences: Preferences) throws {
    precondition(!Thread.isMainThread)
  }
  func forgetCalendar() throws {}
}
@main struct BindingProbe {
  static func main() async throws {
    precondition(
      normalizeSpeech(text: "Frühstück II beginnt um 09:15 Uhr in Raum 105.")
        == "Frühstück zwei beginnt um neun Uhr fünfzehn in Raum einhundertfünf.")
    let root = CommandLine.arguments[1]
    let draftRoot = root + "-draft"
    try FileManager.default.copyItem(atPath: root, toPath: draftRoot)
    let host = TestHost()
    let core = try await openApplication(root: root, models: "/unavailable-test-model", host: host)
    let nativeFailures: [AppError] = [
      .Validation(message: "Kalenderzugriff fehlt."),
      .Storage(message: "Vorschau abgelaufen; läuft bereits"),
      .PermissionDenied, .Timeout(operation: "queryEvents"), .UncertainWrite,
      .ExpiredScan, .StaleRevision, .StaleProposal, .Busy, .Cancelled,
    ]
    for expected in nativeFailures {
      host.failure.withLock { $0 = expected }
      do {
        _ = try await core.calendarRequest(command: "calendarStatus", arguments: "{}")
        preconditionFailure("Native failure disappeared")
      } catch {
        precondition(error as? AppError == expected, "Native failure identity changed: \(error)")
      }
      do {
        _ = try await core.calendarStatus()
        preconditionFailure("Typed status failure disappeared")
      } catch { precondition(error as? AppError == expected) }
    }
    host.failure.withLock { $0 = nil }
    var preferences = try await core.preferences()
    preferences.appearance = "dark"
    preferences.reminderSound = false
    preferences.reminderPreview = true
    let savedPreferences = try await core.savePreferences(value: preferences)
    precondition(savedPreferences == preferences)
    host.failure.withLock { $0 = .PermissionDenied }
    preferences.displayCalendarIds = ["selected"]
    let withMaintenanceFailure = try await core.savePreferencesDetailed(value: preferences)
    precondition(withMaintenanceFailure.preferences == preferences)
    precondition(withMaintenanceFailure.maintenanceWarnings.count == 1)
    host.failure.withLock { $0 = nil }
    let preferencesReopened = try await openApplication(
      root: root, models: "/unavailable-test-model", host: host)
    let restoredPreferences = try await preferencesReopened.preferences()
    precondition(restoredPreferences == preferences)
    let queryArguments = #"{"start_utc":"2026-09-18T00:00:00Z","end_utc":"2026-09-19T00:00:00Z"}"#
    let query = try await core.calendarRequest(
      command: "queryCalendarEvents", arguments: queryArguments)
    let response = try JSONSerialization.jsonObject(with: Data(query.utf8)) as! [String: Any]
    let event = (response["events"] as! [[String: Any]])[0]
    precondition(event["id"] as? String == "stable-occurrence" && event["import_id"] == nil)
    precondition(event["fingerprint"] as? String == "original-fingerprint")
    precondition((event["metadata"] as? [String: Any])?["notes"] as? String == "Unverändert")
    precondition(
      (response["unavailable_events"] as? [[String: Any]])?.first?["id"] as? String == "missing")
    let scope = try await core.agendaSelection()
    let legacyScopeText = try await core.calendarRequest(
      command: "agendaSelection", arguments: "{}")
    let legacyScope =
      try JSONSerialization.jsonObject(with: Data(legacyScopeText.utf8)) as! [String: Any]
    precondition(scope.calendarIds == ["selected"] && scope.timezone == preferences.timezone)
    precondition(scope.revision == (legacyScope["revision"] as! NSNumber).uint64Value)
    let typedRequest = AgendaQueryRequest(
      startUtc: "2026-09-18T00:00:00Z", endUtc: "2026-09-19T00:00:00Z", expectedScope: scope)
    let typedQuery = try await core.queryCalendarEvents(request: typedRequest)
    precondition(typedQuery.scope == scope)
    precondition(
      typedQuery.startUtc == typedRequest.startUtc && typedQuery.endUtc == typedRequest.endUtc)
    let typedEvent = typedQuery.events[0]
    precondition(typedEvent.id == event["id"] as? String && typedEvent.importId == nil)
    precondition(typedEvent.fingerprint == event["fingerprint"] as? String)
    let typedMetadata =
      try JSONSerialization.jsonObject(with: Data(typedEvent.metadataJson.utf8)) as! NSDictionary
    precondition(typedMetadata == event["metadata"] as! NSDictionary)
    precondition(typedQuery.unavailableCalendarIds == ["selected"])
    precondition(typedQuery.unavailableEvents.first?.id == "missing")
    precondition(host.queries.withLock { $0.last?.selectionRevision } == scope.revision)
    let status = try await core.calendarStatus()
    let legacyStatusText = try await core.calendarRequest(
      command: "calendarStatus", arguments: "{}")
    let legacyStatus =
      try JSONSerialization.jsonObject(with: Data(legacyStatusText.utf8)) as! [String: Any]
    precondition(status.platform.access == .fullAccess)
    precondition(status.platform.lastReadAt == legacyStatus["last_read_at"] as? String)
    precondition(status.platform.unavailableCalendarIds == ["missing-calendar"])
    precondition(status.displayCalendarIds == preferences.displayCalendarIds)
    precondition(status.pendingEvents == (legacyStatus["pending_events"] as! NSNumber).uint32Value)
    let bookkeeping = try await core.reconcileCalendarBookkeeping()
    precondition(bookkeeping.pendingBookkeeping == 0)
    let queryCount = host.queries.withLock { $0.count }
    var staleRequest = typedRequest
    staleRequest.expectedScope?.revision += 2
    do {
      _ = try await core.queryCalendarEvents(request: staleRequest)
      preconditionFailure("Obsolete scope reached the native callback")
    } catch { precondition(error as? AppError == .StaleRevision) }
    var emptyPreferences = preferences
    emptyPreferences.displayCalendarIds = []
    _ = try await core.savePreferencesDetailed(value: emptyPreferences)
    let emptyQuery = try await core.queryCalendarEvents(
      request: AgendaQueryRequest(
        startUtc: typedRequest.startUtc, endUtc: typedRequest.endUtc, expectedScope: nil))
    precondition(emptyQuery.scope.calendarIds.isEmpty && emptyQuery.events.isEmpty)
    precondition(emptyQuery.unavailableCalendarIds.isEmpty && emptyQuery.unavailableEvents.isEmpty)
    precondition(host.queries.withLock { $0.count } == queryCount)
    _ = try await core.savePreferencesDetailed(value: preferences)
    do {
      _ = try await core.queryCalendarEvents(request: typedRequest)
      preconditionFailure("A -> B -> A accepted an obsolete selection revision")
    } catch { precondition(error as? AppError == .StaleRevision) }
    let currentScope = try await core.agendaSelection()
    let currentRequest = AgendaQueryRequest(
      startUtc: typedRequest.startUtc, endUtc: typedRequest.endUtc, expectedScope: currentScope)
    for expected in nativeFailures {
      host.failure.withLock { $0 = expected }
      do {
        _ = try await core.calendarRequest(
          command: "queryCalendarEvents", arguments: queryArguments)
        preconditionFailure("Typed read failure disappeared")
      } catch { precondition(error as? AppError == expected) }
      do {
        _ = try await core.queryCalendarEvents(request: currentRequest)
        preconditionFailure("Typed application read failure disappeared")
      } catch { precondition(error as? AppError == expected) }
    }
    host.failure.withLock { $0 = nil }
    do {
      let destinations = try await core.eventCalendars()
      precondition(destinations.count == 1 && destinations[0].id == "selected")
      let editSession = try core.registerEventSession()
      let preview = try await core.previewEventMutation(
        request: EventPreviewRequest(
          session: editSession, revision: 7, kind: .create, calendarId: "selected", event: nil,
          patch: EventEditPatch(
            title: "Typed preview", startUtc: "2031-05-15T08:00:00Z",
            endUtc: "2031-05-15T09:00:00Z", timezone: "Europe/Vienna", location: "Room",
            reminder: .disabled), origin: "manual"))
      guard case .proposal(let proposal) = preview else { preconditionFailure("Expected proposal") }
      precondition(proposal.patch.reminder == .disabled && proposal.revision == 7)
      let confirmation = EventConfirmRequest(
        token: proposal.token, session: editSession,
        revision: 7, confirmation: .button)
      let mutation = try await core.confirmEventProposal(request: confirmation)
      precondition(mutation.status == .failed && mutation.operationId == proposal.token)
      try core.invalidateEventSession(session: editSession)
      let replay = try await core.confirmEventProposal(request: confirmation)
      precondition(replay == mutation)
      let detail = try await core.eventHistoryDetail(id: proposal.token)
      precondition(detail?.status == .failed && detail?.proposal.token == proposal.token)
      precondition(detail?.result?.status == .failed && detail?.undoneBy == nil)
      let legacyDetailText = try await core.calendarRequest(
        command: "activityDetail", arguments: #"{"id":"event:\#(proposal.token)"}"#)
      let legacyDetail =
        try JSONSerialization.jsonObject(with: Data(legacyDetailText.utf8)) as! [String: Any]
      precondition(legacyDetail["id"] as? String == detail?.id)
      let missingDetail = try await core.eventHistoryDetail(id: "missing-event")
      precondition(missingDetail == nil)
      let recovery = try await core.reconcileEventMutations()
      precondition(recovery.maintenanceWarnings.isEmpty)
      let uncertainSession = try core.registerEventSession()
      host.mutationOutcome.withLock { $0 = .uncertain }
      let uncertainPreview = try await core.previewEventMutation(
        request: EventPreviewRequest(
          session: uncertainSession, revision: 8, kind: .create, calendarId: "selected", event: nil,
          patch: EventEditPatch(
            title: "Uncertain", startUtc: "2031-05-15T10:00:00Z",
            endUtc: "2031-05-15T11:00:00Z", timezone: "Europe/Vienna", location: "Room",
            reminder: .disabled),
          origin: "manual"))
      guard case .proposal(let pending) = uncertainPreview else {
        preconditionFailure("Expected uncertain proposal")
      }
      let uncertain = try await core.confirmEventProposal(
        request: EventConfirmRequest(
          token: pending.token, session: uncertainSession, revision: 8, confirmation: .button))
      precondition(uncertain.status == .uncertain)
      let writesBeforeAck = host.mutationCalls.withLock { $0 }
      do {
        _ = try await core.calendarRequest(
          command: "resolveEventUncertainty",
          arguments: #"{"id":"\#(pending.token)","confirmation":"spoken"}"#)
        preconditionFailure("Spoken manual acknowledgement was accepted")
      } catch { guard let app = error as? AppError, case .Validation = app else { throw error } }
      let acknowledged = try await core.resolveEventUncertainty(
        request: ResolveEventUncertaintyRequest(
          id: pending.token, confirmation: .button))
      precondition(acknowledged.status == .acknowledged && acknowledged.event == nil)
      let acknowledgedDetail = try await core.eventHistoryDetail(id: pending.token)
      precondition(acknowledgedDetail?.status == .acknowledged)
      precondition(acknowledgedDetail?.result?.status == .acknowledged)
      let fullHistory = try await core.eventHistory()
      precondition(fullHistory.contains { $0.id == pending.token && $0.status == .acknowledged })
      _ = try await core.reconcileEventMutations()
      precondition(host.mutationCalls.withLock { $0 } == writesBeforeAck)
      do {
        _ = try await core.resolveEventUncertainty(
          request: ResolveEventUncertaintyRequest(
            id: pending.token, confirmation: .button))
        preconditionFailure("Already acknowledged operation was acknowledged twice")
      } catch { guard let app = error as? AppError, case .Validation = app else { throw error } }
      host.mutationOutcome.withLock { $0 = .failed }
      try core.invalidateEventSession(session: uncertainSession)

    }
    let history = try await core.history()
    precondition(history.scans.count == 1)
    let id = history.scans[0].id
    let archive = try await core.archivePage(after: nil, limit: 1)
    precondition(archive.plans.count == 1 && archive.plans[0].id == id && archive.next == nil)
    precondition(archive.plans[0].status == .readyForReview)
    precondition(archive.plans[0].itemCount == history.scans[0].itemCount)
    let initial = try await core.loadScan(id: id)
    precondition(!initial.appointments[0].id.isEmpty)
    var edited = initial.appointments
    edited[0].title = "Swift 6 Integration"
    edited[0].durationMinutes = 30
    edited[0].end = nil
    edited[0] = try confirmAppointmentFields(appointment: edited[0])
    let saved = try await core.saveReview(
      id: id, revision: initial.revision, appointments: edited, complete: false,
      selection: [edited[0].id])
    precondition(saved.appointments[0].approval != nil)
    precondition(saved.appointments[0].rowPolygon == initial.appointments[0].rowPolygon)
    do {
      _ = try await core.saveReview(
        id: id, revision: initial.revision, appointments: initial.appointments, complete: true,
        selection: [])
      fatalError("Stale save accepted")
    } catch AppError.StaleRevision {}
    let ics = try await core.exportIcs(
      id: id, timezone: saved.timezone, reminder: 10, selection: [edited[0].id])
    precondition(ics.contains("BEGIN:VCALENDAR") && ics.contains("Swift 6 Integration"))
    let again = try await core.exportIcs(
      id: id, timezone: saved.timezone, reminder: 10, selection: [edited[0].id])
    precondition(
      ics.components(separatedBy: "\n").filter { $0.hasPrefix("UID:") }
        == again.components(separatedBy: "\n").filter { $0.hasPrefix("UID:") })
    let proposal = try await core.prepareCalendar(
      id: id, calendarId: "synthetic", timezone: saved.timezone, reminder: 10,
      selection: [edited[0].id], replacement: false)
    precondition(proposal.operations.first?.kind == .create)
    let results = try await core.approveCalendar(token: proposal.token, approveRemovals: false)
    precondition(results.first?.status == .uncertain)
    let uncertainArchive = try await core.archivePage(after: nil, limit: 20)
    precondition(uncertainArchive.plans[0].status == .reconciliationNeeded)
    do {
      _ = try await core.prepareCalendar(
        id: id, calendarId: "synthetic", timezone: saved.timezone, reminder: 10,
        selection: [edited[0].id], replacement: false)
      fatalError("Uncertain write allowed a blind retry")
    } catch AppError.UncertainWrite {}
    let recovered = try await core.reconcileCalendar()
    precondition(recovered.first?.status == .saved)
    precondition(recovered.first?.maintenanceWarnings == ["Erfundener Wartungshinweis"])
    let reopened = try await openApplication(
      root: root, models: "/unavailable-test-model", host: host)
    let retained = try await reopened.history()
    precondition(
      retained.pending.isEmpty && retained.imports.first?.externalId == "synthetic-external")
    let jobID = UUID().uuidString
    let job = try core.registerJob(id: jobID)
    try core.cancelJob(id: job.attemptId())
    do {
      _ = try await core.importPhoto(
        request: PhotoRequest(
          id: jobID, path: "/unavailable-test-photo", timezone: "Europe/Vienna", quarterTurns: 0,
          mirrored: false, pageCorners: [], force: false), job: job)
      fatalError("Cancellation before import start was lost")
    } catch AppError.Cancelled {}
    precondition(!core.recognitionBusy())
    let retry = try core.registerJob(id: jobID)
    precondition(retry.attemptId() != job.attemptId())
    job.cancel()
    job.close()
    try core.cancelJob(id: job.attemptId())
    try core.cancelJob(id: UUID().uuidString)
    do {
      _ = try await core.importPhoto(
        request: PhotoRequest(
          id: jobID, path: "/unavailable-test-photo", timezone: "Europe/Vienna", quarterTurns: 0,
          mirrored: false, pageCorners: [], force: false), job: retry)
      fatalError("Missing photo was accepted")
    } catch AppError.Storage {}
    retry.close()
    let unused = try core.registerJob(id: jobID)
    unused.close()
    let retryBeforeStart = try core.registerJob(id: jobID)
    retryBeforeStart.cancel()
    do {
      _ = try await core.retryCapture(id: jobID, job: retryBeforeStart)
      fatalError("Cancellation before retry start was lost")
    } catch AppError.Cancelled {}
    retryBeforeStart.close()
    do {
      _ = try await core.artifactPath(id: id, artifact: "../../ledger.sqlite")
      fatalError("Traversal accepted")
    } catch AppError.Validation {}
    let draftCore = try await openApplication(
      root: draftRoot, models: "/unavailable-test-model", host: host)
    let beforeDraft = try await draftCore.loadScan(id: id)
    let preview = try await draftCore.previewDraft(
      id: id, calendarId: "synthetic", timezone: beforeDraft.timezone, reminder: nil)
    precondition(preview.assessment.policyVersion == 1 && !preview.assessment.readyIds.isEmpty)
    precondition(!preview.assessment.questions.isEmpty)
    let afterPreview = try await draftCore.loadScan(id: id)
    precondition(beforeDraft.revision == afterPreview.revision)
    precondition(afterPreview.appointments.allSatisfy { $0.approval == nil })
    let accepted = try await draftCore.acceptAndSave(
      token: preview.proposal!.token, selection: preview.assessment.readyIds, approveRemovals: false
    )
    precondition(accepted.results.allSatisfy { $0.status == .uncertain })
    precondition(accepted.existingIds.isEmpty && !accepted.remainingIds.isEmpty)
    let afterAccept = try await draftCore.loadScan(id: id)
    precondition(
      afterAccept.appointments.allSatisfy { $0.approval == nil && $0.calendarSavedHash == nil })
    for (before, after) in zip(beforeDraft.appointments, afterAccept.appointments) {
      precondition(before.fields == after.fields)
    }
    print(
      "Swift 6 integration passed: typed appointments/geometry, revisions, approvals, stable ICS, uncertain-write recovery, reopen, cancellation and artifact confinement"
    )
  }
}
