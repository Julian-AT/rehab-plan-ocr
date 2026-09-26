import Foundation

@main @MainActor struct ScanAttemptRegistryProbe {
  static func main() async throws {
    let admission = IntakeAdmission()
    admission.open()
    let ticket = admission.ticket()!
    let registry = ScanAttemptRegistry(limit: 4)

    // An abandoned camera that has no producer needs no historical entry.
    let camera = try registry.register(id: "camera", ticket: ticket, parent: "plan")
    registry.revokeAll()
    precondition(registry.count == 0 && registry.active("camera") == nil)
    precondition(registry.begin(camera) == nil && !registry.permits(camera))

    // Photo delivery may retain its original after cancel. It cannot restart
    // recognition, and retry must wait until all writers of this ID have ended.
    let photo = try registry.register(id: "photo", ticket: ticket, parent: "plan")
    let provider = registry.begin(photo)!
    registry.finishInput(photo)
    registry.revokeAll()
    precondition(registry.count == 1 && registry.owns(photo) && !registry.permits(photo))
    precondition(admission.accepts(photo.ticket) && photo.parent == "plan")
    let persistence = registry.begin(photo)!
    precondition(!registry.end(provider) && registry.count == 1)
    do {
      _ = try registry.register(id: "photo", ticket: ticket)
      preconditionFailure("Two attempts could write the same document simultaneously")
    } catch ScanAttemptRegistry.RegistrationError.busy {}
    precondition(registry.end(persistence) && registry.count == 0)
    let retry = try registry.register(id: "photo", ticket: ticket)
    let retryOwner = registry.begin(retry)!
    registry.finishInput(retry)
    registry.end(provider)
    registry.end(persistence)
    precondition(registry.permits(retry) && registry.count == 1)
    precondition(!registry.permits(photo) && registry.begin(photo) == nil)
    registry.end(retryOwner)
    precondition(registry.count == 0)

    // A queued OCR task keeps the registration after the source producer ends.
    let queued = try registry.register(id: "queued", ticket: ticket)
    let source = registry.begin(queued)!
    registry.finishInput(queued)
    let inference = registry.begin(queued)!
    registry.end(source)
    precondition(registry.count == 1 && registry.permits(queued))
    registry.end(inference)
    precondition(registry.count == 0)

    await delayedPDFReturn(registry, ticket: ticket)
    await nativeDrain(registry, ticket: ticket)

    // Repeated successful and cancelled attempts leave no ever-growing sets.
    for index in 0..<2_000 {
      let attempt = try registry.register(id: "cycle-\(index)", ticket: ticket)
      let owner = registry.begin(attempt)!
      registry.finishInput(attempt)
      if index.isMultiple(of: 2) { registry.revokeAll() }
      registry.end(owner)
      precondition(registry.count == 0)
    }
    var held: [ScanAttemptRegistry.Lease] = []
    for index in 0..<4 {
      let attempt = try registry.register(id: "held-\(index)", ticket: ticket)
      held.append(registry.begin(attempt)!)
      registry.finishInput(attempt)
      registry.revokeAll()
    }
    do {
      _ = try registry.register(id: "overflow", ticket: ticket)
      preconditionFailure("Hung producers bypassed the registration limit")
    } catch ScanAttemptRegistry.RegistrationError.full {}
    precondition(registry.count == 4)
    for owner in held { registry.end(owner) }
    precondition(registry.count == 0)
    let erased = try registry.register(id: "erased", ticket: ticket)
    let erasingOwner = registry.begin(erased)!
    registry.finishInput(erased)
    admission.close()
    registry.revokeAll()
    admission.open()
    precondition(!admission.accepts(erased.ticket) && !registry.permits(erased))
    registry.end(erasingOwner)
    precondition(registry.count == 0)
    print(
      "Scan attempts: bounded ownership, native/producer drain, retry isolation, delayed PDF and erasure passed"
    )
  }

  @MainActor private final class DrainState {
    var busy = true
    var completions = 0
  }

  private static func nativeDrain(
    _ registry: ScanAttemptRegistry, ticket: IntakeAdmission.Ticket
  ) async {
    let state = DrainState()
    let completed = AsyncStream<Void>.makeStream()
    var held: [ScanAttemptRegistry.Lease] = []
    for index in 0..<4 {
      let attempt = try! registry.register(id: "native-\(index)", ticket: ticket)
      let owner = registry.begin(attempt)!
      held.append(owner)
      registry.finishInput(attempt)
      registry.endAfterDrain(owner) {
        state.busy
      } completion: { retired in
        precondition(retired)
        state.completions += 1
        if state.completions == 4 { completed.continuation.finish() }
      }
    }
    registry.revokeAll()
    precondition(registry.count == 4 && registry.drainingCount == 4 && state.completions == 0)
    for owner in held { precondition(!registry.end(owner)) }
    do {
      _ = try registry.register(id: "native-0", ticket: ticket)
      preconditionFailure("Partial native result admitted a competing retry")
    } catch ScanAttemptRegistry.RegistrationError.busy {} catch {
      preconditionFailure("Unexpected registration error: \(error)")
    }
    // Duplicated completion cannot replace a pending drain callback.
    registry.endAfterDrain(held[0]) {
      state.busy
    } completion: { _ in
      preconditionFailure("Duplicate drain completion")
    }
    await Task.yield()
    precondition(registry.count == 4 && state.completions == 0)
    state.busy = false
    for await _ in completed.stream {}
    precondition(registry.count == 0 && registry.drainingCount == 0 && state.completions == 4)
    let retry = try! registry.register(id: "native-0", ticket: ticket)
    let owner = registry.begin(retry)!
    registry.finishInput(retry)
    registry.end(held[0])
    precondition(registry.permits(retry) && !registry.permits(held[0].attempt))
    var immediate = false
    registry.endAfterDrain(owner) {
      false
    } completion: { retired in
      precondition(retired)
      immediate = true
    }
    precondition(immediate && registry.count == 0)
  }

  private static func delayedPDFReturn(
    _ registry: ScanAttemptRegistry, ticket: IntakeAdmission.Ticket
  ) async {
    let document = try! registry.register(id: "pdf", ticket: ticket)
    let documentOwner = registry.begin(document)!
    registry.finishInput(document)
    let page = try! registry.register(id: "pdf-page", ticket: ticket)
    let renderer = registry.begin(page)!
    registry.finishInput(page)
    let entered = AsyncStream<Void>.makeStream()
    let resumed = AsyncStream<Void>.makeStream()
    var delivered = false
    let late = Task {
      defer {
        registry.end(renderer)
        registry.end(documentOwner)
      }
      entered.continuation.yield()
      entered.continuation.finish()
      for await _ in resumed.stream {}
      guard registry.permits(document), registry.permits(page) else { return }
      delivered = true
    }
    for await _ in entered.stream {}
    registry.revokeAll()
    precondition(registry.count == 2)
    resumed.continuation.finish()
    await late.value
    precondition(!delivered && registry.count == 0)
  }
}
