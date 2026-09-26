import Foundation

private enum ProbeFailure: Error { case read, acknowledgement, presentation }

@MainActor private final class LinkHost {
  var reads: [String] = []
  var replies: [String: CheckedContinuation<String, Error>] = [:]
  var pendingRead: CheckedContinuation<String?, Error>?
  var pendingReads = 0
  var acknowledgements: [String] = []
  var heldAcknowledgement: CheckedContinuation<String?, Error>?
  var holdAcknowledgement = false
  var deliveries: [String] = []
  var failures: [ProbeFailure] = []
  var rejectPresentation = false
  func client() -> AgendaLinkRequests<String> {
    AgendaLinkRequests(
      resolve: { id in
        self.reads.append(id)
        // Intentionally ignore cancellation like a callback already in EventKit.
        return try await withCheckedThrowingContinuation { self.replies[id] = $0 }
      },
      pending: { id in
        if let id {
          self.acknowledgements.append(id)
          if self.holdAcknowledgement {
            return try await withCheckedThrowingContinuation { self.heldAcknowledgement = $0 }
          }
          return nil
        }
        self.pendingReads += 1
        return try await withCheckedThrowingContinuation { self.pendingRead = $0 }
      })
  }
  func receive(_ value: AgendaLinkDelivery<String>) throws {
    if rejectPresentation { throw ProbeFailure.presentation }
    switch value {
    case .today: deliveries.append("today")
    case .event(let value): deliveries.append(value)
    }
  }
  func failed(_ error: Error) { failures.append(error as! ProbeFailure) }
  func reply(_ id: String, _ result: Result<String, Error>) {
    replies.removeValue(forKey: id)!.resume(with: result)
  }
}

@main @MainActor struct AgendaLinkRequestsProbe {
  private static let first = "11111111-1111-4111-8111-111111111111"
  private static let second = "22222222-2222-4222-8222-222222222222"
  private static func ready(_ condition: () -> Bool) async {
    for _ in 0..<10_000 {
      if condition() { return }
      await Task.yield()
    }
    preconditionFailure("Expected link operation was not reached")
  }
  static func main() async {
    // A late owned-event read cannot reopen its sheet after the Today link.
    do {
      let host = LinkHost()
      let client = host.client()
      let old = client.open(.event(first), deliver: host.receive, failed: host.failed)
      await ready { host.replies[first] != nil }
      client.open(.today, deliver: host.receive, failed: host.failed)
      host.reply(first, .success("old"))
      await old?.value
      precondition(host.deliveries == ["today"] && host.acknowledgements.isEmpty)
      precondition(host.failures.isEmpty)
    }
    // Reordered results, coalesced repeated taps, and an old failure after B.
    do {
      let host = LinkHost()
      let client = host.client()
      let old = client.open(.event(first), deliver: host.receive, failed: host.failed)
      await ready { host.replies[first] != nil }
      let newest = client.open(.event(second), deliver: host.receive, failed: host.failed)
      client.open(.event(second), deliver: host.receive, failed: host.failed)
      await ready { host.replies[second] != nil }
      host.reply(second, .success("new"))
      await newest?.value
      host.reply(first, .failure(ProbeFailure.read))
      await old?.value
      precondition(host.reads == [first, second])
      precondition(host.deliveries == ["new"] && host.acknowledgements == [second])
      precondition(host.failures.isEmpty)
    }
    // User navigation, erasure and background all invalidate the same ownership.
    for reply: Result<String, Error> in [.success("old"), .failure(ProbeFailure.read)] {
      let host = LinkHost()
      let client = host.client()
      let old = client.open(.event(first), deliver: host.receive, failed: host.failed)
      await ready { host.replies[first] != nil }
      client.invalidate()
      host.reply(first, reply)
      await old?.value
      precondition(host.deliveries.isEmpty && host.failures.isEmpty)
      precondition(host.acknowledgements.isEmpty)
    }
    // A delayed notification read or startup/share recovery cannot undo a URL.
    do {
      let host = LinkHost()
      let client = host.client()
      let revision = client.revision
      let pending = client.openPending(
        expectedRevision: revision, deliver: host.receive, failed: host.failed)
      client.openPending(expectedRevision: revision, deliver: host.receive, failed: host.failed)
      await ready { host.pendingRead != nil }
      client.open(.today, deliver: host.receive, failed: host.failed)
      client.openPending(expectedRevision: revision, deliver: host.receive, failed: host.failed)
      host.pendingRead!.resume(returning: first)
      await pending?.value
      precondition(host.pendingReads == 1 && host.reads.isEmpty)
      precondition(host.deliveries == ["today"] && host.acknowledgements.isEmpty)
    }
    // Acknowledgement may already be committing; its late error stays obsolete.
    do {
      let host = LinkHost()
      let client = host.client()
      host.holdAcknowledgement = true
      let old = client.open(.event(first), deliver: host.receive, failed: host.failed)
      await ready { host.replies[first] != nil }
      host.reply(first, .success("opened"))
      await ready { host.heldAcknowledgement != nil }
      client.open(.today, deliver: host.receive, failed: host.failed)
      host.heldAcknowledgement!.resume(throwing: ProbeFailure.acknowledgement)
      await old?.value
      precondition(host.deliveries == ["opened", "today"] && host.failures.isEmpty)
      precondition(host.acknowledgements == [first])
    }
    // Current errors remain visible; a rejected projection never consumes a link.
    for reject in [false, true] {
      let host = LinkHost()
      let client = host.client()
      host.rejectPresentation = reject
      let work = client.open(.event(first), deliver: host.receive, failed: host.failed)
      await ready { host.replies[first] != nil }
      host.reply(first, reject ? .success("invalid projection") : .failure(ProbeFailure.read))
      await work?.value
      precondition(host.failures == [reject ? .presentation : .read])
      precondition(host.deliveries.isEmpty && host.acknowledgements.isEmpty)
    }
    // The pending path must also deliver/acknowledge its exact valid identity.
    for target in [first, "invalid-id"] {
      let host = LinkHost()
      let client = host.client()
      let work = client.openPending(
        expectedRevision: client.revision, deliver: host.receive, failed: host.failed)
      await ready { host.pendingRead != nil }
      host.pendingRead!.resume(returning: target)
      if target == first {
        await ready { host.replies[first] != nil }
        host.reply(first, .success("pending"))
      }
      await work?.value
      precondition(host.deliveries == (target == first ? ["pending"] : []))
      precondition(host.acknowledgements == (target == first ? [first] : []))
    }
    print(
      "Agenda links: 10 controlled flows passed; stale reads/errors, duplicate taps, pending recovery, acknowledgement and cancellation preserve current navigation."
    )
  }
}
