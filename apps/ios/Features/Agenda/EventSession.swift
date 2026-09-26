import Foundation
import Observation

struct EventResponse: Decodable {
  var proposal: EventProposalView?
  // swift-format-ignore: AlwaysUseLowerCamelCase
  var system_editor: CalendarEvent?
  var status: String?
  var message: String?
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
  typealias Request = @MainActor @Sendable (String, [String: Any]) async throws -> Data
  typealias OpenSystem = @MainActor @Sendable (CalendarEvent) async throws -> Void
  private let request: Request
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
    origin: String = "manual", request: @escaping Request,
    openSystem: @escaping OpenSystem = { _ in throw CocoaError(.featureUnsupported) },
    confirmationStarted: @escaping @MainActor @Sendable (String) -> Void = { _ in },
    describe: @escaping @MainActor @Sendable (Error) -> String = { $0.localizedDescription }
  ) {
    self.request = request
    self.systemEditor = openSystem
    self.confirmationStarted = confirmationStarted
    self.describe = describe
    self.origin = origin
    registration = EventSessionRegistration(
      register: {
        struct Registered: Decodable { let session: String }
        let result = try JSONDecoder().decode(
          Registered.self, from: await request("registerEventSession", [:]))
        return result.session
      },
      revoke: { token in
        _ = try? await request("invalidateEventSession", ["session": token])
      })
  }
  private func eventRequest<T: Decodable>(_ command: String, _ args: [String: Any]) async throws
    -> T
  {
    try JSONDecoder().decode(T.self, from: await request(command, args))
  }

  func preview(kind: String, calendar: String, event: CalendarEvent?, patch: [String: JSONValue])
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
      let response: EventResponse = try await eventRequest(
        "previewEventMutation",
        [
          "origin": origin, "kind": kind, "calendar_id": calendar,
          "event": try event.map(jsonObject) ?? NSNull(), "patch": try jsonObject(patch),
          "session": nativeSession, "revision": revision,
        ])
      guard self.session == session, self.revision == revision else { return }
      proposal = response.proposal
      systemEvent = response.system_editor
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
      let response: EventResponse = try await eventRequest(
        "confirmProposal",
        [
          "token": proposal.token, "session": proposal.session, "revision": revision,
          "confirmation": "button",
        ])
      guard session == current else { return }
      conversationResult =
        response.status == "saved"
        ? (proposal.kind == "remove"
          ? "Der Kalendereintrag ist gelöscht." : "Der Termin ist gespeichert.")
        : response.message ?? "Der Schreibstatus ist unklar. Bitte den Kalender abgleichen."
      result =
        response.status == "saved"
        ? "\(proposal.kind == "remove" ? "Kalendereintrag gelöscht" : "Gespeichert") in \(proposal.calendar_title)."
        : response.message ?? "Schreibstatus unklar. Kalender abgleichen."
      if response.maintenance_warnings?.isEmpty == false {
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
      let response: EventResponse = try await eventRequest(
        "previewEventUndo", ["id": id, "session": nativeSession, "revision": revision])
      guard session == current else { return }
      proposal = response.proposal
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
