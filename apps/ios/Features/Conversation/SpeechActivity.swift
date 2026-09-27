import Foundation

/// One 20 ms observation from the processed microphone, before UI level scaling.
struct SpeechActivityFrame: Sendable {
  let speech: Bool
  let rms: Double
}

/// Energy complements WebRTC's speech decision; neither identifies a speaker.
/// Learn only while listening, so Victoria cannot raise the user's reference.
struct SpeechActivityGate {
  private var noise = 0.0005
  private var speaker: Double?
  private var onset: [Bool] = []
  private var tail = 0
  private(set) var open = false

  mutating func beginTurn(preRoll: Bool) {
    onset = []
    tail = preRoll ? 15 : 0
    open = preRoll
  }

  mutating func append(_ frame: SpeechActivityFrame, monitoring: Bool)
    -> (voice: Bool, interruption: Bool, admit: Bool)
  {
    guard frame.rms.isFinite, frame.rms >= 0 else { return (false, false, false) }
    if !frame.speech {
      // Slow, bounded adaptation must not turn one impact into a new noise floor.
      noise += (min(frame.rms, noise * 2) - noise) * 0.02
      noise = min(0.004, max(0.0001, noise))
    }
    let floor = max(0.003, noise * 2.5)
    let voice = frame.speech && frame.rms >= floor
    let interruption =
      voice && frame.rms >= max(floor, min(0.025, max(0.006, (speaker ?? 0) * 0.25)))
    onset.append(voice)
    if onset.count > 5 { onset.removeFirst() }
    if onset.filter({ $0 }).count >= 3 { open = true }
    if voice {
      tail = 15  // Preserve soft consonants and word endings for 300 ms.
      if open && !monitoring {
        speaker = speaker.map { $0 + (frame.rms - $0) * 0.04 } ?? frame.rms
      }
    } else {
      tail = max(0, tail - 1)
    }
    return (voice, interruption, open && (voice || tail > 0))
  }
}
