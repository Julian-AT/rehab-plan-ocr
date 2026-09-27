import Foundation
import Synchronization

/// Only scalar observations cross from the audio tap; PCM stays with SpeechInput.
struct SpeechInputPacket: Sendable {
  let level: Double
  let sampleRate: Double
  let channels: Int
  let capturedAt: Double
  let voicedFrames: [Bool]
  var interruptionFrames: [Bool] = []
}

/// One consumer preserves tap order. An overflow invalidates queued observations
/// before they can finalize an incomplete request; audio is never silently skipped.
final class SpeechInputChannel: Sendable {
  enum Failure: Error { case overflow, invalidPacket }
  private struct State {
    var closed = false
    var failure: (any Error)?
  }
  let stream: AsyncThrowingStream<SpeechInputPacket, Error>
  private let continuation: AsyncThrowingStream<SpeechInputPacket, Error>.Continuation
  private let state = Mutex(State())

  init(capacity: Int = 64) {
    precondition(capacity > 0)
    (stream, continuation) = AsyncThrowingStream.makeStream(
      bufferingPolicy: .bufferingOldest(capacity))
  }

  @discardableResult func send(_ packet: SpeechInputPacket) -> Bool {
    state.withLock { state in
      guard !state.closed else { return false }
      guard packet.level.isFinite, (0...1).contains(packet.level),
        packet.sampleRate.isFinite, packet.sampleRate > 0, packet.channels > 0,
        packet.capturedAt.isFinite, packet.voicedFrames.count <= 64,
        packet.interruptionFrames.isEmpty
          || packet.interruptionFrames.count == packet.voicedFrames.count
      else {
        state.closed = true
        state.failure = Failure.invalidPacket
        continuation.finish(throwing: Failure.invalidPacket)
        return false
      }
      switch continuation.yield(packet) {
      case .enqueued: return true
      case .dropped:
        state.closed = true
        state.failure = Failure.overflow
        continuation.finish(throwing: Failure.overflow)
        return false
      case .terminated:
        state.closed = true
        return false
      @unknown default:
        state.closed = true
        state.failure = Failure.overflow
        continuation.finish(throwing: Failure.overflow)
        return false
      }
    }
  }

  /// Check before consuming a packet, even if it preceded an overflow in the queue.
  func checkActive() throws {
    try state.withLock { state in
      if let failure = state.failure { throw failure }
      if state.closed { throw CancellationError() }
    }
  }

  func finish(throwing error: Error? = nil) {
    state.withLock {
      $0.closed = true
      if $0.failure == nil { $0.failure = error }
    }
    continuation.finish(throwing: error)
  }
}

/// Preserve per-buffer smoothing while publishing at most 20 updates per second.
/// The first valid observation is immediate; VAD and watchdogs are not throttled.
struct InputLevelPublication {
  private var smoothed = 0.0
  private var publishedAt: Double?
  mutating func receive(_ level: Double, at time: Double) -> Double? {
    guard level.isFinite, time.isFinite else { return nil }
    smoothed += (min(1, max(0, level)) - smoothed) * 0.4
    if let publishedAt, time >= publishedAt, time - publishedAt < 0.05 { return nil }
    publishedAt = time
    return smoothed
  }
}
