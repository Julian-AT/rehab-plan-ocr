import Foundation

// Transport stand-ins keep this race probe independent of EventKit and FFI.
// Both load implementations below are the production models, not test copies.
struct Appointment {
  var id: String
  var date: String? = nil
  var start: String? = nil
  var included = true
}
struct ReviewSnapshot { var appointments: [Appointment] }
struct DraftAssessment {
  var readyIds: [String]
  var questions: [String] = []
}
struct CalendarOperation {
  enum Kind { case create, update, unchanged, keep }
  var id: String
  var requiresResolution = false
  var kind = Kind.create
}
struct Proposal {
  var token: String
  var bindings: [String: String]
  var operations: [CalendarOperation]
}
struct SaveOutcome {}
struct Preferences {
  var timezone: String
  var reminder = true
}
struct History {
  struct Intake {
    var id: String
    var error: String?
  }
  var intakes: [Intake]
}
struct PlanCalendar {
  var calendarId: String
  var locked: Bool
}
struct DraftPreview {
  var assessment: DraftAssessment
  var proposal: Proposal
}
struct CalendarDestinations {
  struct Destination {
    var id: String
    var title: String
    var source: String
    var writable = true
  }
  var calendars: [Destination]
}
func userMessage(_ error: Error) -> String { error.localizedDescription }

@MainActor final class NativeApplication {
  var revision = "initial"
  var hold: String?
  var pending: CheckedContinuation<Void, Never>?
  var fail: String?
  var calls: [String] = []

  private func step(_ name: String) async throws {
    calls.append("\(revision):\(name)")
    let failure = fail == name
    if hold == name {
      hold = nil
      await withCheckedContinuation { pending = $0 }
    }
    if failure { throw CocoaError(.fileReadUnknown) }
  }
  func release() {
    let continuation = pending
    pending = nil
    continuation?.resume()
  }
  func preferences() async throws -> Preferences {
    let result = Preferences(timezone: revision)
    try await step("preferences")
    return result
  }
  func pageGroup(id: String) async throws -> [String] {
    let result = [revision]
    try await step("pages")
    return result
  }
  func history() async throws -> History {
    let result = History(intakes: [.init(id: "plan", error: revision)])
    try await step("history")
    return result
  }
  func loadScan(id: String) async throws -> ReviewSnapshot {
    let result = ReviewSnapshot(appointments: [.init(id: id)])
    try await step("scan")
    return result
  }
  func assessDraft(id: String, timezone: String) async throws -> DraftAssessment {
    let result = DraftAssessment(readyIds: [revision])
    try await step("assessment")
    return result
  }
  func planCalendar(id: String) async throws -> PlanCalendar {
    let result = PlanCalendar(calendarId: revision, locked: revision == "latest")
    try await step("target")
    return result
  }
  func destinations() async throws -> CalendarDestinations {
    let result = CalendarDestinations(calendars: [
      .init(id: revision, title: revision, source: "local")
    ])
    try await step("destinations")
    return result
  }
  func previewDraft(id: String, calendarId: String, timezone: String, reminder: Bool) async throws
    -> DraftPreview
  {
    precondition(calendarId == revision && timezone == revision)
    let result = DraftPreview(
      assessment: .init(readyIds: [revision]),
      proposal: .init(
        token: revision, bindings: [revision: revision], operations: [.init(id: revision)]))
    try await step("preview")
    return result
  }
  func acceptAndSave(token: String, selection: [String], approveRemovals: Bool) async throws
    -> SaveOutcome
  { preconditionFailure("Loading must never save") }
  func resolveProposal(token: String, eventId: String, choice: String) async throws -> Proposal {
    preconditionFailure("Loading must never resolve")
  }
}

@MainActor final class ReviewModel {
  let core: NativeApplication
  let id: String
  var review: ReviewSnapshot?
  init(core: NativeApplication, id: String) {
    self.core = core
    self.id = id
  }
  func load() async { review = try? await core.loadScan(id: id) }
}

