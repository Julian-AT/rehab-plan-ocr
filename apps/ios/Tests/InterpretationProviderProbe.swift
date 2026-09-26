import Foundation

@MainActor private final class FixtureProvider: InterpretationProvider {
  let identity = InterpretationIdentity(provider: "fixture", model: "invented", schemaVersion: 1)
  var capabilities: Set<InterpretationCapability> = [.calendar, .mutation, .conversation]
  var availability = InterpretationAvailability.available
  var calls = 0
  var operation: @MainActor (InterpretationRequest) async throws -> ConversationInterpretation = {
    _ in
    ConversationInterpretation(action: .clarify)
  }
  func interpret(_ request: InterpretationRequest) async throws -> ConversationInterpretation {
    calls += 1
    return try await operation(request)
  }
}

@main struct InterpretationProviderProbe {
  @MainActor static func main() async throws {
    func request(_ text: String, seconds: Double = 5) -> InterpretationRequest {
      InterpretationRequest(
        text: text, context: "{}", history: [], now: .now,
        deadline: ContinuousClock.now.advanced(by: .seconds(seconds)))
    }
    let provider = FixtureProvider()
    let router = InterpretationRouter(generation: provider)
    provider.availability = .unavailable("Missing local asset")
    let direct = try await router.interpret(request("Termine morgen"))
    precondition(direct.identity.provider == "complete-rules" && direct.value.query != nil)
    precondition(provider.calls == 0, "Exact rules must work without starting an unavailable model")
    do {
      _ = try await router.interpret(request("Termine morgen außer Gymnastik"))
      preconditionFailure("Unavailable model called")
    } catch InterpretationError.unavailable(let reason) {
      precondition(reason == "Missing local asset")
    }
    precondition(provider.calls == 0)
    provider.availability = .available
    provider.operation = { input in
      precondition(input.text == "Termine morgen außer Gymnastik")
      return ConversationInterpretation(
        action: .calendar,
        query: CalendarQuestion(excluding: "Gymnastik"))
    }
    let generated = try await router.interpret(request("Termine morgen außer Gymnastik"))
    precondition(
      generated.identity == provider.identity && generated.value.query?.excluding == "Gymnastik")
    precondition(provider.calls == 1)

    for input in [request(""), request("Termine morgen", seconds: -1)] {
      do {
        _ = try await router.interpret(input)
        preconditionFailure("Invalid admission")
      } catch InterpretationError.invalidRequest {} catch InterpretationError.deadlineExceeded {}
    }
    precondition(provider.calls == 1)
    provider.capabilities = [.calendar]
    provider.operation = { _ in ConversationInterpretation(action: .create) }
    do {
      _ = try await router.interpret(request("Erstelle einen Termin"))
      preconditionFailure("Provider exceeded declared capabilities")
    } catch InterpretationError.invalidRequest {}
    provider.capabilities = [.calendar, .mutation, .conversation]
    for malformed in [
      ConversationInterpretation(
        action: .calendar, query: CalendarQuestion(), reply: "Invented fact"),
      ConversationInterpretation(action: .remove),
      ConversationInterpretation(
        action: .calendar, query: CalendarQuestion(afterMinutes: 900, beforeMinutes: 800)),
      ConversationInterpretation(action: .conversation, reply: " "),
    ] {
      provider.operation = { _ in malformed }
      do {
        _ = try await router.interpret(request("Strukturierte Frage"))
        preconditionFailure("Invalid output escaped")
      } catch InterpretationError.invalidRequest {}
    }

    let query = CalendarUnderstanding.Query(
      detail: .room, date: nil, days: 1, title: "", excluding: "", calendarName: nil,
      reference: "r1", ordinal: 0, usesLastPage: false, after: nil, before: nil)
    let decoded = try CalendarUnderstanding(
      action: .calendar, query: query, change: nil, reply: nil
    ).validated()
    precondition(decoded.query?.reference == "r1" && decoded.query?.detail == .room)
    for title in ["", String(repeating: "x", count: 201)] {
      do {
        _ = try CalendarUnderstanding.Change(title: title, date: nil, time: nil, duration: nil)
          .validated(action: .update)
        preconditionFailure("Invalid change title accepted")
      } catch CalendarUnderstandingError.invalidRequest {}
    }

    // Simulate a native implementation that ignores cancellation until C inference returns.
    var late: CheckedContinuation<ConversationInterpretation, Never>?
    let started = AsyncStream<Void>.makeStream()
    provider.operation = { _ in
      await withCheckedContinuation { continuation in
        late = continuation
        started.continuation.yield(())
      }
    }
    let deadlineTask = Task { try await router.interpret(request("Freie Frage", seconds: 0.2)) }
    var iterator = started.stream.makeAsyncIterator()
    await iterator.next()
    do {
      _ = try await deadlineTask.value
      preconditionFailure("Late response delivered")
    } catch InterpretationError.deadlineExceeded {}
    precondition(late != nil, "Deadline must finish before the uncooperative provider")
    late?.resume(returning: ConversationInterpretation(action: .create))
    late = nil

    let cancellationTask = Task { try await router.interpret(request("Andere freie Frage")) }
    await iterator.next()
    cancellationTask.cancel()
    do {
      _ = try await cancellationTask.value
      preconditionFailure("Canceled response delivered")
    } catch is CancellationError {}
    late?.resume(returning: ConversationInterpretation(action: .remove))
    late = nil
    provider.operation = { _ in
      ConversationInterpretation(action: .conversation, reply: "Neue Antwort")
    }
    let fresh = try await router.interpret(request("Neues Thema"))
    precondition(fresh.value.reply == "Neue Antwort")
    print(
      "Interpretation providers passed: complete rules, one selected model, capability fallback, deadlines, cancellation and late-result isolation."
    )
  }
}
