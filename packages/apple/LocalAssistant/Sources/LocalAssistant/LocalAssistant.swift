import CryptoKit
import Foundation
import RehaAssistantNative

public struct LocalAssistantAsset: Sendable {
  public let url: URL
  public let sha256: String
  public let bytes: Int64

  public init(url: URL, sha256: String, bytes: Int64) {
    self.url = url
    self.sha256 = sha256
    self.bytes = bytes
  }
}

public enum LocalAssistantError: Error, Equatable, Sendable {
  case invalidRequest, unavailable, assetMismatch, contextLimit, deadline, outputLimit, busy
  case nativeFailure(Int32)
}

/// The serial queue owns all model access. An operation's independent atomic
/// cancellation flag may be set on any thread; its owner outlives native work.
public final class LocalAssistant: @unchecked Sendable {
  private let asset: LocalAssistantAsset
  private let queue = DispatchQueue(label: "at.rehakalender.assistant", qos: .userInitiated)
  private var model: OpaquePointer?

  public init(asset: LocalAssistantAsset) { self.asset = asset }

  deinit {
    // Queued/running operations capture self, so the final owner can only disappear
    // after they finish. The C model is never freed during generation.
    if let model { reha_assistant_model_free(model) }
  }

  public func generate(
    prompt: String, maximumTokens: UInt32 = 192,
    deadline: ContinuousClock.Instant
  ) async throws -> String {
    guard !prompt.isEmpty, prompt.utf8.count <= 131_072, (1...192).contains(maximumTokens) else {
      throw LocalAssistantError.invalidRequest
    }
    let remaining = ContinuousClock.now.duration(to: deadline)
    guard remaining > .zero else { throw LocalAssistantError.deadline }
    guard remaining <= .seconds(120) else { throw LocalAssistantError.invalidRequest }
    let milliseconds =
      remaining.components.seconds * 1_000
      + (remaining.components.attoseconds + 999_999_999_999_999) / 1_000_000_000_000_000
    guard milliseconds > 0, milliseconds <= 120_000 else {
      throw LocalAssistantError.invalidRequest
    }
    let operation = try Operation(timeout: UInt32(milliseconds))
    return try await withTaskCancellationHandler {
      try Task.checkCancellation()
      let value: String = try await withCheckedThrowingContinuation { continuation in
        queue.async { [self, operation] in
          do {
            try load(operation)
            var output = [CChar](repeating: 0, count: 8_193)
            var count = 0
            let status = prompt.withCString { text in
              reha_assistant_generate(
                model, operation.pointer, text, prompt.utf8.count,
                maximumTokens, &output, output.count, &count)
            }
            try check(status)
            let data = output.prefix(count).map { UInt8(bitPattern: $0) }
            guard let value = String(bytes: data, encoding: .utf8), !value.isEmpty else {
              throw LocalAssistantError.nativeFailure(-1)
            }
            continuation.resume(returning: value)
          } catch { continuation.resume(throwing: error) }
        }
      }
      try Task.checkCancellation()
      guard ContinuousClock.now < deadline else { throw LocalAssistantError.deadline }
      return value
    } onCancel: {
      operation.cancel()
    }
  }

  /// Reuse the immutable model only. Every C generation creates fresh KV/sampler state.
  private func load(_ operation: Operation) throws {
    try check(reha_assistant_operation_status(operation.pointer))
    guard model == nil else { return }
    guard asset.url.isFileURL, asset.bytes > 0, asset.bytes <= 2_147_483_648,
      asset.sha256.count == 64, asset.sha256.allSatisfy({ $0.isHexDigit && !$0.isUppercase })
    else { throw LocalAssistantError.assetMismatch }
    let attributes = try FileManager.default.attributesOfItem(atPath: asset.url.path)
    guard attributes[.type] as? FileAttributeType == .typeRegular,
      (attributes[.size] as? NSNumber)?.int64Value == asset.bytes
    else { throw LocalAssistantError.assetMismatch }
    let source = try FileHandle(forReadingFrom: asset.url)
    defer { try? source.close() }
    var digest = SHA256()
    var count: Int64 = 0
    while let data = try source.read(upToCount: 4_194_304), !data.isEmpty {
      try check(reha_assistant_operation_status(operation.pointer))
      count += Int64(data.count)
      guard count <= asset.bytes else { throw LocalAssistantError.assetMismatch }
      digest.update(data: data)
    }
    let actual = digest.finalize().map { String(format: "%02x", $0) }.joined()
    guard count == asset.bytes, actual == asset.sha256 else {
      throw LocalAssistantError.assetMismatch
    }
    var status = REHA_ASSISTANT_OK
    let loaded = asset.url.path.withCString { reha_assistant_load($0, operation.pointer, &status) }
    try check(status)
    guard let loaded else { throw LocalAssistantError.unavailable }
    model = loaded
  }

  private func check(_ status: reha_assistant_status) throws {
    switch status {
    case REHA_ASSISTANT_OK: return
    case REHA_ASSISTANT_CANCELLED: throw CancellationError()
    case REHA_ASSISTANT_DEADLINE: throw LocalAssistantError.deadline
    case REHA_ASSISTANT_CONTEXT_LIMIT: throw LocalAssistantError.contextLimit
    case REHA_ASSISTANT_OUTPUT_LIMIT: throw LocalAssistantError.outputLimit
    case REHA_ASSISTANT_BUSY: throw LocalAssistantError.busy
    case REHA_ASSISTANT_INVALID_INPUT: throw LocalAssistantError.invalidRequest
    default: throw LocalAssistantError.nativeFailure(Int32(status.rawValue))
    }
  }
}

private final class Operation: @unchecked Sendable {
  let pointer: OpaquePointer
  init(timeout: UInt32) throws {
    guard let pointer = reha_assistant_operation_create(timeout) else {
      throw LocalAssistantError.invalidRequest
    }
    self.pointer = pointer
  }
  func cancel() { reha_assistant_operation_cancel(pointer) }
  deinit { reha_assistant_operation_free(pointer) }
}
