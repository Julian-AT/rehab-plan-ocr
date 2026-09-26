import Foundation

/// The pending operation travels with its interaction state. Returning to the
/// action prompt always drops it, including after a negation or a new question.
enum ConversationState {
  enum Question { case action, event, title, date, time, duration, confirmation }
  case idle
  case resolving(VoiceIntent)
  case collecting(VoiceIntent, Question)
  case confirming(VoiceIntent)

  func rejectsPendingChange(_ text: String) -> Bool {
    guard [.create, .update, .remove].contains(intent.action) else { return false }
    return ["nein", "nein danke", "doch nicht", "bitte nicht", "lieber nicht"]
      .contains(VoiceRules.normalized(text).trimmingCharacters(in: .punctuationCharacters))
  }

  var question: Question {
    switch self {
    case .idle, .resolving: .action
    case .collecting(_, let question): question
    case .confirming: .confirmation
    }
  }
  var intent: VoiceIntent {
    get {
      switch self {
      case .idle: VoiceIntent()
      case .resolving(let intent), .collecting(let intent, _), .confirming(let intent): intent
      }
    }
    set {
      switch self {
      case .idle, .resolving: self = newValue.action == .unsupported ? .idle : .resolving(newValue)
      case .collecting(_, let question): self = .collecting(newValue, question)
      case .confirming: self = .confirming(newValue)
      }
    }
  }
  mutating func ask(_ question: Question) {
    switch question {
    case .action: self = .idle
    case .confirmation: self = .confirming(intent)
    default: self = .collecting(intent, question)
    }
  }
}
