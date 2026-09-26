import Foundation
import Darwin

/// The lock is outside receipts and survives erasure. A provider callback keeps
/// the generation captured before loading its file, including across processes.
struct IntakeGate: Sendable {
    struct State: Codable, Equatable, Sendable {
        var generation: UUID
        var erasing: Bool
    }
    let root: URL
    private func locked<Value>(_ body: (inout State) throws -> Value) throws -> Value {
        let files = FileManager.default
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        let descriptor = open(root.appendingPathComponent("intake.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw POSIXError(.EIO) }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw POSIXError(.EIO) }
        defer { flock(descriptor, LOCK_UN) }
        let stateURL = root.appendingPathComponent("intake-state.json")
        let exists = files.fileExists(atPath: stateURL.path)
        var state = exists ? try JSONDecoder().decode(State.self, from: Data(contentsOf: stateURL)) : State(generation: UUID(), erasing: false)
        // The initial generation must be persisted before handing out a ticket.
        if !exists { try JSONEncoder().encode(state).write(to: stateURL, options: .atomic) }
        let previous = state
        let result = try body(&state)
        if previous != state { try JSONEncoder().encode(state).write(to: stateURL, options: .atomic) }
        return result
    }
    func snapshot() throws -> State { try locked { $0 } }
    func ticket() throws -> UUID {
        try locked { state in
            guard !state.erasing else { throw IntakeGateError.erasing }
            return state.generation
        }
    }
    func write<Value>(generation: UUID, _ body: () throws -> Value) throws -> Value {
        try locked { state in
            guard !state.erasing, state.generation == generation else { throw IntakeGateError.expired }
            return try body()
        }
    }
    func beginErasure() throws {
        try locked { state in
            if !state.erasing { state = State(generation: UUID(), erasing: true) }
        }
    }
    func finishErasure() throws {
        try locked { state in
            guard state.erasing else { throw IntakeGateError.expired }
            let receipts = root.appendingPathComponent("receipts", isDirectory: true)
            if FileManager.default.fileExists(atPath: receipts.path) { try FileManager.default.removeItem(at: receipts) }
            state.erasing = false
        }
    }
}
enum IntakeGateError: LocalizedError {
    case erasing, expired
    var errorDescription: String? {
        switch self {
        case .erasing: "Lokale Daten werden gelöscht. Neue Erfassung anschließend starten."
        case .expired: "Diese Erfassung wurde durch das Löschen lokaler Daten beendet."
        }
    }
}
