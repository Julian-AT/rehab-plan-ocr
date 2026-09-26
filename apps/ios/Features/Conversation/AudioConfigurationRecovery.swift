import Foundation

/// Coalesce I/O notifications without rebuilding a healthy graph. A recovery
/// budget resets only after sustained buffers, never merely after start().
struct AudioConfigurationRecovery {
  enum Action { case none, wait, restart, fail }
  private var active = false
  private var due: Double?
  private var needsNewInput = false
  private var retried = false
  private var healthySince: Double?
  private var lastBuffer: Double?
  var isPending: Bool { due != nil }

  mutating func start() {
    self = Self()
    active = true
  }
  mutating func changed(at time: Double, needsNewInput: Bool = false) {
    guard active else { return }
    if due == nil { due = time + 0.15 }
    self.needsNewInput = self.needsNewInput || needsNewInput
  }
  mutating func received(at time: Double) {
    guard active else { return }
    if healthySince == nil || lastBuffer.map({ time - $0 > 0.5 }) == true { healthySince = time }
    lastBuffer = time
    if time - healthySince! >= 1 { retried = false }
  }
  mutating func check(at time: Double, running: Bool, matchingFormats: Bool) -> Action {
    guard active, let due else { return .none }
    guard time >= due else { return .wait }
    self.due = nil
    let forced = needsNewInput
    needsNewInput = false
    guard forced || !running || !matchingFormats else { return .none }
    healthySince = nil
    lastBuffer = nil
    guard !retried else { return .fail }
    retried = true
    return .restart
  }
  mutating func cancel() { self = Self() }
}
