import Foundation

@main struct SpeechActivityProbe {
  static func main() {
    var gate = SpeechActivityGate()
    gate.beginTurn(preRoll: false)
    for _ in 0..<500 {
      let result = gate.append(.init(speech: true, rms: 0.002), monitoring: false)
      precondition(!result.voice && !result.interruption && !result.admit)
    }
    // Two isolated frames cannot acquire a request.
    for _ in 0..<2 {
      precondition(!gate.append(.init(speech: true, rms: 0.02), monitoring: false).admit)
    }
    for _ in 0..<10 { _ = gate.append(.init(speech: false, rms: 0), monitoring: false) }
    // Quiet speech still starts a turn; first syllables come from PCM pre-roll.
    for index in 0..<3 {
      let result = gate.append(.init(speech: true, rms: 0.004), monitoring: false)
      precondition(result.voice && !result.interruption && result.admit == (index == 2))
    }
    for _ in 0..<14 {
      precondition(gate.append(.init(speech: false, rms: 0), monitoring: false).admit)
    }
    precondition(!gate.append(.init(speech: false, rms: 0), monitoring: false).admit)
    // Learn the user's level, then reject quieter background speech as barge-in.
    for _ in 0..<150 { _ = gate.append(.init(speech: true, rms: 0.08), monitoring: false) }
    for _ in 0..<300 {
      precondition(!gate.append(.init(speech: true, rms: 0.012), monitoring: true).interruption)
    }
    precondition(gate.append(.init(speech: true, rms: 0.04), monitoring: true).interruption)
    gate.beginTurn(preRoll: true)
    precondition(gate.append(.init(speech: false, rms: 0), monitoring: false).admit)
    // Speaking softly after a louder answer remains possible in a normal turn.
    precondition(gate.append(.init(speech: true, rms: 0.004), monitoring: false).voice)
    precondition(!gate.append(.init(speech: true, rms: .nan), monitoring: false).admit)
    print(
      "Speech admission: low background, onset confirmation, quiet speech, tails, learned interruption floor, pre-roll and invalid energy passed (synthetic policy checks)"
    )
  }
}
