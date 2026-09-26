import Foundation
import Observation

#if canImport(RehaCore)
  import RehaCore
#endif

@MainActor @Observable final class PlanModel {
  let core: NativeApplication
  let id: String
  var pages: [ReviewModel] = []
  var assessment: DraftAssessment?
  var proposal: Proposal?
  var outcome: SaveOutcome?
  var error: String?
  var retainedError: String?
  var loading = false
  var saving = false
  var needsCalendar = false
  var calendarID = ""
  var calendarName = "Kalender"
  var targetLocked = false
  var savedCalendarName = "Kalender"
  var timezone = "Europe/Vienna"
  private var generation = 0
  private let calendarAccess: @MainActor () -> Bool
  private let calendars: @MainActor () async throws -> CalendarDestinations
  init(
    core: NativeApplication, id: String,
    calendarAccess: @escaping @MainActor () -> Bool,
    calendars: @escaping @MainActor () async throws -> CalendarDestinations
  ) {
    self.core = core
    self.id = id
    self.calendarAccess = calendarAccess
    self.calendars = calendars
  }
  var appointments: [Appointment] {
    pages.compactMap(\.review).flatMap(\.appointments).sorted {
      ($0.date ?? "9999", $0.start ?? "99", $0.id) < ($1.date ?? "9999", $1.start ?? "99", $1.id)
    }
  }
  var selected: [String] {
    guard let proposal else { return [] }
    return (assessment?.readyIds ?? []).filter { id in
      guard let event = proposal.bindings[id] else { return false }
      return proposal.operations.contains {
        $0.id == event && !$0.requiresResolution
          && [.create, .update, .unchanged, .keep].contains($0.kind)
      }
    }
  }
  var total: Int { appointments.filter(\.included).count }
  var openCount: Int {
    (assessment?.questions.count ?? 0)
      + (proposal?.operations.filter(\.requiresResolution).count ?? 0)
  }
  var saveLabel: String {
    if selected.count < total { return "\(selected.count) von \(total) Terminen speichern" }
    return selected.count == 1 ? "1 Termin speichern" : "\(selected.count) Termine speichern"
  }
  var hasWrites: Bool {
    proposal?.operations.contains {
      !$0.requiresResolution && [.create, .update].contains($0.kind)
    } == true
  }
  func load(compare: Bool = true) async {
    guard !saving, !Task.isCancelled else { return }
    generation += 1
    let current = generation
    loading = true
    proposal = nil
    defer { if current == generation { loading = false } }
    do {
      let preferences = try await core.preferences()
      guard current == generation, !Task.isCancelled else { return }
      let ids = try await core.pageGroup(id: id)
      guard current == generation, !Task.isCancelled else { return }
      let history = try await core.history()
      guard current == generation, !Task.isCancelled else { return }
      let retainedError = history.intakes.first { $0.id == id && $0.error != nil }?.error
      var loaded: [ReviewModel] = []
      for page in ids {
        let model = ReviewModel(core: core, id: page)
        await model.load()
        guard current == generation, !Task.isCancelled else { return }
        if model.review != nil { loaded.append(model) }
      }
      var draft = try await core.assessDraft(id: id, timezone: preferences.timezone)
      guard current == generation, !Task.isCancelled else { return }
      let target = try await core.planCalendar(id: id)
      guard current == generation, !Task.isCancelled else { return }
      var needsCalendar = target.calendarId.isEmpty || !calendarAccess()
      var calendarName = "Kalender"
      if !needsCalendar {
        let destinations = try await calendars()
        guard current == generation, !Task.isCancelled else { return }
        needsCalendar = !destinations.calendars.contains {
          $0.id == target.calendarId && $0.writable
        }
        calendarName =
          destinations.calendars.first { $0.id == target.calendarId }
          .map { "\($0.title) · \($0.source)" } ?? "Kalender nicht verfügbar"
      }
      var proposal: Proposal?
      if compare && !needsCalendar && !draft.readyIds.isEmpty {
        let prepared = try await core.previewDraft(
          id: id, calendarId: target.calendarId, timezone: preferences.timezone,
          reminder: preferences.reminder)
        guard current == generation, !Task.isCancelled else { return }
        draft = prepared.assessment
        proposal = prepared.proposal
      }
      // Publish one generation only after every dependent read has completed.
      // Until then, the previously displayed pages and calendar stay together.
      timezone = preferences.timezone
      pages = loaded
      assessment = draft
      self.retainedError = retainedError
      calendarID = target.calendarId
      targetLocked = target.locked
      self.needsCalendar = needsCalendar
      self.calendarName = calendarName
      self.proposal = proposal
      error = nil
    } catch {
      if current == generation, !Task.isCancelled { self.error = userMessage(error) }
    }
  }

  func save() async {
    guard let proposal, !saving, !selected.isEmpty else { return }
    saving = true
    error = nil
    do {
      savedCalendarName = calendarName
      outcome = try await core.acceptAndSave(
        token: proposal.token, selection: selected, approveRemovals: false)
      self.proposal = nil
    } catch {
      self.error = userMessage(error)
      self.proposal = nil
    }
    let writeError = error
    saving = false
    await load()
    if let writeError { error = writeError }
  }
  func resolve(_ operation: CalendarOperation, choice: String) async {
    guard let proposal, !saving else { return }
    saving = true
    defer { saving = false }
    do {
      self.proposal = try await core.resolveProposal(
        token: proposal.token, eventId: operation.id, choice: choice)
      error = nil
    } catch { self.error = userMessage(error) }
  }
}
