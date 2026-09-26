import Foundation

@main struct ConversationStateProbe {
  static func main() {
    var state = ConversationState.idle
    var change = VoiceIntent()
    change.action = .remove
    change.referenceText = "Erfundener Termin"
    state.intent = change
    state.ask(.event)
    precondition(state.intent.action == .remove && state.question == .event)
    state.ask(.confirmation)
    precondition(state.intent.action == .remove && state.question == .confirmation)
    state.ask(.action)  // Negation, cancellation, unrelated question or completion.
    precondition(state.intent.action == .unsupported && state.intent.referenceText.isEmpty)
    state.intent.action = .create
    state.ask(.title)
    state.intent.title = "Kontrolle"
    precondition(state.intent.action == .create && state.intent.title == "Kontrolle")
    state.ask(.action)
    state.intent.action = .update
    precondition(state.intent.title == nil && state.intent.referenceText.isEmpty)
    print("Conversation states: cancellation, negation, subject change and fresh mutation passed")
  }
}
