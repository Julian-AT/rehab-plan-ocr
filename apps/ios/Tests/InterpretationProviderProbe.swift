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
    var newYork = Calendar(identifier: .gregorian)
    newYork.timeZone = TimeZone(identifier: "America/New_York")!
    let evening = ISO8601DateFormatter().date(from: "2026-09-16T02:00:00Z")!
    let zonedRequest = InterpretationRequest(
      text: "Termine heute", context: "{}", history: [], now: evening,
      calendar: newYork, deadline: .now + .seconds(5))
    let zonedRules = try await router.interpret(zonedRequest)
    precondition(zonedRules.value.query?.timezone == "America/New_York")
    precondition(zonedRules.value.query?.date == newYork.startOfDay(for: evening))
    precondition(provider.calls == 0)
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

    provider.operation = { _ in ConversationInterpretation(action: .help, helpTopic: .capture) }
    do {
      _ = try await router.interpret(request("Wie fotografiere ich einen Plan?"))
      preconditionFailure("Help capability was not checked")
    } catch InterpretationError.invalidRequest {}
    provider.capabilities.insert(.appHelp)
    let help = try await router.interpret(request("Wie fotografiere ich einen Plan?"))
    precondition(help.value.helpTopic == .capture && help.value.reply == nil)
    provider.operation = { _ in ConversationInterpretation(action: .cancel) }
    let canceledIntent = try await router.interpret(request("Ich möchte doch nichts ändern"))
    precondition(canceledIntent.value.action == .cancel && canceledIntent.value.change == nil)
    let callsBeforeInvalidRequests = provider.calls

    for input in [request(""), request("Termine morgen", seconds: -1)] {
      do {
        _ = try await router.interpret(input)
        preconditionFailure("Invalid admission")
      } catch InterpretationError.invalidRequest {} catch InterpretationError.deadlineExceeded {}
    }
    precondition(provider.calls == callsBeforeInvalidRequests)
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
    let zonedQuery = CalendarUnderstanding.Query(
      detail: .list, date: "2026-09-15", days: 1, title: "", excluding: "", calendarName: nil,
      reference: nil, ordinal: 0, usesLastPage: false, after: "21:00", before: "23:00")
    let zonedApple = try CalendarUnderstanding(
      action: .calendar, query: zonedQuery, change: nil, reply: nil
    ).validated(calendar: newYork)
    precondition(zonedApple.query?.date == newYork.startOfDay(for: evening))
    precondition(zonedApple.query?.timezone == "America/New_York")
    let changed = try CalendarUnderstanding.Change(
      title: nil, date: "2026-09-15", time: "22:00", duration: nil
    ).validated(action: .update, calendar: newYork)
    precondition(changed.timezone == "America/New_York" && changed.newTime == 1320)
    precondition(changed.newDate == newYork.startOfDay(for: evening))
    precondition(
      changed.calendar.date(bySettingHour: 22, minute: 0, second: 0, of: changed.newDate!)
        == evening)
    let zonedCustom = try AssistantInterpretation.decode(
      #"{"action":"update","query":{"reference":"r1"},"change":{"date":"2026-09-15","time":"22:00"}}"#,
      references: ["r1"], timezone: "America/New_York")
    precondition(zonedCustom.change?.timezone == changed.timezone)
    precondition(zonedCustom.change?.newDate == changed.newDate)
    precondition(zonedCustom.change?.newTime == changed.newTime)
    let zonedMutation = VoiceRules.parse(
      "Verschiebe den Termin auf heute um 22 Uhr", now: evening, calendar: newYork)
    precondition(zonedMutation.timezone == "America/New_York")
    precondition(zonedMutation.newDate == changed.newDate && zonedMutation.newTime == 1320)
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