@main @MainActor struct PlanLoadingProbe {
  static func wait(_ source: NativeApplication) async {
    for _ in 0..<10_000 {
      if source.pending != nil { return }
      await Task.yield()
    }
    preconditionFailure("Expected held request")
  }
  static func check(_ model: PlanModel, _ revision: String) {
    precondition(model.pages.map(\.id) == [revision])
    precondition(model.assessment?.readyIds == [revision])
    precondition(model.timezone == revision && model.retainedError == revision)
    precondition(model.calendarID == revision && model.targetLocked == (revision == "latest"))
    precondition(model.calendarName == "\(revision) · local" && !model.needsCalendar)
  }
  static func main() async {
    for stage in [
      "preferences", "pages", "history", "scan", "assessment", "target", "destinations", "preview",
    ] {
      let source = NativeApplication()
      let model = PlanModel(
        core: source, id: "plan", calendarAccess: { true },
        calendars: {
          try await source.destinations()
        })
      await model.load()
      check(model, "initial")
      source.revision = "outdated"
      source.hold = stage
      let old = Task { await model.load() }
      await wait(source)
      check(model, "initial")
      precondition(model.loading && model.proposal == nil, "Loading invalidates confirmation only")
      source.revision = "latest"
      await model.load()
      check(model, "latest")
      let calls = source.calls.count
      source.release()
      await old.value
      check(model, "latest")
      precondition(!model.loading && model.proposal?.token == "latest" && model.error == nil)
      precondition(
        source.calls.count == calls, "Superseded load must stop after its awaited result")
    }
    await cancelledAndFailedDetailLoadsRetainContent()
    await pageSnapshotsNeverMixGenerations()
    print(
      "Plan loading: coherent snapshots, all delayed boundaries, stale errors and cancellation passed"
    )
  }

  static func cancelledAndFailedDetailLoadsRetainContent() async {
    let source = NativeApplication()
    let model = PlanModel(
      core: source, id: "plan", calendarAccess: { true },
      calendars: {
        try await source.destinations()
      })
    await model.load()
    source.revision = "cancelled"
    source.hold = "target"
    let task = Task { await model.load() }
    await wait(source)
    task.cancel()
    source.release()
    await task.value
    check(model, "initial")
    precondition(model.error == nil && !model.loading && model.proposal == nil)
    source.fail = "destinations"
    await model.load()
    check(model, "initial")
    precondition(model.error != nil && !model.loading && model.proposal == nil)
    source.hold = "target"
    source.fail = "target"
    let failing = Task { await model.load() }
    await wait(source)
    source.fail = nil
    source.revision = "latest"
    await model.load()
    source.release()
    await failing.value
    check(model, "latest")
    precondition(model.error == nil && model.proposal?.token == "latest")
  }

  static func pageSnapshotsNeverMixGenerations() async {
    for stage in ["pages", "scan"] {
      let source = NativeApplication()
      let model = PlanPagesModel()
      await model.load(core: source, id: "plan")
      source.revision = "outdated"
      source.hold = stage
      let old = Task { await model.load(core: source, id: "plan") }
      await wait(source)
      precondition(model.snapshot.pageIDs == ["initial"])
      precondition(model.snapshot.reviews["initial"]?.appointments.first?.id == "initial")
      source.revision = "latest"
      await model.load(core: source, id: "plan")
      source.release()
      await old.value
      precondition(model.snapshot.pageIDs == ["latest"])
      precondition(Set(model.snapshot.reviews.keys) == ["latest"])
      source.revision = "cancelled"
      source.hold = stage
      let cancelled = Task { await model.load(core: source, id: "plan") }
      await wait(source)
      cancelled.cancel()
      source.release()
      await cancelled.value
      precondition(model.snapshot.pageIDs == ["latest"] && model.error == nil)
      source.fail = "pages"
      await model.load(core: source, id: "plan")
      precondition(model.snapshot.pageIDs == ["latest"] && model.error != nil)
      source.fail = nil
      source.revision = "recovered"
      await model.load(core: source, id: "plan")
      precondition(model.snapshot.pageIDs == ["recovered"] && model.error == nil)
    }
  }
}
