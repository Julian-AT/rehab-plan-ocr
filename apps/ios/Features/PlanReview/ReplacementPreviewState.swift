import Foundation

/// A preview belongs to one immutable set of inputs and one calendar snapshot.
/// Invalidating a request also rejects a late completion after A → B → A changes.
struct ReplacementPreviewState<Value> {
  struct Inputs: Equatable {
    let previousID: String
    let complete: Bool
  }
  struct Request: Equatable {
    fileprivate let id = UUID()
    let inputs: Inputs
  }
  private var request: Request?
  private var valueInputs: Inputs?
  private(set) var value: Value?
  var removalsApproved = false

  mutating func begin(inputs: Inputs, retainingValue: Bool = false) -> Request {
    if !retainingValue || valueInputs != inputs { invalidate() }
    removalsApproved = false
    let request = Request(inputs: inputs)
    self.request = request
    return request
  }
  func accepts(_ request: Request, inputs: Inputs) -> Bool {
    self.request == request && request.inputs == inputs && inputs.complete
  }
  func current(inputs: Inputs) -> Value? {
    valueInputs == inputs && inputs.complete ? value : nil
  }
  @discardableResult
  mutating func finish(_ request: Request, inputs: Inputs, value: Value?) -> Bool {
    guard accepts(request, inputs: inputs) else { return false }
    self.request = nil
    self.value = value
    valueInputs = inputs
    return true
  }
  mutating func invalidate() {
    request = nil
    value = nil
    valueInputs = nil
    removalsApproved = false
  }
}
