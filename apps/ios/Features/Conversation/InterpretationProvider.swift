import Foundation
import RehaCore

struct InterpretationIdentity: Equatable, Sendable {
  let provider: String
  let model: String
  let schemaVersion: Int
}

enum InterpretationCapability: Hashable, Sendable {
  case calendar, mutation, conversation, appHelp
}

enum InterpretationAvailability: Equatable, Sendable {
  case available
  case unavailable(String)
}

struct InterpretationRequest: Sendable {
  let text: String
  let context: String
  let history: [[String: String]]
  let now: Date
  let calendar: Calendar
  let deadline: ContinuousClock.Instant

  init(
    text: String, context: String, history: [[String: String]], now: Date,
    calendar: Calendar = .current, deadline: ContinuousClock.Instant
  ) {
    self.text = text
    self.context = context
    self.history = history
    self.now = now
    self.calendar = calendar
    self.deadline = deadline
  }

  func validate() throws {
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      text.utf8.count <= 8_192, context.utf8.count <= 65_536,
      history.count <= 6,
      history.reduce(0, { $0 + $1.values.reduce(0, { $0 + $1.utf8.count }) }) <= 65_536
    else { throw InterpretationError.invalidRequest }
  }
}

/// Provider-neutral interpretation. Calendar facts and mutation execution stay downstream.
struct ConversationInterpretation: Sendable {
  enum Action: Sendable {
    case calendar, create, update, remove, cancel, help, conversation, clarify
  }
  var action: Action
  var query: CalendarQuestion?
  var change: VoiceIntent?
  var reply: String?
  var helpTopic: AssistantHelpTopic?
  var problem: AssistantProblem?

  func validate() throws {
    guard action == .help || helpTopic == nil, action == .clarify || problem == nil else {
      throw InterpretationError.invalidRequest
    }
    if let query {
      guard query.validTimeBounds, (1...90).contains(query.days),
        (0...5).contains(query.ordinal), (0...500).contains(query.offset),
        query.title.count <= 160, query.excluding.count <= 160
      else { throw InterpretationError.invalidRequest }
    }
    if let change {
      guard TimeZone(identifier: change.timezone) != nil,
        change.newTime.map({ (0..<1440).contains($0) }) ?? true,
        change.duration.map({ (1...1440).contains($0) }) ?? true,
        change.title.map({
          !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 200
        }) ?? true
      else { throw InterpretationError.invalidRequest }
    }
    let valid: Bool =
      switch action {
      case .calendar: query != nil && change == nil && reply == nil
      case .create: query == nil && reply == nil && (change == nil || change?.action == .create)
      case .update: query != nil && reply == nil && (change == nil || change?.action == .update)
      case .remove: query != nil && change == nil && reply == nil
      case .conversation:
        query == nil && change == nil
          && (reply.map({
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 4_096
          }) ?? false)
      case .clarify: query == nil && change == nil && reply == nil
      case .cancel: query == nil && change == nil && reply == nil
      case .help: query == nil && change == nil && reply == nil && helpTopic != nil
      }
    guard valid else { throw InterpretationError.invalidRequest }
  }
}

struct InterpretationResult: Sendable {
  let value: ConversationInterpretation
  let identity: InterpretationIdentity
  let elapsed: Duration
}

enum InterpretationError: Error {
  case invalidRequest
  case unavailable(String)
  case deadlineExceeded
  case contextTooLarge
}

@MainActor protocol InterpretationProvider: AnyObject {
  var identity: InterpretationIdentity { get }
  var capabilities: Set<InterpretationCapability> { get }
  var availability: InterpretationAvailability { get }
  func prepare()
  func discard()
  func interpret(_ request: InterpretationRequest) async throws -> ConversationInterpretation
}

extension InterpretationProvider {
  func prepare() {}
  func discard() {}
}

@MainActor final class CalendarRulesProvider: InterpretationProvider {
  let identity = InterpretationIdentity(
    provider: "complete-rules", model: "calendar-3", schemaVersion: 1)
  let capabilities: Set<InterpretationCapability> = [.calendar]
  let availability = InterpretationAvailability.available

