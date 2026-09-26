#if DEBUG && REHA_CUSTOM_ASSISTANT_TRIAL && targetEnvironment(simulator)
  import Foundation

  /// Run-bound test status in the existing app group, visible to the isolated
  /// entitled XCTest runner while a modal sheet hides the underlying view.
  final class AssistantVoiceTrialSignal: Sendable {
    private let url: URL
    private let runID: String
    private let scenario: String
    init?(runID: String, scenario: String, directory: URL? = nil) {
      guard UUID(uuidString: runID) != nil,
        ["calendar-audio", "minimal-create", "rename-confirm", "late-cancel", "live-confirm"]
          .contains(scenario),
        let root = directory
          ?? FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.at.rehakalender.personal")
      else { return nil }
      self.runID = runID
      self.scenario = scenario
      let folder = root.appendingPathComponent("assistant-voice-trial", isDirectory: true)
      do {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      } catch { return nil }
      url = folder.appendingPathComponent("\(runID)-\(scenario).json")
    }
    func publish(_ status: String) -> Bool {
      do {
        let value = ["run_id": runID, "case_id": scenario, "status": status]
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
        return true
      } catch { return false }
    }
    func matches(_ status: String) -> Bool {
      do {
        let stream = try FileHandle(forReadingFrom: url)
        defer { try? stream.close() }
        let data = try stream.read(upToCount: 1025) ?? Data()
        guard data.count <= 1024 else { return false }
        let value = try JSONDecoder().decode([String: String].self, from: data)
        return value == ["run_id": runID, "case_id": scenario, "status": status]
      } catch { return false }
    }
  }
#endif
