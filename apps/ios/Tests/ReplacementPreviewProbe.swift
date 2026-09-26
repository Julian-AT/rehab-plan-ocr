import Foundation

@main struct ReplacementPreviewProbe {
  static func main() {
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
    print(
      "Replacement preview regressions passed: changed inputs, A→B→A, calendar invalidation, late resolution and deletion approval."
    )
  }
}
