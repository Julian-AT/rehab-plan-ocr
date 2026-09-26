import Foundation

@main struct OrderedSettingsProbe {
  struct Value: Codable, Equatable, Sendable {
    var sound = false
    var preview = false
    var appearance = "system"
  }
  enum Failure: Error { case unavailable }
  @MainActor static func resetDiscardsOldRead(fails: Bool, oldReturnsFirst: Bool) async {
    var pending: [CheckedContinuation<Value, Error>] = []
    var writes: [Value] = []
    let store = OrderedSettings<Value>(
      read: { try await withCheckedThrowingContinuation { pending.append($0) } },
      write: {
        writes.append($0)
        return $0
      })
    let initialLoad = Task { await store.load() }
    while pending.count < 1 { await Task.yield() }
    let reset = Task { await store.reset() }
    while pending.count < 2 { await Task.yield() }
    let old = Value(sound: true, preview: true, appearance: "dark")
    let oldResult: Result<Value, Error> = fails ? .failure(Failure.unavailable) : .success(old)
    if oldReturnsFirst {
      pending[0].resume(with: oldResult)
      await initialLoad.value
      precondition(store.value == nil && store.error == nil)
      pending[1].resume(returning: Value())
      await reset.value
    } else {
      pending[1].resume(returning: Value())
      await reset.value
      pending[0].resume(with: oldResult)
      await initialLoad.value
    }
    precondition(store.value == Value() && store.error == nil)
    store.change { $0.appearance = "light" }
    let flushed = await store.flush()
    precondition(flushed && writes == [Value(appearance: "light")])
  }
  @MainActor static func main() async throws {
    for fails in [false, true] {
      for oldReturnsFirst in [false, true] {
        await resetDiscardsOldRead(fails: fails, oldReturnsFirst: oldReturnsFirst)
      }
    }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("settings.json")
    try JSONEncoder().encode(Value()).write(to: file)
    let read: () async throws -> Value = {
      try JSONDecoder().decode(Value.self, from: Data(contentsOf: file))
    }
    var active = 0
    var peak = 0
    var fail = false
    var writes: [Value] = []
    let write: (Value) async throws -> Value = { value in
      active += 1
      peak = max(peak, active)
      defer { active -= 1 }
      try await Task.sleep(for: .milliseconds(20))
      if fail {
        fail = false
        throw Failure.unavailable
      }
      try JSONEncoder().encode(value).write(to: file, options: .atomic)
      writes.append(value)
      return value
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
    precondition(
      retried && !store.canRetry
        && store.value == Value(sound: false, preview: true, appearance: "light"))
    let disk = try await read()
    precondition(disk == store.value)
    // A write that committed before reporting an error is read back truthfully.
    let uncertain = OrderedSettings(
      read: read,
      write: { value in
        try JSONEncoder().encode(value).write(to: file)
        throw Failure.unavailable
      })
    await uncertain.load()
    uncertain.change { $0.appearance = "system" }
    _ = await uncertain.flush()
    precondition(uncertain.value?.appearance == "system" && uncertain.canRetry)
    // A known durable save is never offered for retry because maintenance failed.
    var maintenanceFails = true
    let maintained = OrderedSettings(
      read: read,
      writeResult: { value in
        try JSONEncoder().encode(value).write(to: file, options: .atomic)
        return SettingsWriteResult(
          value: value,
          maintenanceWarnings: maintenanceFails ? ["Erinnerungen nicht aktualisiert."] : [])
      })
    await maintained.load()
    maintained.change { $0.appearance = "light" }
    let durable = await maintained.flush()
    let actual = try await read()
    precondition(durable && maintained.value == actual && actual.appearance == "light")
    precondition(maintained.error == nil && !maintained.canRetry)
    precondition(maintained.maintenanceWarnings == ["Erinnerungen nicht aktualisiert."])
    maintained.retry()
    precondition(!maintained.isSaving)
    maintenanceFails = false
    maintained.change { $0.appearance = "dark" }
    let successful = await maintained.flush()
    precondition(successful && maintained.maintenanceWarnings.isEmpty)
    print(
      "Settings: ordered edits, rollback, retry, uncertain readback, separate maintenance warnings, restart and stale-read protection passed"
    )
  }
}
