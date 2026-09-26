import Foundation

@main struct OrderedSettingsProbe {
    struct Value: Codable, Equatable, Sendable { var sound = false; var preview = false; var appearance = "system" }
    enum Failure: Error { case unavailable }
    @MainActor static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("settings.json")
        try JSONEncoder().encode(Value()).write(to: file)
        let read: () async throws -> Value = { try JSONDecoder().decode(Value.self, from: Data(contentsOf: file)) }
        var active = 0, peak = 0, fail = false
        var writes: [Value] = []
        let write: (Value) async throws -> Value = { value in
            active += 1; peak = max(peak, active); defer { active -= 1 }
            try await Task.sleep(for: .milliseconds(20))
            if fail { fail = false; throw Failure.unavailable }
            try JSONEncoder().encode(value).write(to: file, options: .atomic)
            writes.append(value); return value
        }
        let store = OrderedSettings(read: read, write: write)
        await store.load()
        store.change { $0.sound = true }
        store.change { $0.preview = true }
        store.change { $0.appearance = "dark" }
        store.change { $0.sound = false }
        precondition(store.value == Value(sound: false, preview: true, appearance: "dark"))
        let saved = await store.flush()
        precondition(saved && peak == 1 && writes.count == 4)
        let restarted = OrderedSettings(read: read, write: write)
        await restarted.load()
        precondition(restarted.value == store.value)
        fail = true
        store.change { $0.sound = true }
        store.change { $0.appearance = "light" }
        let failed = await store.flush()
        precondition(!failed && store.canRetry && store.value == restarted.value)
        store.change { $0.sound = false }
        _ = await store.flush()
        store.retry()
        let retried = await store.flush()
        precondition(retried && !store.canRetry && store.value == Value(sound: false, preview: true, appearance: "light"))
        let disk = try await read()
        precondition(disk == store.value)
        // A write that committed before reporting an error is read back truthfully.
        let uncertain = OrderedSettings(read: read, write: { value in
            try JSONEncoder().encode(value).write(to: file); throw Failure.unavailable
        })
        await uncertain.load(); uncertain.change { $0.appearance = "system" }
        _ = await uncertain.flush()
        precondition(uncertain.value?.appearance == "system" && uncertain.canRetry)
        print("Settings: ordered rapid edits, optimistic display, failure rollback, retry, uncertain-write readback and restart persistence passed")
    }
}
