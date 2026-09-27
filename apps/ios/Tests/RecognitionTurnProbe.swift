import AVFoundation
import Foundation
import Synchronization

private final class RecordingSink: RecognitionAudioSink, Sendable {
  let observations = Mutex([Int]())
  let energies = Mutex([Double]())
  func append(_ buffer: AVAudioPCMBuffer) throws {
    observations.withLock { $0.append(Int(buffer.frameLength)) }
    let values = buffer.floatChannelData![0]
    energies.withLock {
      $0.append((0..<Int(buffer.frameLength)).reduce(0.0) { $0 + abs(Double(values[$1])) })
    }
  }
  func finish() throws { observations.withLock { $0.append(-1) } }
}

@main struct RecognitionTurnProbe {
  static func main() async throws {
    for _ in 0..<100 {
      var transcript = RecognitionTranscript()
      try transcript.receive("morgen um neun", start: 0, end: 1, final: false)
      precondition(transcript.completion == .failed(.incomplete))
      try transcript.receive("morgen um zehn", start: 0, end: 1.2, final: true)
      precondition(transcript.completion == .finalized("morgen um zehn"))
      try transcript.receive("im Raum", start: 1.2, end: 2, final: false)
      precondition(transcript.text == "morgen um zehn im Raum")
      precondition(
        transcript.completion == .failed(.incomplete), "Stable prefix hid unfinished suffix")
      try transcript.receive("im Raum 2.14", start: 1.2, end: 2.4, final: true)
      precondition(transcript.completion == .finalized("morgen um zehn im Raum 2.14"))
      do {
        try transcript.receive("duplicate", start: 0, end: 1, final: true)
        preconditionFailure("Overlapping final range was duplicated")
      } catch RecognitionFailure.incomplete {}
    }
    precondition(RecognitionTranscript().completion == .noSpeech)
    var progress = RecognitionProgress()
    precondition(!progress.stalled(at: 1000), "Silence is not a stuck recognizer")
    for _ in 0..<25 { progress.voice(at: 10) }
    precondition(!progress.stalled(at: 21.9))
    precondition(progress.stalled(at: 22))
    progress.result(at: 20)
    precondition(!progress.stalled(at: 25))
    precondition(progress.stalled(at: 32))

    let channel = SpeechInputChannel()
    let input = SpeechInput(channel: channel)
    let sink = RecordingSink()
    input.replace(sink)
    let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 320)!
    buffer.frameLength = 320
    buffer.floatChannelData![0].initialize(repeating: 0, count: 320)
    input.append(buffer)
    // Mutating the tap buffer after append cannot mutate the queued copy.
    buffer.floatChannelData![0].initialize(repeating: .nan, count: 320)
    var iterator = channel.stream.makeAsyncIterator()
    let packet = try await iterator.next()!
    precondition(packet.level == 0)
    precondition(sink.observations.withLock { $0.isEmpty }, "Unadmitted silence reached ASR")
    input.replace(nil)
    for _ in 0..<100 where sink.observations.withLock({ $0.last != -1 }) {
      try await Task.sleep(for: .milliseconds(2))
    }
    precondition(sink.observations.withLock { $0 == [-1] }, "Finish overtook queued audio")
    let second = RecordingSink()
    input.beginPending(preRoll: true)
    input.replace(second, preRoll: true)
    for _ in 0..<100 where second.observations.withLock({ $0.isEmpty }) {
      try await Task.sleep(for: .milliseconds(2))
    }
    precondition(second.observations.withLock { $0 == [320] }, "Pre-roll was lost or overwritten")
    // After a confirmed onset, low background becomes equal-duration silence,
    // while the original PCM remains intact in the interruption pre-roll.
    for _ in 0..<30 {
      buffer.floatChannelData![0].initialize(repeating: 0.001, count: 320)
      input.append(buffer)
      _ = try await iterator.next()
    }
    precondition(second.observations.withLock { $0.count == 31 && $0.allSatisfy { $0 == 320 } })
    precondition(second.energies.withLock { $0.last == 0 }, "Rejected background reached ASR")
    input.monitorForInterruption()
    input.append(buffer)
    _ = try await iterator.next()
    precondition(second.observations.withLock { $0.count == 31 }, "Monitoring fed the old request")
    let third = RecordingSink()
    input.beginPending(preRoll: true)
    input.replace(third, preRoll: true)
    for _ in 0..<100 where third.observations.withLock({ $0.isEmpty }) {
      try await Task.sleep(for: .milliseconds(2))
    }
    precondition(
      third.energies.withLock { !$0.isEmpty && $0.allSatisfy { $0 > 0 } },
      "Admission mutated pre-roll")
    input.cancel()
    do {
      try channel.checkActive()
      preconditionFailure("Cancelled audio stayed active")
    } catch is CancellationError {}
    print(
      "Recognition: 100 synthetic final/provisional cycles, overlapping ranges, stalled progress, PCM ownership, ordered finish, pre-roll and cancellation passed (no real speech qualification)"
    )
  }
}
