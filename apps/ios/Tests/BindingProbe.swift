import Foundation
import os

final class TestHost: AppleHost, Sendable {
  let failure = OSAllocatedUnfairLock<AppError?>(initialState: nil)
  func queryCalendar(request: CalendarReadQuery) throws -> CalendarReadResult {
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
  func calendarEventCall(command: String, arguments: String) throws -> String {
    precondition(command != "queryEvents" && command != "getEvent", "Read used JSON callback")
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
    for expected in nativeFailures {
      host.failure.withLock { $0 = expected }
      do {
        _ = try await core.calendarRequest(
          command: "queryCalendarEvents", arguments: queryArguments)
        preconditionFailure("Typed read failure disappeared")
      } catch { precondition(error as? AppError == expected) }
    }
    host.failure.withLock { $0 = nil }
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
    let job = UUID().uuidString
    try core.cancelJob(id: job)
    do {
      _ = try await core.importPhoto(
        request: PhotoRequest(
          id: job, path: "/unavailable-test-photo", timezone: "Europe/Vienna", quarterTurns: 0,
          mirrored: false, pageCorners: [], force: false))
      fatalError("Cancellation before job registration was lost")
    } catch AppError.Cancelled {}
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
