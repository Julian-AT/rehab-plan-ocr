import Foundation
import Observation

/// One queue for every preferences screen. Mutations are applied to the last
/// saved value, so a suspended write cannot overwrite a later field change.
@MainActor @Observable final class OrderedSettings<Value: Equatable & Sendable> {
    typealias Mutation = (inout Value) -> Void
    private(set) var value: Value?
    private(set) var error: String?
    private(set) var isSaving = false
    private(set) var canRetry = false
    private var saved: Value?
    private var pending: [Mutation] = []
    private var failed: [Mutation] = []
    private var worker: Task<Void, Never>?
    private let read: () async throws -> Value
    private let write: (Value) async throws -> Value
    private let describe: (Error) -> String

    init(read: @escaping () async throws -> Value, write: @escaping (Value) async throws -> Value,
         describe: @escaping (Error) -> String = { $0.localizedDescription }) {
        self.read = read; self.write = write; self.describe = describe
    }
    func load() async {
        guard saved == nil, !isSaving else { return }
        do { let actual = try await read(); if saved == nil { saved = actual; value = actual }; error = nil }
        catch { self.error = describe(error) }
    }
    func change(_ mutation: @escaping Mutation) {
        guard var visible = value else { return }
        mutation(&visible)
        guard visible != value else {
            if !failed.isEmpty { failed.append(mutation) }
            return
        }
        value = visible; pending.append(mutation)
        // Preference edits are idempotent assignments. If an earlier edit needs
        // retry, retain newer choices after it so retry cannot undo those choices.
        if !failed.isEmpty { failed.append(mutation) }
        start()
    }
    func retry() {
        guard worker == nil, !failed.isEmpty else { return }
        pending = failed + pending; failed = []; canRetry = false; error = nil
        project(); start()
    }
    @discardableResult func flush() async -> Bool {
        await worker?.value
        return error == nil
    }
    func reset() async {
        await worker?.value
        pending = []; failed = []; canRetry = false; saved = nil; value = nil
        await load()
    }
    private func start() {
        guard worker == nil else { return }
        isSaving = true
        worker = Task { await drain() }
    }
    private func project() {
        guard var projected = saved else { return }
        for mutation in pending { mutation(&projected) }
        value = projected
    }
    private func drain() async {
        defer { isSaving = false; worker = nil; if !pending.isEmpty { start() } }
        while !pending.isEmpty, var next = saved {
            let mutation = pending.removeFirst(); mutation(&next)
            do {
                saved = try await write(next)
                project()
                if failed.isEmpty { error = nil }
            } catch {
                failed += [mutation] + pending; pending = []; canRetry = true
                // Read the actual persisted state after an uncertain write.
                if let actual = try? await read() { saved = actual }
                project()
                self.error = describe(error)
                return
            }
        }
    }
}
