import Foundation

#if DEBUG && REHA_CUSTOM_ASSISTANT_TRIAL
  import CryptoKit
  import LocalAssistant
#endif

@MainActor enum AssistantProviderSelection {
  static func make(arguments: [String] = ProcessInfo.processInfo.arguments)
    -> any InterpretationProvider
  {
    #if DEBUG && REHA_CUSTOM_ASSISTANT_TRIAL
      if arguments.contains("--assistant-model-trial") { return nativeTrial() }
    #endif
    return CalendarUnderstandingSession()
  }

  #if DEBUG && REHA_CUSTOM_ASSISTANT_TRIAL
    private struct TrialManifest: Decodable {
      let schemaVersion: Int
      let qualified: Bool
      let modelID: String
      let modelSHA256: String
      let modelBytes: Int64
      let promptSHA256: String
      let nativeIdentity: String
      enum CodingKeys: String, CodingKey {
        case qualified
        case schemaVersion = "schema_version"
        case modelID = "model_id"
        case modelSHA256 = "model_sha256"
        case modelBytes = "model_bytes"
        case promptSHA256 = "prompt_sha256"
        case nativeIdentity = "native_identity"
      }
    }
    private static func nativeTrial() -> any InterpretationProvider {
      let unavailable = "Das lokale Testmodell ist nicht vollständig verfügbar."
      do {
        guard let folder = Bundle.main.resourceURL?.appendingPathComponent("assistant-trial"),
          let promptURL = Bundle.main.url(forResource: "assistant-system-v1", withExtension: "txt")
        else { throw InterpretationError.unavailable(unavailable) }
        let manifest = try JSONDecoder().decode(
          TrialManifest.self,
          from: Data(contentsOf: folder.appendingPathComponent("manifest.json")))
        let promptData = try Data(contentsOf: promptURL)
        let promptDigest = SHA256.hash(data: promptData).map { String(format: "%02x", $0) }.joined()
        guard manifest.schemaVersion == 1, !manifest.qualified,
          !manifest.modelID.isEmpty, manifest.modelID.utf8.count <= 128,
          manifest.nativeIdentity.count == 64,
          manifest.nativeIdentity.allSatisfy({ $0.isHexDigit && !$0.isUppercase }),
          promptDigest == manifest.promptSHA256,
          let system = String(data: promptData, encoding: .utf8)
        else { throw InterpretationError.invalidRequest }
        let modelURL = folder.appendingPathComponent("assistant.gguf")
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
          throw InterpretationError.unavailable(unavailable)
        }
        let runtime = LocalAssistant(
          asset: LocalAssistantAsset(
            url: modelURL,
            sha256: manifest.modelSHA256, bytes: manifest.modelBytes))
        return CustomAssistantProvider(
          identity: InterpretationIdentity(
            provider: "custom-qwen-trial",
            model: "\(manifest.modelID)/\(manifest.modelSHA256)/\(manifest.nativeIdentity)",
            schemaVersion: 1), system: system,
          onDiscard: { Task { await runtime.unload() } },
          generate: { prompt, deadline in
            do {
              return try await runtime.generate(prompt: prompt, deadline: deadline)
            } catch LocalAssistantError.contextLimit {
              throw InterpretationError.contextTooLarge
            } catch LocalAssistantError.deadline { throw InterpretationError.deadlineExceeded }
          })
      } catch {
        return CustomAssistantProvider(
          identity: InterpretationIdentity(
            provider: "custom-qwen-trial", model: "unavailable", schemaVersion: 1), system: "",
          availability: .unavailable(unavailable)
        ) { _, _ in throw InterpretationError.unavailable(unavailable) }
      }
    }
  #endif
}
