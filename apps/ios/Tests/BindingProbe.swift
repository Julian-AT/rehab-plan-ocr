import Foundation

final class TestHost: AppleHost, @unchecked Sendable {
  func calendarEventCall(command: String, arguments: String) throws -> String { "{}" }
  func overlaps(events: [String: EventValues], exclude: [String]) throws -> [CalendarOverlap] { [] }
  func snapshot(records: [ImportRecord]) throws -> LiveCalendar {
    precondition(!Thread.isMainThread)
    return LiveCalendar(current: [:], protectedIds: [])
  }
  func apply(operation: CalendarOperation, recoveryOnly: Bool) throws -> CalendarResult {
    precondition(!Thread.isMainThread)
    return CalendarResult(
      id: operation.id, status: recoveryOnly ? .saved : .uncertain,
      externalId: recoveryOnly ? "synthetic-external" : nil, error: nil)
  }
  func decodePhoto(bytes: Data) throws -> Data { bytes }
  func syncAgenda(records: [ImportRecord], preferences: Preferences) throws {
    precondition(!Thread.isMainThread)
  }
  func forgetCalendar() throws {}
}
@main struct BindingProbe {
  static func main() async throws {
    let root = CommandLine.arguments[1]
    let draftRoot = root + "-draft"
    try FileManager.default.copyItem(atPath: root, toPath: draftRoot)
    let host = TestHost()
    let core = try await openApplication(root: root, models: "/unavailable-test-model", host: host)
    var preferences = try await core.preferences()
    preferences.appearance = "dark"
    preferences.reminderSound = false
    preferences.reminderPreview = true
    let savedPreferences = try await core.savePreferences(value: preferences)
    precondition(savedPreferences == preferences)
    let preferencesReopened = try await openApplication(
      root: root, models: "/unavailable-test-model", host: host)
    let restoredPreferences = try await preferencesReopened.preferences()
    precondition(restoredPreferences == preferences)
    let history = try await core.history()
    precondition(history.scans.count == 1)
    let id = history.scans[0].id
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
    do {
      _ = try await core.prepareCalendar(
        id: id, calendarId: "synthetic", timezone: saved.timezone, reminder: 10,
        selection: [edited[0].id], replacement: false)
      fatalError("Uncertain write allowed a blind retry")
    } catch AppError.UncertainWrite {}
    let recovered = try await core.reconcileCalendar()
    precondition(recovered.first?.status == .saved)
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
