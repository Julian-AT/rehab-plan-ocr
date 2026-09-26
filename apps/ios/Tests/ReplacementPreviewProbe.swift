import Foundation

// Typed stand-ins exercise the production request adapter without EventKit/FFI.
struct Preferences {
  let calendarId: String
  let reminder: UInt32? = 15
}
struct PlanCalendar { let calendarId: String }
struct DraftPreview: Equatable {
  let token: String
  let revision: String
  let calendarID: String
}
// swift-format-ignore: AlwaysUseLowerCamelCase
enum AppError: Error { case Validation(message: String) }

@MainActor final class NativeApplication {
  let defaultID: String
  let resolvedPlanID: String
  var hold: String?
  var pending: CheckedContinuation<Void, Never>?
  var calls: [String] = []
  init(defaultID: String, resolvedPlanID: String) {
    self.defaultID = defaultID
    self.resolvedPlanID = resolvedPlanID
  }
  private func step(_ name: String) async {
    calls.append(name)
    if hold == name {
      hold = nil
      await withCheckedContinuation { pending = $0 }
    }
  }
  func release() {
    let continuation = pending
    pending = nil
    continuation?.resume()
  }
  func preferences() async throws -> Preferences {
    await step("preferences")
    return Preferences(calendarId: defaultID)
  }
  func planCalendar(id: String) async throws -> PlanCalendar {
    precondition(id == "plan")
    await step("target")
    return PlanCalendar(calendarId: resolvedPlanID)
  }
  func previewReplacement(id: String, calendarId: String, timezone: String, reminder: UInt32?)
    async throws -> DraftPreview
  {
    precondition(id == "plan" && timezone == "Europe/Vienna" && reminder == 15)
    await step("preview")
    return DraftPreview(
      token: "original-token", revision: "original-revision", calendarID: calendarId)
  }
}

@MainActor private final class PreviewOwner {
  var state = ReplacementPreviewState<DraftPreview>()
  let inputs = ReplacementPreviewState<DraftPreview>.Inputs(previousID: "previous", complete: true)
}

@main @MainActor struct ReplacementPreviewProbe {
  static func main() async throws {
    var state = ReplacementPreviewState<String>()
    let a = ReplacementPreviewState<String>.Inputs(previousID: "a", complete: true)
    let b = ReplacementPreviewState<String>.Inputs(previousID: "b", complete: true)
    let incomplete = ReplacementPreviewState<String>.Inputs(previousID: "a", complete: false)

    let first = state.begin(inputs: a)
    // The binding can change before SwiftUI delivers its onChange callback.
    precondition(!state.finish(first, inputs: b, value: "stale comparison"))
    precondition(!state.finish(first, inputs: incomplete, value: "incomplete plan"))
    state.invalidate()
    precondition(!state.finish(first, inputs: a, value: "A → B → A"))

    let second = state.begin(inputs: a)
    precondition(state.finish(second, inputs: a, value: "current comparison"))
    precondition(state.value == "current comparison")
    precondition(state.current(inputs: b) == nil && state.current(inputs: incomplete) == nil)
    let pendingResolution = state.begin(inputs: a, retainingValue: true)
    precondition(state.current(inputs: a) == "current comparison")
    state.removalsApproved = true
    state.invalidate()  // External calendar edit or leaving the screen.
    precondition(state.value == nil && !state.removalsApproved)
    precondition(!state.finish(second, inputs: a, value: "late duplicate"))
    precondition(!state.finish(pendingResolution, inputs: a, value: "obsolete resolution"))

    let resolving = state.begin(inputs: a)
    state.invalidate()
    let newest = state.begin(inputs: b)
    precondition(!state.finish(resolving, inputs: a, value: "old resolution"))
    precondition(state.accepts(newest, inputs: b))
    precondition(state.finish(newest, inputs: b, value: "new comparison"))
    precondition(state.value == "new comparison" && !state.removalsApproved)
    precondition(!state.finish(resolving, inputs: b, value: "wrong selection"))
    try await planDestinationsAndRequestBoundaries()
    print(
      "Replacement preview passed: input/revision fences, deletion approval, bound B with default A/empty, unbound fallback and no calendar write."
    )
  }

  private static func planDestinationsAndRequestBoundaries() async throws {
    // Bound B remains B even when the app's default is A or unset. For an
    // unbound draft, use the target already resolved by the store (default A).
    for (defaultID, planID) in [("A", "B"), ("", "B"), ("A", "A")] {
      let source = NativeApplication(defaultID: defaultID, resolvedPlanID: planID)
      let owner = PreviewOwner()
      let request = owner.state.begin(inputs: owner.inputs)
      let result = try await source.previewPlanReplacement(
        id: "plan", timezone: "Europe/Vienna",
        isCurrent: { owner.state.accepts(request, inputs: owner.inputs) })
      precondition(result.calendarID == planID)
      precondition(result.token == "original-token" && result.revision == "original-revision")
      precondition(source.calls == ["preferences", "target", "preview"])
      precondition(owner.state.finish(request, inputs: owner.inputs, value: result))
      precondition(!owner.state.removalsApproved)
    }
    let missing = NativeApplication(defaultID: "", resolvedPlanID: "")
    do {
      _ = try await missing.previewPlanReplacement(
        id: "plan", timezone: "Europe/Vienna", isCurrent: { true })
      fatalError("Unbound draft with no destination reached preview")
    } catch AppError.Validation {}
    precondition(missing.calls == ["preferences", "target"])

    for stage in ["preferences", "target", "preview"] {
      for cancelTask in [false, true] {
        let source = NativeApplication(defaultID: "A", resolvedPlanID: "B")
        source.hold = stage
        let owner = PreviewOwner()
        let request = owner.state.begin(inputs: owner.inputs)
        let loading = Task {
          try await source.previewPlanReplacement(
            id: "plan", timezone: "Europe/Vienna",
            isCurrent: { owner.state.accepts(request, inputs: owner.inputs) })
        }
        for _ in 0..<10_000 {
          if source.pending != nil { break }
          await Task.yield()
        }
        precondition(source.pending != nil, "Expected delayed \(stage)")
        if cancelTask { loading.cancel() } else { owner.state.invalidate() }
        let before = source.calls
        source.release()
        do {
          _ = try await loading.value
          fatalError("Obsolete or cancelled preview escaped its request")
        } catch is CancellationError {}
        precondition(source.calls == before, "Obsolete preview advanced past \(stage)")
        precondition(owner.state.value == nil && !owner.state.removalsApproved)
      }
    }
  }
}
