import Foundation

@main struct SpeechInputChannelProbe {
  enum FixtureError: Error { case conversion }

  static func packet(_ index: Int, frames: [Bool] = []) -> SpeechInputPacket {
    SpeechInputPacket(
      level: 0.5, sampleRate: 48_000, channels: 1, capturedAt: Double(index), voicedFrames: frames)
  }

  static func main() async throws {
    let channel = SpeechInputChannel(capacity: 256)
    let producer = Task.detached {
      for index in 0..<128 {
        precondition(channel.send(packet(index, frames: [index.isMultiple(of: 2)])))
        await Task.yield()
      }
    }
    var iterator = channel.stream.makeAsyncIterator()
    for expected in 0..<128 {
      let value = try await iterator.next()!
      try channel.checkActive()
      precondition(value.capturedAt == Double(expected), "Audio observations reordered")
      precondition(value.voicedFrames == [expected.isMultiple(of: 2)])
    }
    await producer.value
    channel.finish()
    precondition(!channel.send(packet(129)))
    do {
      try channel.checkActive()
      preconditionFailure("Finished input still active")
    } catch is CancellationError {}

    let bounded = SpeechInputChannel(capacity: 2)
    precondition(bounded.send(packet(0)))
    precondition(bounded.send(packet(1)))
    precondition(!bounded.send(packet(2)))
    var queued = bounded.stream.makeAsyncIterator()
    _ = try await queued.next()  // An older queued observation must not cause an endpoint.
    do {
      try bounded.checkActive()
      preconditionFailure("Overflow allowed stale endpoint processing")
    } catch SpeechInputChannel.Failure.overflow {}
    precondition(!bounded.send(packet(3)))

    let failed = SpeechInputChannel()
    precondition(failed.send(packet(0)))
    failed.finish(throwing: FixtureError.conversion)
    do {
      try failed.checkActive()
      preconditionFailure("Queued packet masked a conversion failure")
    } catch FixtureError.conversion {}

    let canceled = SpeechInputChannel()
    let consumer = Task {
      var iterator = canceled.stream.makeAsyncIterator()
      _ = try? await iterator.next()
    }
    consumer.cancel()
    await consumer.value
    precondition(!canceled.send(packet(0)), "Cancellation did not terminate delivery")

    let invalid = SpeechInputChannel()
    precondition(!invalid.send(packet(0, frames: Array(repeating: false, count: 65))))
    do {
      try invalid.checkActive()
      preconditionFailure("Oversized observation packet accepted")
    } catch SpeechInputChannel.Failure.invalidPacket {}

    try await preservesPauses(
      transcript: "Wann ist mein Termin", pauseFrames: 59, endpointFrames: 60)
    try await preservesPauses(
      transcript: "Verschiebe ihn um", pauseFrames: 124, endpointFrames: 125)
    var meter = InputLevelPublication()
    precondition(abs(meter.receive(1, at: 0)! - 0.4) < 1e-12)
    precondition(meter.receive(1, at: 0.02) == nil)
    precondition(meter.receive(1, at: 0.04) == nil)
    precondition(abs(meter.receive(1, at: 0.06)! - 0.8704) < 1e-12)
    precondition(meter.receive(.nan, at: 0.2) == nil)
    meter = InputLevelPublication()
    var publications = 0
    for index in 0..<100 {
      if meter.receive(0.5, at: Double(index) / 100) != nil { publications += 1 }
    }
    precondition((16...20).contains(publications), "Waveform publication was not bounded")
    print(
      "Speech input: ordered delivery, bounded overflow, cancellation, conversion failure, full pause evidence and 20 Hz level publication passed"
    )
  }

  static func preservesPauses(transcript: String, pauseFrames: Int, endpointFrames: Int)
    async throws
  {
    let frames =
      Array(repeating: true, count: 6)
      + Array(repeating: false, count: pauseFrames)
      + Array(repeating: true, count: 6)
      + Array(repeating: false, count: endpointFrames)
    let input = SpeechInputChannel()
    let chunks = stride(from: 0, to: frames.count, by: 10).map {
      Array(frames[$0..<min($0 + 10, frames.count)])
    }
    for (index, chunk) in chunks.enumerated() {
      precondition(input.send(packet(index, frames: chunk)))
    }
    var endpoint = SpeechEndpoint()
    var iterator = input.stream.makeAsyncIterator()
    var processed = 0
    for _ in chunks {
      let packet = try await iterator.next()!
      try input.checkActive()
      for voice in packet.voicedFrames {
        processed += 1
        let ended = endpoint.append(voice: voice, transcript: transcript)
        precondition(
          ended == (processed == frames.count), "Pause was shortened or evidence dropped")
      }
    }
    input.finish()
  }
}
