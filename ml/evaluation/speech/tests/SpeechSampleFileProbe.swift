import Foundation

@main struct SpeechSampleFileProbe {
  static func main() throws {
    let output = URL(fileURLWithPath: CommandLine.arguments[1])
    let pcm = SpeechPCM(samples: [-2, -1, -0.5, 0, 0.5, 1, 2])
    try SpeechSampleFile.wav(pcm).write(to: output)
    for samples: [Float] in [[], [.nan], [.infinity], [-.infinity]] {
      do {
        _ = try SpeechSampleFile.wav(SpeechPCM(samples: samples))
        fatalError("Invalid PCM was exported")
      } catch SpeechPCMError.invalidFile {}
    }
    do {
      _ = try SpeechSampleFile.wav(
        SpeechPCM(samples: Array(repeating: 0, count: SpeechPCM.maximumFrames + 1)))
      fatalError("Overlong PCM was exported")
    } catch SpeechPCMError.invalidFile {}
  }
}
