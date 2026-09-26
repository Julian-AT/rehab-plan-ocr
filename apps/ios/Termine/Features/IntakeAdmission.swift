import Foundation

/// A presentation ticket survives ordinary cancellation, but never data erasure.
/// Producer leases are acquired synchronously before scheduling asynchronous I/O.
@MainActor final class IntakeAdmission {
    struct Ticket: Sendable, Equatable {
        let generation: UUID
    }
    private var generation = UUID()
    private var leases = Set<UUID>()
    private(set) var isOpen = false
    var isDrained: Bool { leases.isEmpty }
    func open() { isOpen = true }
    func close() { isOpen = false; generation = UUID() }
    func ticket() -> Ticket? { isOpen ? Ticket(generation: generation) : nil }
    func accepts(_ ticket: Ticket?) -> Bool { isOpen && ticket?.generation == generation }
    func begin(_ ticket: Ticket?) -> UUID? {
        guard accepts(ticket) else { return nil }
        let lease = UUID(); leases.insert(lease); return lease
    }
    func end(_ lease: UUID) { leases.remove(lease) }
}
