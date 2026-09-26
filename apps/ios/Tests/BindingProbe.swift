import Foundation
import os

final class TestHost: AppleHost, Sendable {
  let failure = OSAllocatedUnfairLock<AppError?>(initialState: nil)
  let mutationOutcome = OSAllocatedUnfairLock<EventMutationStatus>(initialState: .failed)
  let mutationCalls = OSAllocatedUnfairLock<Int>(initialState: 0)
  let queries = OSAllocatedUnfairLock<[CalendarReadQuery]>(initialState: [])
  let agendaRequests = OSAllocatedUnfairLock<[AgendaSyncRequest]>(initialState: [])
  let agendaWarnings = OSAllocatedUnfairLock<[String]>(initialState: [])
  let linkRecords = OSAllocatedUnfairLock<[[AgendaOwnedRecord]]>(initialState: [])
  let ownedRecords = OSAllocatedUnfairLock<[AgendaOwnedRecord]>(initialState: [])
  let ownedResolution = OSAllocatedUnfairLock<OwnedEventResolution>(initialState: .unavailable)
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
      ![
        "queryEvents", "getEvent", "eventCalendars", "mutateEvent", "calendarStatus", "agenda",
        "inspectCalendarLinks", "resolveOwnedEvent",
      ]
      .contains(
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
  func inspectCalendarLinks(records: [AgendaOwnedRecord]) throws -> CalendarLinkInspection {
    precondition(!Thread.isMainThread)
    linkRecords.withLock { $0.append(records) }
    if let error = failure.withLock({ $0 }) { throw error }
    return CalendarLinkInspection(
      calendarIds: ["selected"],
      results: records.map {
        CalendarLinkResult(id: $0.id, state: .unavailable(reason: "calendar_missing"))
      })
  }
  func resolveOwnedEvent(record: AgendaOwnedRecord) throws -> OwnedEventResolution {
    precondition(!Thread.isMainThread)
    ownedRecords.withLock { $0.append(record) }
    if let error = failure.withLock({ $0 }) { throw error }
    return ownedResolution.withLock { $0 }
  }
  func syncAgenda(request: AgendaSyncRequest) throws -> AgendaSyncResult {
    precondition(!Thread.isMainThread)
    agendaRequests.withLock { $0.append(request) }
    if let error = failure.withLock({ $0 }) { throw error }
    return AgendaSyncResult(maintenanceWarnings: agendaWarnings.withLock { $0 })
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
    let pagesRoot = root + "-pages"
    try FileManager.default.copyItem(atPath: root, toPath: pagesRoot)
    let activityRoot = root + "-activity"
    try FileManager.default.copyItem(atPath: root, toPath: activityRoot)
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
      do {
        _ = try await core.refreshAgenda()
        preconditionFailure("Typed agenda failure disappeared")
      } catch { precondition(error as? AppError == expected) }
      do {
        _ = try await core.calendarRequest(command: "inspectCalendarRepair", arguments: "{}")
        preconditionFailure("Typed ownership inspection failure disappeared")
      } catch { precondition(error as? AppError == expected) }
      do {
        _ = try await core.inspectCalendarRepair()
        preconditionFailure("Typed repair request failure disappeared")
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
    host.agendaWarnings.withLock { $0 = ["Alarmjournal ausstehend", "Widget ausstehend"] }
    let refreshed = try await core.refreshAgenda()
    precondition(refreshed.maintenanceWarnings == ["Alarmjournal ausstehend", "Widget ausstehend"])
    let agendaRequest = host.agendaRequests.withLock { $0.last! }
    precondition(agendaRequest.displayCalendarIds == preferences.displayCalendarIds)
    precondition(agendaRequest.preferences.enabled == preferences.appRemindersEnabled)
    precondition(agendaRequest.preferences.minutes == preferences.appReminderMinutes)
    precondition(agendaRequest.preferences.sound == preferences.reminderSound)
    precondition(agendaRequest.preferences.preview == preferences.reminderPreview)
    host.agendaWarnings.withLock { $0 = [] }
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
    precondition(host.agendaRequests.withLock { $0.last!.displayCalendarIds.isEmpty })
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
    let imported = retained.imports.first!
    let transferred = host.agendaRequests.withLock { requests in
      requests.flatMap(\.records).last {
        $0.id == imported.id && $0.externalId == imported.externalId
      }
    }
    precondition(
      transferred != nil, "Confirmed hidden import did not reach typed agenda maintenance")
    precondition(transferred?.calendarId == imported.calendarId)
    precondition(transferred?.approved == imported.approved)
    precondition(transferred?.origin == "import" && transferred?.importId == imported.id)
    precondition(transferred?.operationId == imported.operationId)
    let liveEvent = CalendarReadEvent(
      id: "moved-occurrence", externalId: "repaired-external", calendarId: "hidden-moved",
      calendarTitle: "Erfundener Kalender", source: "Local", occurrence: imported.approved.startUtc,
      recurring: false, systemOnly: false, writable: true,
      values: CalendarReadValues(
        title: "Aktueller Titel", startUtc: imported.approved.startUtc,
        endUtc: imported.approved.endUtc, timezone: imported.approved.timezone,
        location: "Raum 3", reminderMinutes: nil),
      metadataJson: #"{"notes":"Unverändert","alarms":[{"relative":-600}],"future":[true,null]}"#,
      fingerprint: "existing-fingerprint", importId: imported.id)
    for expected: OwnedEventResolution in [.found(event: liveEvent), .deleted, .unavailable] {
      host.ownedResolution.withLock { $0 = expected }
      let actual = try await reopened.resolveOwnedEvent(id: imported.id)
      if case .found(var received) = actual, case .found(let supplied) = expected {
        let actualMetadata = try JSONSerialization.jsonObject(
          with: Data(received.metadataJson.utf8))
        let expectedMetadata = try JSONSerialization.jsonObject(
          with: Data(supplied.metadataJson.utf8))
        precondition(
          NSDictionary(dictionary: actualMetadata as! [String: Any]).isEqual(
            to: expectedMetadata as! [String: Any]))
        received.metadataJson = supplied.metadataJson
        precondition(received == supplied)
      } else {
        precondition(actual == expected)
      }
      let legacyText = try await reopened.calendarRequest(
        command: "resolveOwnedEvent", arguments: #"{"id":"\#(imported.id)"}"#)
      let legacy = try JSONSerialization.jsonObject(with: Data(legacyText.utf8)) as! [String: Any]
      switch expected {
      case .found:
        precondition(legacy["status"] as? String == "found")
        let event = legacy["event"] as! [String: Any]
        precondition(event["import_id"] as? String == imported.id)
        precondition(event["external_id"] as? String == liveEvent.externalId)
      case .deleted: precondition(legacy["status"] as? String == "deleted")
      case .unavailable: precondition(legacy["status"] as? String == "unavailable")
      case .missing: preconditionFailure("Unexpected fixture")
      }
    }
    precondition(host.ownedRecords.withLock { $0.allSatisfy { $0 == transferred } })
    for expected in nativeFailures {
      host.failure.withLock { $0 = expected }
      do {
        _ = try await reopened.resolveOwnedEvent(id: imported.id)
        preconditionFailure("Owned lookup failure disappeared")
      } catch { precondition(error as? AppError == expected) }
    }
    host.failure.withLock { $0 = nil }
    let missingLink = try await reopened.resolveOwnedEvent(id: UUID().uuidString)
    precondition(missingLink == .missing)
    do {
      _ = try await reopened.resolveOwnedEvent(id: "invalid")
      preconditionFailure("Invalid link accepted")
    } catch AppError.Validation {}
    let lookupHistory = try await reopened.history()
    precondition(lookupHistory.imports == retained.imports)
    let linkReport = try await reopened.calendarRequest(
      command: "inspectCalendarRepair", arguments: "{}")
    let inspectedRecords = host.linkRecords.withLock { $0.last! }
    precondition(inspectedRecords.first { $0.id == imported.id } == transferred)
    let linkResponse =
      try JSONSerialization.jsonObject(with: Data(linkReport.utf8)) as! [String: Any]
    let linkIssues = linkResponse["issues"] as! [[String: Any]]
    let linkIssue = linkIssues.first { $0["id"] as? String == imported.id }!
    precondition(linkIssue["reason"] as? String == "calendar_missing")
    precondition(linkIssue["title"] as? String == imported.approved.title)
    precondition(linkResponse["removed_count"] as? Int == 0)
    let typedLinks = try await reopened.inspectCalendarRepair()
    let typedIssue = typedLinks.issues.first { $0.id == imported.id }!
    precondition(typedIssue.fingerprint == linkIssue["fingerprint"] as? String)
    precondition(typedIssue.calendarId == imported.calendarId)
    precondition(typedIssue.title == imported.approved.title)
    precondition(typedIssue.startUtc == imported.approved.startUtc)
    precondition(typedIssue.endUtc == imported.approved.endUtc)
    precondition(typedIssue.timezone == imported.approved.timezone)
    precondition(typedIssue.reason == linkIssue["reason"] as? String)
    precondition(typedLinks.missingCalendarIds == linkResponse["missing_calendar_ids"] as? [String])
    precondition(typedLinks.removedCount == 0 && !typedLinks.cleanupBlocked)
    do {
      _ = try await reopened.confirmCalendarRepair(selection: [], confirmation: .button)
      preconditionFailure("Empty selection was accepted")
    } catch AppError.Validation {}
    host.agendaWarnings.withLock { $0 = ["Reminder unavailable", "Widget unavailable"] }
    let selectedLink = CalendarRepairSelection(
      id: typedIssue.id, fingerprint: typedIssue.fingerprint)
    let detached = try await reopened.confirmCalendarRepair(
      selection: [selectedLink], confirmation: .button)
    precondition(detached.removedCount == 1)
    precondition(detached.refreshWarning == "Reminder unavailable\n\nWidget unavailable")
    host.agendaWarnings.withLock { $0 = [] }
    let repairedReopen = try await openApplication(
      root: root, models: "/unavailable-test-model", host: host)
    let retainedAfterRepair = try await repairedReopen.history()
    precondition(retainedAfterRepair.imports == retained.imports)
    let afterRepair = try await repairedReopen.inspectCalendarRepair()
    precondition(afterRepair.issues.isEmpty)
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
    let pagesCore = try await openApplication(
      root: pagesRoot, models: "/unavailable-test-model", host: host)
    let initialPage = try await pagesCore.loadScan(id: id)
    let source = try await pagesCore.artifactPath(id: id, artifact: "source.bin")
    let firstPage = UUID().uuidString
    let secondPage = UUID().uuidString
    _ = try await pagesCore.stagePhoto(id: firstPage, path: source)
    _ = try await pagesCore.stagePhoto(id: secondPage, path: source)
    let firstCount = try await pagesCore.appendPages(id: id, pages: [firstPage, firstPage])
    precondition(firstCount == 2)
    let secondCount = try await pagesCore.appendPages(
      id: firstPage, pages: [secondPage, firstPage])
    precondition(secondCount == 3)
    let expectedPages = [id, firstPage, secondPage]
    let grouped = try await pagesCore.pageGroup(id: secondPage)
    precondition(grouped == expectedPages)
    let legacyCountText = try await pagesCore.calendarRequest(
      command: "appendPlanPages",
      arguments: String(
        data: JSONSerialization.data(withJSONObject: ["id": id, "pages": []]),
        encoding: .utf8)!)
    let legacyCount =
      try JSONSerialization.jsonObject(with: Data(legacyCountText.utf8)) as! [String: Int]
    precondition(legacyCount["count"] == 3)
    do {
      _ = try await pagesCore.appendPages(id: "", pages: [secondPage])
      preconditionFailure("Missing parent accepted")
    } catch AppError.Validation {}
    do {
      _ = try await pagesCore.appendPages(id: id, pages: [UUID().uuidString])
      preconditionFailure("Missing source accepted")
    } catch AppError.Validation {}
    let pagesReopened = try await openApplication(
      root: pagesRoot, models: "/unavailable-test-model", host: host)
    let reopenedPages = try await pagesReopened.pageGroup(id: id)
    let unchangedPage = try await pagesReopened.loadScan(id: id)
    precondition(reopenedPages == expectedPages)
    precondition(unchangedPage.revision == initialPage.revision)
    precondition(unchangedPage.appointments == initialPage.appointments)
    try await verifyActivity(core: core, activityRoot: activityRoot, host: host)
    print(
      "Swift 6 integration passed: typed appointments/geometry, revisions, approvals, stable ICS, uncertain-write recovery, reopen, cancellation and artifact confinement"
    )
  }
  static func verifyActivity(core: NativeApplication, activityRoot: String, host: TestHost)
    async throws
  {
    for (source, stored) in [(ActivitySource.calendarImport, "import"), (.eventMutation, "event")] {
      let page = try await core.activityPage(cursor: nil, limit: 100, source: source)
      precondition(!page.items.isEmpty && page.items.allSatisfy { $0.source == source })
      let legacyText = try await core.calendarRequest(
        command: "activityPage", arguments: #"{"limit":100,"source":"\#(stored)"}"#)
      let legacy = try JSONSerialization.jsonObject(with: Data(legacyText.utf8)) as! [String: Any]
      let rows = legacy["items"] as! [[String: Any]]
      precondition(rows.count == page.items.count)
      for (row, typed) in zip(rows, page.items) {
        precondition(row["id"] as? String == typed.id)
        precondition((row["created_at"] as? NSNumber)?.int64Value == typed.createdAt)
        precondition(row["source"] as? String == stored)
        precondition(row["source_id"] as? String == typed.sourceId)
        precondition(row["document_id"] as? String == typed.documentId)
        precondition(
          row["kind"] as? String == typed.kind && row["status"] as? String == typed.status)
        precondition((row["count"] as? NSNumber)?.uint32Value == typed.count)
      }
      precondition(legacy["next_cursor"] as? String == page.nextCursor)
    }
    let activity = try await openApplication(
      root: activityRoot, models: "/unavailable-test-model", host: host)
    let source = activityRoot + "/synthetic-invalid-photo.bin"
    let bytes = Data("synthetic invalid image".utf8)
    try bytes.write(to: URL(fileURLWithPath: source))
    let document = UUID().uuidString
    _ = try await activity.stagePhoto(id: document, path: source)
    for _ in 0..<2 {
      let job = try activity.registerJob(id: document)
      do {
        _ = try await activity.retryCapture(id: document, job: job)
        preconditionFailure("Invalid image unexpectedly recognized")
      } catch AppError.Validation {} catch AppError.Storage {}
      job.close()
    }
    let all = try await activity.activityPage(cursor: nil, limit: nil, source: nil)
    precondition(all.items.count == 3)
    precondition(all.items.filter { $0.source == .capture }.count == 1)
    let recognition = try await activity.activityPage(cursor: nil, limit: nil, source: .recognition)
    precondition(recognition.items.count == 2)
    var details: [RecognitionActivityDetail] = []
    for row in recognition.items {
      precondition(row.status == "failed" && row.documentId == document)
      let detail = try await activity.recognitionActivityDetail(id: row.sourceId)
      precondition(detail.documentId == document && detail.status == "failed")
      precondition(detail.error?.isEmpty == false)
      let legacyText = try await activity.calendarRequest(
        command: "activityDetail", arguments: #"{"id":"\#(row.id)"}"#)
      let legacy = try JSONSerialization.jsonObject(with: Data(legacyText.utf8)) as! [String: Any]
      precondition(legacy["document_id"] as? String == detail.documentId)
      precondition(legacy["status"] as? String == detail.status)
      precondition(legacy["error"] as? String == detail.error)
      details.append(detail)
    }
    var cursor: String?
    var ids: [String] = []
    repeat {
      let page = try await activity.activityPage(cursor: cursor, limit: 1, source: nil)
      precondition(page.items.count == 1)
      ids += page.items.map(\.id)
      cursor = page.nextCursor
    } while cursor != nil
    precondition(ids == all.items.map(\.id) && Set(ids).count == 3)
    for invalid in ["bad cursor", String(repeating: "x", count: 513)] {
      do {
        _ = try await activity.activityPage(cursor: invalid, limit: nil, source: nil)
        preconditionFailure("Invalid activity cursor accepted")
      } catch AppError.Validation {}
    }
    do {
      _ = try await activity.recognitionActivityDetail(id: document)
      preconditionFailure("Document ID confused with processing attempt ID")
    } catch AppError.Storage {}
    let reopened = try await openApplication(
      root: activityRoot, models: "/unavailable-test-model", host: host)
    let reopenedPage = try await reopened.activityPage(cursor: nil, limit: nil, source: nil)
    precondition(reopenedPage == all)
    for (row, detail) in zip(recognition.items, details) {
      let restored = try await reopened.recognitionActivityDetail(id: row.sourceId)
      precondition(restored == detail)
    }
    let retainedSource = try await reopened.artifactPath(id: document, artifact: "source.bin")
    let retainedBytes = try Data(contentsOf: URL(fileURLWithPath: retainedSource))
    precondition(retainedBytes == bytes)
  }

}
