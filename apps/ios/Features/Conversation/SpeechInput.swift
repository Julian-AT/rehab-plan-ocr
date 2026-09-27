import AVFoundation
import Foundation
import Synchronization

/// The tap only copies PCM into a bounded pool and enqueues it. Level detection,
/// conversion, VAD, pre-roll and provider input run on one dedicated serial queue.
/// Queue-owned mutable fields never cross executors; admission/pool state uses a
/// mutex. PCM is recycled only after it has left both the worker and pre-roll.
final class SpeechInput: @unchecked Sendable {
  private struct Admission {
    var pending = 0
    var closed = false
    var pool: [OwnedPCM] = []
  }
  private let admission = Mutex(Admission())
  private let queue = DispatchQueue(label: "at.rehakalender.speech-input", qos: .userInitiated)
  private let channel: SpeechInputChannel
  private var sink: (any RecognitionAudioSink)?
  private var ring: [AVAudioPCMBuffer] = []
  private var ringSeconds = 0.0
  private var pending: [AVAudioPCMBuffer]?
  private var pendingSeconds = 0.0
  private var detector: VoiceActivityDetector?
  private var activity = SpeechActivityGate()
  private var monitoring = false
  private var admittedTurn = false
  private var silence: AVAudioPCMBuffer?
  init(channel: SpeechInputChannel) { self.channel = channel }

  func monitorForInterruption() { queue.async { self.monitoring = true } }

  func beginPending(preRoll: Bool) {
    queue.async {
      guard !self.admission.withLock({ $0.closed }) else { return }
      self.monitoring = false
      self.admittedTurn = preRoll
      self.activity.beginTurn(preRoll: preRoll)
      self.pending = preRoll ? self.ring : []
      self.pendingSeconds = preRoll ? self.ringSeconds : 0
    }
  }
  func replace(_ next: (any RecognitionAudioSink)?, preRoll: Bool = false) {
    queue.async {
      guard !self.admission.withLock({ $0.closed }) else { return }
      do {
        try self.sink?.finish()
        self.sink = next
        if let next, let pending = self.pending {
          for buffer in pending { try next.append(buffer) }
          self.pending = nil
          // Pending may share immutable silence buffers. Release these refs;
          // only raw buffers leaving the pre-roll ring return to the tap pool.
          self.pendingSeconds = 0
        } else if preRoll {
          for buffer in self.ring { try next?.append(buffer) }
        }
      } catch { self.fail(error) }
    }
  }
  func append(_ buffer: AVAudioPCMBuffer) {
    let capturedAt = ProcessInfo.processInfo.systemUptime
    do {
      try InputAudioLimits.validate(buffer)
      guard buffer.frameLength > 0 else { return }
      let borrowed = try admission.withLock { state -> OwnedPCM? in
        guard !state.closed else { return nil }
        // At most 16 owned tap buffers wait for conversion. Never drop audio
        // silently: an overflow invalidates this entire turn.
        guard state.pending < 16 else { throw RecognitionFailure.overflow }
        let copy: OwnedPCM
        if let index = state.pool.firstIndex(where: {
          $0.buffer.format == buffer.format && $0.buffer.frameCapacity >= buffer.frameLength
        }) {
          copy = state.pool.remove(at: index)
        } else {
          guard
            let allocated = AVAudioPCMBuffer(
              pcmFormat: buffer.format, frameCapacity: buffer.frameLength)
          else { throw InputAudioError.conversion }
          copy = OwnedPCM(allocated)
        }
        state.pending += 1
        return copy
      }
      guard let borrowed else { return }
      let copy = borrowed.buffer
      copy.frameLength = buffer.frameLength
      for (source, destination) in zip(
        UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList),
        UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList))
      {
        guard let from = source.mData, let to = destination.mData else {
          throw InputAudioError.invalidFormat
        }
        memcpy(to, from, Int(source.mDataByteSize))
      }
      // Transfer sole ownership of this copy to the serial worker.
      let owned = OwnedPCM(copy)
      queue.async {
        defer { self.admission.withLock { $0.pending -= 1 } }
        guard !self.admission.withLock({ $0.closed }) else { return }
        self.process(owned.buffer, at: capturedAt)
      }
    } catch { fail(error) }
  }
  private func process(_ buffer: AVAudioPCMBuffer, at time: Double) {
    do {
      guard let level = try InputAudioLevel.measure(buffer) else { return }
      if let detector, detector.inputFormat != buffer.format { throw InputAudioError.invalidFormat }
      if detector == nil { detector = try VoiceActivityDetector(input: buffer.format) }
      var frames: [Bool] = []
      var interruptions: [Bool] = []
      var admit = false
      try detector?.append(buffer) {
        let decision = activity.append($0, monitoring: monitoring)
        frames.append(decision.voice)
        interruptions.append(decision.interruption)
        admit = admit || decision.admit
      }
      if !monitoring && (pending != nil || sink != nil) {
        if !admittedTurn && admit {
          admittedTurn = true
          // Recover the onset used to confirm speech, including a soft first word.
          for previous in ring { try forward(previous) }
        }
        if admittedTurn {
          // Keep the recognizer's timeline continuous after onset. Rejected
          // background must not become words or prolong the spoken request.
          try forward(admit ? buffer : silentBuffer(like: buffer))
        }
      }
      ring.append(buffer)
      ringSeconds += Double(buffer.frameLength) / buffer.format.sampleRate
      while ringSeconds > 0.4, let first = ring.first {
        ring.removeFirst()
        ringSeconds -= Double(first.frameLength) / first.format.sampleRate
        if pending?.contains(where: { $0 === first }) != true { recycle(first) }
      }
      guard
        channel.send(
          SpeechInputPacket(
            level: level, sampleRate: buffer.format.sampleRate,
            channels: Int(buffer.format.channelCount), capturedAt: time, voicedFrames: frames,
            interruptionFrames: interruptions))
      else { throw RecognitionFailure.overflow }
    } catch { fail(error) }
  }
  private func forward(_ buffer: AVAudioPCMBuffer) throws {
    if pending != nil {
      pending?.append(buffer)
      pendingSeconds += Double(buffer.frameLength) / buffer.format.sampleRate
      guard pendingSeconds <= 2 else { throw RecognitionFailure.overflow }
    } else {
      try sink?.append(buffer)
    }
  }
  private func silentBuffer(like buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
    if let silence, silence.format == buffer.format, silence.frameLength == buffer.frameLength {
      return silence
    }
    guard let result = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength)
    else { throw InputAudioError.conversion }
    result.frameLength = buffer.frameLength
    for part in UnsafeMutableAudioBufferListPointer(result.mutableAudioBufferList) {
      guard let data = part.mData else { throw InputAudioError.invalidFormat }
      memset(data, 0, Int(part.mDataByteSize))
    }
    silence = result  // Immutable, including while retained by pending input.
    return result
  }
  private func recycle(_ buffer: AVAudioPCMBuffer) {
    admission.withLock { if $0.pool.count < 24 { $0.pool.append(OwnedPCM(buffer)) } }
  }
  private func fail(_ error: Error) {
    admission.withLock {
      $0.closed = true
      $0.pool = []
    }
    channel.finish(throwing: error)
  }
  func cancel() {
    admission.withLock {
      $0.closed = true
      $0.pool = []
    }
    channel.finish()
    queue.async {
      self.sink = nil
      self.ring = []
      self.pending = nil
      self.detector = nil
    }
  }
}

/// Ownership transfer only: after init the tap never touches the buffer again.
private struct OwnedPCM: @unchecked Sendable {
  let buffer: AVAudioPCMBuffer
  init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }
}