  func match(_ text: String, now: Date = .now, calendar: Calendar = .current) -> CalendarQuestion? {
    CalendarQuestion.direct(text, now: now, calendar: calendar)
  }
  func immediate(_ request: InterpretationRequest) -> ConversationInterpretation? {
    if VoiceRules.parse(request.text, now: request.now, calendar: request.calendar).action
      == .cancel
    {
      return ConversationInterpretation(action: .cancel)
    }
    if VoiceRules.hasInvalidDate(request.text, now: request.now, calendar: request.calendar) {
      return ConversationInterpretation(action: .clarify, problem: .invalidDate)
    }
    return nil
  }
  func interpret(_ request: InterpretationRequest) async throws -> ConversationInterpretation {
    try Task.checkCancellation()
    if let immediate = immediate(request) { return immediate }
    guard let question = match(request.text, now: request.now, calendar: request.calendar) else {
      throw InterpretationError.invalidRequest
    }
    return ConversationInterpretation(action: .calendar, query: question)
  }
}

/// Chooses one interpretation provider before generation. It never races models or
/// retries a failed generation with a different provider and a different meaning.
@MainActor final class InterpretationRouter {
  let rules = CalendarRulesProvider()
  private let generation: any InterpretationProvider
  init(generation: any InterpretationProvider) { self.generation = generation }

  var availability: InterpretationAvailability { generation.availability }

  /// Context preparation belongs to the same cancellable task as generation.
  /// A late context response must never start a provider for an ended turn.
  func interpret(preparing request: @MainActor () async throws -> InterpretationRequest)
    async throws -> InterpretationResult
  {
    try Task.checkCancellation()
    let prepared = try await request()
    try Task.checkCancellation()
    return try await interpret(prepared)
  }

  func interpret(_ request: InterpretationRequest) async throws -> InterpretationResult {
    try request.validate()
    try Task.checkCancellation()
    guard ContinuousClock.now < request.deadline else { throw InterpretationError.deadlineExceeded }
    let provider: any InterpretationProvider =
      rules.immediate(request) == nil
        && rules.match(request.text, now: request.now, calendar: request.calendar) == nil
      ? generation : rules
    if case .unavailable(let reason) = provider.availability {
      throw InterpretationError.unavailable(reason)
    }
    let identity = provider.identity
    let started = ContinuousClock.now
    let value = try await InterpretationDeadline.run(until: request.deadline) {
      try await provider.interpret(request)
    }
    try Task.checkCancellation()
    try value.validate()
    let required: InterpretationCapability? =
      switch value.action {
      case .calendar: .calendar
      case .create, .update, .remove: .mutation
      case .conversation: .conversation
      case .help: .appHelp
      case .clarify, .cancel: nil
      }
    guard required.map(provider.capabilities.contains) ?? true else {
      throw InterpretationError.invalidRequest
    }
    return InterpretationResult(
      value: AssistantInterpretation.checked(value, for: request), identity: identity,
      elapsed: started.duration(to: .now))
  }
}

/// An uncooperative native generation may finish late. The caller still receives
/// its deadline/cancellation promptly, and the late value has no delivery path.
@MainActor private final class InterpretationDeadline {
  private var continuation: CheckedContinuation<ConversationInterpretation, Error>?
  private var worker: Task<Void, Never>?
  private var timer: Task<Void, Never>?

  static func run(
    until deadline: ContinuousClock.Instant,
    operation: @escaping @MainActor () async throws -> ConversationInterpretation
  ) async throws -> ConversationInterpretation {
    let pending = InterpretationDeadline()
    let result = try await withTaskCancellationHandler {
      try Task.checkCancellation()
      return try await withCheckedThrowingContinuation { continuation in
        pending.continuation = continuation
        pending.worker = Task { [weak pending] in
          let result: Result<ConversationInterpretation, Error>
          do {
            try Task.checkCancellation()
            let value = try await operation()
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline else {
              throw InterpretationError.deadlineExceeded
            }
            result = .success(value)
          } catch { result = .failure(error) }
          pending?.finish(result)
        }
        pending.timer = Task { [weak pending] in
          do {
            try await ContinuousClock().sleep(until: deadline)
            pending?.finish(.failure(InterpretationError.deadlineExceeded))
          } catch {}
        }
      }
    } onCancel: {
      Task { @MainActor in pending.finish(.failure(CancellationError())) }
    }
    try Task.checkCancellation()
    return result
  }

  private func finish(_ result: Result<ConversationInterpretation, Error>) {
    guard let continuation else { return }
    self.continuation = nil
    worker?.cancel()
    timer?.cancel()
    worker = nil
    timer = nil
    continuation.resume(with: result)
  }
}
