import Foundation

/// Missing buffers and digital silence are different. A session may recover
/// once; cancelling it invalidates even an already scheduled timeout.
struct InputBufferWatchdog {
  enum Action { case wait, restart, fail }
  private var lastBuffer: Double?
  private var started: Double?
  private var retried = false
  mutating func start(at time: Double) {
    started = time
    lastBuffer = nil
  }
  mutating func received(at time: Double) { if started != nil { lastBuffer = time } }
  mutating func cancel() {
    started = nil
    lastBuffer = nil
  }
  mutating func check(at time: Double) -> Action {
    guard let since = lastBuffer ?? started, time - since >= 2 else { return .wait }
    if retried {
      cancel()
      return .fail
    }
    retried = true
    start(at: time)
    return .restart
  }
}
