import Foundation
import Observation
import RehaCore

/// The remaining reconciliation endpoint returns only maintenance information here.
struct EventResponse: Decodable {
  // swift-format-ignore: AlwaysUseLowerCamelCase
  var maintenance_warnings: [String]?
}
struct EventHistoryItem: Decodable, Identifiable {
  let id: String
  // swift-format-ignore: AlwaysUseLowerCamelCase
  let created_at: Double
  let proposal: EventProposalView
  let status: String
  // swift-format-ignore: AlwaysUseLowerCamelCase
  let undone_by: String?
}
@MainActor func jsonObject<T: Encodable>(_ value: T) throws -> Any {
  try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
}
@MainActor @Observable final class EventSession {
  typealias OpenSystem = @MainActor @Sendable (CalendarEvent) async throws -> Void
  private let client: EventMutationClient
  private let systemEditor: OpenSystem
  private let confirmationStarted: @MainActor @Sendable (String) -> Void
  private let describe: @MainActor @Sendable (Error) -> String
  let origin: String
  private let registration: EventSessionRegistration
  private(set) var session = UUID().uuidString
  private(set) var revision: UInt64 = 0
  var proposal: EventProposalView?
  var systemEvent: CalendarEvent?
  var busy = false
  var error: String?
  var conversationResult: String?
  var result: String?
  init(
    origin: String = "manual", client: EventMutationClient,
    openSystem: @escaping OpenSystem = { _ in throw CocoaError(.featureUnsupported) },
    confirmationStarted: @escaping @MainActor @Sendable (String) -> Void = { _ in },
    describe: @escaping @MainActor @Sendable (Error) -> String = { $0.localizedDescription }
  ) {
    self.client = client
    self.systemEditor = openSystem
    self.confirmationStarted = confirmationStarted
    self.describe = describe
    self.origin = origin
    registration = EventSessionRegistration(register: client.register, revoke: client.invalidate)
  }
  private func show(_ response: EventPreviewResult) throws {
    switch response {
    case .proposal(let value):
      proposal = try EventProposalView(value)
      systemEvent = nil
    case .systemEditor(let event):
      proposal = nil
      systemEvent = try CalendarEvent(event)
    }
  }

  func preview(
    kind: EventMutationKind, calendar: String, event: CalendarEvent?, patch: EventEditPatch
  )
    async
  {
    guard !busy else { return }
    busy = true
    revision += 1
    let revision = revision
    let session = session
    proposal = nil
    result = nil
    conversationResult = nil
    defer { if self.session == session { busy = false } }
    do {
      let nativeSession = try await registration.acquire()
      let response = try await client.preview(
        EventPreviewRequest(
          session: nativeSession, revision: revision, kind: kind, calendarId: calendar,
          event: try event.map { try $0.nativeReadEvent }, patch: patch, origin: origin))
      guard self.session == session, self.revision == revision else { return }
      try show(response)
      error = nil
    } catch { if self.session == session { self.error = describe(error) } }
  }
  func confirm() async {
    guard let proposal, !busy else { return }
    busy = true
    self.proposal = nil
    conversationResult = nil
    let current = session
    confirmationStarted(proposal.token)
    defer { if session == current { busy = false } }
    do {
      let response = try await client.confirm(
        EventConfirmRequest(
          token: proposal.token, session: proposal.session, revision: revision,
          confirmation: .button))
      guard session == current else { return }
      conversationResult =
        response.status == .saved
        ? (proposal.kind == "remove"
          ? "Der Kalendereintrag ist gelöscht." : "Der Termin ist gespeichert.")
        : response.message ?? "Der Schreibstatus ist unklar. Bitte den Kalender abgleichen."
      result =
        response.status == .saved
        ? "\(proposal.kind == "remove" ? "Kalendereintrag gelöscht" : "Gespeichert") in \(proposal.calendar_title)."
        : response.message ?? "Schreibstatus unklar. Kalender abgleichen."
      if !response.maintenanceWarnings.isEmpty {
        let warning = " Erinnerungen und Widgets konnten noch nicht aktualisiert werden."
        result = (result ?? "") + warning
        conversationResult = (conversationResult ?? "") + warning
      }
      error = nil
    } catch { if session == current { self.error = describe(error) } }
  }
  func undo(_ id: String) async {
    guard !busy else { return }
    busy = true
    revision += 1
    let current = session
    defer { if session == current { busy = false } }
    do {
      let nativeSession = try await registration.acquire()
      let response = try await client.undo(
        EventUndoRequest(id: id, session: nativeSession, revision: revision))
      guard session == current else { return }
      try show(response)
      error = nil
    } catch { if session == current { self.error = describe(error) } }
  }
  func interrupt() {
    registration.invalidate()
    session = UUID().uuidString
    revision += 1
    proposal = nil
    systemEvent = nil
    busy = false
    error = nil
    result = nil
    conversationResult = nil
  }
  func openSystem(_ event: CalendarEvent) async {
    interrupt()
    let current = session
    do {
      try await systemEditor(event)
      guard session == current else { return }
      result =
        "Kalenderbearbeitung beendet. Termine neu laden. Diese Änderung steht nicht im App-Rückgängig zur Verfügung."
    } catch {
      if session == current {
        self.error =
          "\(describe(error)) Im Kalender suchen: \(event.values.title), \(eventDate(event.values.start))."
      }
    }
  }
}
