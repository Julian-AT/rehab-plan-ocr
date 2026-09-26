import Foundation

#if canImport(LocalAssistant)
  import LocalAssistant
#endif
#if canImport(UIKit)
  import UIKit
#endif

private struct ProbeInput: Decodable {
  struct Model: Decodable {
    var path: String
    var sha256: String
    var bytes: Int64
  }
  struct Case: Decodable {
    var id: String
    var prompt: String
  }
  var runID: String
  var model: Model
  var cases: [Case]
}

@MainActor private func execute(inputURL: URL, resultURL: URL, bundled: Bool) async {
  var report: [String: Any] = ["stage": "starting", "qualified": false]
  func save() throws {
    try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
      .write(to: resultURL, options: .atomic)
  }
  do {
    let input = try JSONDecoder().decode(ProbeInput.self, from: Data(contentsOf: inputURL))
    report["run_id"] = input.runID
    report["model_sha256"] = input.model.sha256
    report["stage"] = "loading"
    try save()
    let modelURL =
      bundled
      ? inputURL.deletingLastPathComponent().appendingPathComponent("assistant.gguf")
      : URL(fileURLWithPath: input.model.path)
    let assistant = LocalAssistant(
      asset: LocalAssistantAsset(
        url: modelURL, sha256: input.model.sha256, bytes: input.model.bytes))
    guard !input.cases.isEmpty else { throw LocalAssistantError.invalidRequest }
    var cases: [[String: Any]] = []
    for test in input.cases {
      report["stage"] = "generating"
      report["case_id"] = test.id
      try save()
      let output = try await assistant.generate(prompt: test.prompt, deadline: .now + .seconds(120))
      cases.append(["id": test.id, "output": output])
      report["cases"] = cases
      try save()
    }
    let prompt = input.cases[0].prompt
    report["stage"] = "cancellation"
    try save()
    let cancelled = Task {
      try await assistant.generate(prompt: prompt, deadline: .now + .seconds(120))
    }
    try await Task.sleep(for: .milliseconds(25))
    cancelled.cancel()
    do {
      _ = try await cancelled.value
      throw ProbeError.failed("Canceled generation returned output")
    } catch is CancellationError { report["cancellation_passed"] = true }
    report["stage"] = "deadline"
    try save()
    do {
      _ = try await assistant.generate(prompt: prompt, deadline: .now + .milliseconds(1))
      throw ProbeError.failed("Expired generation returned output")
    } catch LocalAssistantError.deadline { report["deadline_passed"] = true }
    do {
      _ = try await assistant.generate(
        prompt: String(repeating: "Termin ", count: 5_000), deadline: .now + .seconds(120))
      throw ProbeError.failed("Oversized token context was accepted")
    } catch LocalAssistantError.contextLimit { report["context_limit_passed"] = true }
    do {
      _ = try await assistant.generate(
        prompt: prompt, maximumTokens: 1, deadline: .now + .seconds(120))
      throw ProbeError.failed("Truncated output was accepted")
    } catch LocalAssistantError.outputLimit { report["output_limit_passed"] = true }
    report["stage"] = "after_cancellation"
    try save()
    let repeated = try await assistant.generate(prompt: prompt, deadline: .now + .seconds(120))
    guard repeated == cases[0]["output"] as? String else {
      throw ProbeError.failed("Abandoned requests changed the later answer")
    }
    report["state_isolation_passed"] = true
    report["stage"] = "passed"
    try save()
  } catch {
    report["stage"] = "failed"
    report["error"] = String(describing: error)
    try? save()
  }
}

private enum ProbeError: Error { case failed(String) }

#if canImport(UIKit)
  @main @MainActor final class AssistantProbeApp: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(
      _ application: UIApplication,
      didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
      let window = UIWindow(frame: UIScreen.main.bounds)
      window.rootViewController = UIViewController()
      self.window = window
      window.makeKeyAndVisible()
      Task {
        guard let input = Bundle.main.url(forResource: "input", withExtension: "json") else {
          return
        }
        let output = URL.documentsDirectory.appendingPathComponent("assistant-result.json")
        await execute(inputURL: input, resultURL: output, bundled: true)
      }
      return true
    }
  }
#else
  @main struct AssistantHostProbe {
    static func main() async {
      guard CommandLine.arguments.count == 3 else { return }
      await execute(
        inputURL: URL(fileURLWithPath: CommandLine.arguments[1]),
        resultURL: URL(fileURLWithPath: CommandLine.arguments[2]), bundled: false)
    }
  }
#endif
