import Foundation

/// The generator closure is the sole native inference call. It must map a token
/// context limit to contextTooLarge; no alternate provider is selected on failure.
@MainActor final class CustomAssistantProvider: InterpretationProvider {
  typealias Generate = @MainActor @Sendable (String, ContinuousClock.Instant) async throws -> String
  let identity: InterpretationIdentity
  let capabilities: Set<InterpretationCapability> = [.calendar, .mutation, .appHelp]
  let availability: InterpretationAvailability
  private let system: String
  private let generate: Generate
  private let onDiscard: @MainActor () -> Void

  init(
    identity: InterpretationIdentity, system: String,
    availability: InterpretationAvailability = .available,
    onDiscard: @escaping @MainActor () -> Void = {}, generate: @escaping Generate
  ) {
    self.identity = identity
    self.system = system
    self.availability = availability
    self.generate = generate
    self.onDiscard = onDiscard
  }

  func discard() { onDiscard() }

  func interpret(_ request: InterpretationRequest) async throws -> ConversationInterpretation {
    try request.validate()
    if case .unavailable(let reason) = availability {
      throw InterpretationError.unavailable(reason)
    }
    let prompt = try AssistantPrompt(request: request, system: system)
    var prior = request.history
    while true {
      try Task.checkCancellation()
      guard ContinuousClock.now < request.deadline else {
        throw InterpretationError.deadlineExceeded
      }
      do {
        let output = try await generate(prompt.render(history: prior), request.deadline)
        try Task.checkCancellation()
        guard ContinuousClock.now < request.deadline else {
          throw InterpretationError.deadlineExceeded
        }
        return try AssistantInterpretation.decode(
          output, references: prompt.references, timezone: prompt.timezone)
      } catch InterpretationError.contextTooLarge {
        guard !prior.isEmpty else { throw InterpretationError.contextTooLarge }
        prior.removeFirst()
      }
    }
  }
}
