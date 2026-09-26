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
        query: CalendarQuestion(
          date: input.calendar.date(
            byAdding: .day, value: 1, to: input.calendar.startOfDay(for: input.now)),
          excluding: "Gymnastik"))
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

    // A timed-out native request still owns its generation slot until it returns.
    // Repeated attempts must not accumulate uncooperative model operations.
    let heldProvider = FixtureProvider()
    let heldRouter = InterpretationRouter(generation: heldProvider)
    var held: [CheckedContinuation<ConversationInterpretation, Never>] = []
    heldProvider.operation = { _ in
      await withCheckedContinuation { held.append($0) }
    }
    do {
      _ = try await heldRouter.interpret(request("Ausführliche freie Frage", seconds: 0.05))
      preconditionFailure("Uncooperative provider escaped its deadline")
    } catch InterpretationError.deadlineExceeded {}
    precondition(held.count == 1)
    var blocked = 0
    for _ in 0..<20 {
      do {
        _ = try await heldRouter.interpret(request("Neue ausführliche Frage", seconds: 0.05))
      } catch InterpretationError.unavailable {
        blocked += 1
      } catch InterpretationError.deadlineExceeded {}
    }
    let heldCalls = heldProvider.calls
    let simpleWhileHeld = try await heldRouter.interpret(request("Termine morgen"))
    precondition(simpleWhileHeld.identity.provider == "complete-rules")
    for completion in held {
      completion.resume(returning: ConversationInterpretation(action: .create))
    }
    held.removeAll()
    print("Uncooperative admission: provider calls=\(heldCalls), blocked repeats=\(blocked)")
    precondition(heldCalls == 1 && blocked == 20, "Repeated timeouts accumulated model work")
    let drained = ContinuousClock.now + .seconds(2)
    while heldRouter.availability != .available && ContinuousClock.now < drained {
      await Task.yield()
    }
    precondition(heldRouter.availability == .available)
    heldProvider.operation = { _ in ConversationInterpretation(action: .clarify) }
    _ = try await heldRouter.interpret(request("Aktuelle freie Frage"))
    precondition(heldProvider.calls == 2, "Provider was not admitted after actual drain")

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

    let deadlineDrained = ContinuousClock.now + .seconds(2)
    while router.availability != .available && ContinuousClock.now < deadlineDrained {
      await Task.yield()
    }
    precondition(router.availability == .available)
    let cancellationTask = Task { try await router.interpret(request("Andere freie Frage")) }
    await iterator.next()
    cancellationTask.cancel()
    do {
      _ = try await cancellationTask.value
      preconditionFailure("Canceled response delivered")
    } catch is CancellationError {}
    let callsDuringCancel = provider.calls
    for _ in 0..<20 {
      do {
        _ = try await router.interpret(request("Weitere freie Frage"))
        preconditionFailure("Canceled but active model admitted more work")
      } catch InterpretationError.unavailable {}
    }
    let immediateCancel = try await router.interpret(request("Abbrechen"))
    precondition(immediateCancel.value.action == .cancel && provider.calls == callsDuringCancel)
    late?.resume(returning: ConversationInterpretation(action: .remove))
    late = nil
    provider.operation = { _ in
      ConversationInterpretation(action: .conversation, reply: "Neue Antwort")
    }
    let cancellationDrained = ContinuousClock.now + .seconds(2)
    while router.availability != .available && ContinuousClock.now < cancellationDrained {
      await Task.yield()
    }
    precondition(router.availability == .available)
    let fresh = try await router.interpret(request("Neues Thema"))
    precondition(fresh.value.reply == "Neue Antwort")

    provider.operation = { _ in throw InterpretationError.invalidRequest }
    do {
      _ = try await router.interpret(request("Fehlerhafte freie Frage"))
      preconditionFailure("Provider error was lost")
    } catch InterpretationError.invalidRequest {}
    precondition(router.availability == .available, "Provider failure retained its slot")
    provider.operation = { _ in
      ConversationInterpretation(action: .conversation, reply: "Neue Antwort")
    }

    // Cancellation while context is being prepared must precede provider admission.
    // Let a newer request complete before the old, uncooperative context arrives.
    var pendingContext: CheckedContinuation<Void, Never>?
    let contextStarted = AsyncStream<Void>.makeStream()
    let beforePreparation = provider.calls
    let preparing = Task {
      try await router.interpret(preparing: {
        await withCheckedContinuation { continuation in
          pendingContext = continuation
          contextStarted.continuation.yield(())
        }
        return request("Veraltete Frage")
      })
    }
    var contextIterator = contextStarted.stream.makeAsyncIterator()
    await contextIterator.next()
    preparing.cancel()
    let replacement = try await router.interpret(request("Aktuelle Frage"))
    precondition(replacement.value.reply == "Neue Antwort")
    pendingContext?.resume()
    do {
      _ = try await preparing.value
      preconditionFailure("Cancelled context admitted a provider")
    } catch is CancellationError {}
    precondition(provider.calls == beforePreparation + 1)

    var preparedWhenCancelled = false
    let cancelledBeforePreparation = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try await router.interpret(preparing: {
        preparedWhenCancelled = true
        return request("Nicht mehr vorbereiten")
      })
    }
    do {
      _ = try await cancelledBeforePreparation.value
      preconditionFailure("Cancelled task prepared another context")
    } catch is CancellationError {}
    precondition(!preparedWhenCancelled && provider.calls == beforePreparation + 1)
    print(
      "Interpretation providers passed: complete rules, one selected model, capability fallback, deadlines, cancellation during context preparation and late-result isolation."
    )
  }
}
