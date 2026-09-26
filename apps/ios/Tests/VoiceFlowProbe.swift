import Foundation
import RehaCore

@MainActor private final class FlowInput: VoiceRecording {
  var state = VoiceRecordingState.idle
  var transcript = ""
  var level = 0.0
  var failure: String?
  var contextualTitles: [String] = []
  var onEndpoint: (() -> Void)?
  var onBargeIn: (() -> Void)?
  var onFailure: ((String) -> Void)?
  var pending: CheckedContinuation<String, Never>?
  var suspend = false
  var monitors = 0
  func beginTurn(preRoll: Bool) async throws { state = .recording }
  func endTurn() async throws -> String {
    state = .finishing
    if suspend { return await withCheckedContinuation { pending = $0 } }
    return transcript
  }
  func monitorForInterruption() {
    monitors += 1
    state = .idle
  }
  func cancelTurn() { state = .idle }
}

@MainActor private final class FlowOutput: VoiceSpeaking {
  var speaking = false
  var responseID = UUID()
  var spokenText = ""
  var onFinished: (() -> Void)?
  var onFailure: ((String) -> Void)?
  var replies: [ConversationReply] = []
  var stops = 0
  func speak(_ reply: ConversationReply) {
    responseID = UUID()
    spokenText = ""
    speaking = true
    replies.append(reply)
  }
  func stop() {
    speaking = false
    stops += 1
  }
}

@MainActor private final class FlowProvider: InterpretationProvider {
  let identity = InterpretationIdentity(
    provider: "flow-fixture", model: "invented", schemaVersion: 1)
  let capabilities: Set<InterpretationCapability> = [.calendar, .mutation, .conversation, .appHelp]
  var availability = InterpretationAvailability.available
  var requests: [InterpretationRequest] = []
  var discards = 0
  var reply: (InterpretationRequest) async throws -> ConversationInterpretation = { _ in
    ConversationInterpretation(action: .clarify, problem: .ambiguous)
  }
  func interpret(_ request: InterpretationRequest) async throws -> ConversationInterpretation {
    requests.append(request)
    return try await reply(request)
  }
  func discard() { discards += 1 }
}

@MainActor private final class FlowCalendar {
  let now = ISO8601DateFormatter().date(from: "2031-05-15T06:00:00Z")!
  var calendar: Calendar {
    var value = Calendar(identifier: .gregorian)
    value.timeZone = TimeZone(identifier: "Europe/Vienna")!
    return value
  }
  var events: [CalendarEvent] = []
  var reads = 0
  var failRead = false
  var active: Set<String> = []
  var previews: [EventProposalView] = []
  var confirmed: [EventProposalView] = []
  var warning = false
  var suspendPreview = false
  var previewContinuation: CheckedContinuation<Void, Never>?
  var suspendConfirm = false
  var confirmContinuation: CheckedContinuation<Void, Never>?

  init() {
    events = [
      event("physio", title: "Physiotherapie", hour: 8, room: "Raum 2.14"),
      event("ergo", title: "Ergotherapie", hour: 10, room: "Raum 3.12"),
    ]
  }
  func event(_ id: String, title: String, hour: Int, room: String) -> CalendarEvent {
    CalendarEvent(
      id: id, external_id: id, calendar_id: "visible", calendar_title: "Privat", source: "fixture",
      occurrence: "", recurring: false, system_only: false, writable: true,
      values: CalendarEventValues(
        title: title,
        start_utc: String(format: "2031-05-15T%02d:00:00Z", hour),
        end_utc: String(format: "2031-05-15T%02d:30:00Z", hour), timezone: "Europe/Vienna",
        location: room, reminder_minutes: 10), metadata: .object([:]), fingerprint: id)
  }
  func fetch(_ start: Date, _ end: Date, _ expected: AgendaSelection?) throws
    -> CalendarQueryResponse
  {
    reads += 1
    if failRead { throw CocoaError(.fileReadNoPermission) }
    let scope = AgendaSelection(calendarIDs: ["visible"])
    guard expected == nil || expected == scope else { throw CalendarQueryFailure.selectionChanged }
    return CalendarQueryResponse(
      scope: scope, events: events.filter { $0.values.start < end && $0.values.end > start },
      unavailableCalendarIDs: [])
  }
  func preferences() -> Preferences {
    Preferences(
      timezone: calendar.timeZone.identifier, reminder: 10, detailedDebug: false,
      appRemindersEnabled: false, appReminderMinutes: nil, reminderSound: false,
      reminderPreview: false, appearance: "system", calendarId: "hidden-write-target",
      displayCalendarIds: ["visible"], recentCalendarIds: [], completionDefaults: [],
      retentionDays: nil)
  }
  var client: EventMutationClient {
    EventMutationClient(
      register: {
        let token = UUID().uuidString
        self.active.insert(token)
        return token
      },
      invalidate: { _ = self.active.remove($0) },
      preview: { request in
        precondition(self.active.contains(request.session))
        let proposal = EventEditProposal(
          token: UUID().uuidString, session: request.session, revision: request.revision,
          expiresAt: 2_000_000_000, kind: request.kind, calendarId: request.calendarId,
          calendarTitle: "Privat", before: request.event, patch: request.patch,
          undoOf: nil, ownedId: nil, origin: request.origin)
        self.previews.append(try EventProposalView(proposal))
        if self.suspendPreview { await withCheckedContinuation { self.previewContinuation = $0 } }
        return .proposal(proposal: proposal)
      },
      confirm: { request in
        let proposal = self.previews.first { $0.token == request.token }!
        precondition(request.confirmation == .button)
        precondition(self.active.contains(request.session))
        precondition(request.revision == proposal.revision)
        precondition(!self.confirmed.contains { $0.token == request.token })
        self.confirmed.append(proposal)
        if self.suspendConfirm { await withCheckedContinuation { self.confirmContinuation = $0 } }
        return EventMutationResult(
          status: .saved, event: nil, operationId: request.token, message: nil,
          maintenanceWarnings: self.warning ? ["reminders"] : [])
      },
      undo: { _ in preconditionFailure("Unexpected undo in voice flow") })
  }

}

@MainActor private struct Flow {
  let calendar = FlowCalendar()
  let input = FlowInput()
  let output = FlowOutput()
  let provider = FlowProvider()
  let model: VoiceModel
  init() {
    let calendar = calendar
    model = VoiceModel(
      dependencies: VoiceDependencies(
        now: { calendar.now }, calendar: { calendar.calendar },
        address: { .sie }, isVoiceOverRunning: { false },
        fetchCalendar: { start, end, scope in try await calendar.fetch(start, end, scope) },
        preferences: { calendar.preferences() }, destinations: { [] }, trace: { _ in },
        errorMessage: { $0.localizedDescription }),
      understanding: provider,
      edits: EventSession(origin: "voice", client: calendar.client),
      recorder: input, output: output)
  }
  func spoken(_ text: String) async {
    input.transcript = text
    await model.beginTurn()
    await model.endTurn()
  }
}

@main struct VoiceFlowProbe {
  @MainActor static func until(_ condition: () -> Bool) async {
    let deadline = ContinuousClock.now + .seconds(3)
    while !condition() && ContinuousClock.now < deadline { await Task.yield() }
    precondition(condition(), "Expected workflow state was not reached")
  }

  @MainActor static func main() async throws {
    let rules = Flow()
    rules.provider.availability = .unavailable("No model assets")
    await rules.model.submitText("Nächster Termin")
    precondition(rules.model.response.contains("Physiotherapie"))
    await rules.model.submitText("Und der Raum dazu?")
    precondition(rules.model.response.contains("2.14"))
    await rules.model.submitText("Und danach?")
    precondition(rules.model.response.contains("Ergotherapie"))
    let reads = rules.calendar.reads
    rules.calendar.events = []
    await rules.model.submitText("Und der Raum dazu?")
    precondition(!rules.model.response.contains("3.12") && rules.calendar.reads > reads)
    precondition(rules.provider.requests.isEmpty && rules.calendar.previews.isEmpty)

    let creation = Flow()
    await creation.model.submitText("Erstelle einen neuen Termin")
    precondition(creation.model.question == .title)
    await creation.model.submitText("Gymnastik")
    precondition(creation.model.question == .date)
    await creation.model.submitText("31. April 2031")
    precondition(creation.model.question == .date && creation.calendar.previews.isEmpty)
    await creation.model.submitText("morgen")
    await creation.model.submitText("zehn Uhr")
    await creation.model.submitText("30 Minuten")
    precondition(creation.model.question == .confirmation)
    let proposal = creation.model.edits.proposal!
    precondition(proposal.calendar_id == "hidden-write-target")
    precondition(proposal.after?.title == "Gymnastik")
    precondition(proposal.after?.start_utc == "2031-05-16T08:00:00Z")
    precondition(creation.calendar.confirmed.isEmpty)
    creation.input.transcript = "Ja, speichern"
    await creation.model.endTurn()
    precondition(creation.model.response.contains("Schaltfläche"))
    precondition(creation.calendar.confirmed.isEmpty && creation.model.edits.proposal != nil)
    creation.calendar.warning = true
    creation.calendar.suspendConfirm = true
    let confirming = Task { await creation.model.confirmProposal() }
    await until { creation.calendar.confirmContinuation != nil }
    await creation.model.confirmProposal()
    precondition(creation.calendar.confirmed.count == 1)
    creation.calendar.confirmContinuation!.resume()
    await confirming.value
    precondition(creation.model.response.contains("gespeichert"))
    precondition(creation.model.response.contains("Widgets"))
    precondition(creation.model.question == .action)

    let selection = Flow()
    await selection.model.submitAction(.remove)
    precondition(selection.model.question == .event)
    await selection.model.submitText("den ersten oder den zweiten")
    precondition(selection.model.edits.proposal == nil && selection.model.question == .event)
    await selection.model.submitText("den zweiten Physiotherapie")
    precondition(selection.model.edits.proposal == nil && selection.model.question == .event)
    await selection.model.submitText("den zweiten um elf Uhr")
    precondition(selection.model.edits.proposal == nil && selection.model.question == .event)
    await selection.model.submitText("Nicht den ersten, sondern den zweiten")
    precondition(selection.model.edits.proposal?.before?.id == "ergo")
    selection.model.cancelSession()
    await selection.model.submitAction(.remove)
    await selection.model.submitText("den zweiten")
    precondition(selection.model.edits.proposal?.before?.id == "ergo")
    precondition(selection.calendar.confirmed.isEmpty)
    selection.model.cancelSession()
    await selection.model.confirmProposal()
    precondition(selection.calendar.confirmed.isEmpty && selection.model.edits.proposal == nil)

    let ordinal = Flow()
    await ordinal.model.submitText("Welche Termine habe ich heute?")
    await ordinal.model.submitText("Verschiebe den zweiten Termin auf morgen um zehn Uhr")
    precondition(
      ordinal.model.edits.proposal?.before?.id == "ergo",
      "Spoken ordinal must use the discussed page")
    precondition(ordinal.model.edits.proposal?.after?.start_utc == "2031-05-16T08:00:00Z")
    precondition(ordinal.model.edits.proposal?.patch.keys.sorted() == ["end_utc", "start_utc"])
    precondition(ordinal.calendar.confirmed.isEmpty && ordinal.provider.requests.isEmpty)

    let unseen = Flow()
    await unseen.model.submitText("Verschiebe den zweiten Termin auf morgen um zehn Uhr")
    precondition(unseen.model.edits.proposal == nil && unseen.calendar.reads == 0)
    let hidden = Flow()
    await hidden.model.submitText("Termine heute")
    hidden.calendar.events = [hidden.calendar.events[0]]
    await hidden.model.submitText("Lösche den zweiten Termin")
    precondition(hidden.model.edits.proposal == nil && hidden.calendar.previews.isEmpty)
    for utterance in [
      "Verschiebe den ersten oder den zweiten Termin auf morgen um zehn Uhr",
      "Verschiebe den zweiten Termin Physiotherapie auf morgen um zehn Uhr",
      "Verschiebe den zweiten Termin um elf Uhr auf morgen um zehn Uhr",
      "Verschiebe die zweite Therapie auf morgen um zehn Uhr",
    ] {
      let conflict = Flow()
      await conflict.model.submitText("Termine heute")
      await conflict.model.submitText(utterance)
      precondition(
        conflict.model.edits.proposal == nil && conflict.calendar.previews.isEmpty, utterance)
      await conflict.model.submitText("Verschiebe den ersten Termin auf morgen um zehn Uhr")
      precondition(
        conflict.model.edits.proposal?.before?.id == "physio",
        "Failed selection renumbered the heard page")
    }
    precondition(VoiceRules.eventPosition("Lösche den Termin am ersten Mai") == .absent)

    let subject = Flow()
    await subject.model.submitAction(.create)
    await subject.model.submitText("Gymnastik")
    await subject.model.submitText("Welche Termine habe ich heute?")
    precondition(subject.model.question == .action && subject.model.intent.action == .unsupported)
    await subject.model.submitText("Nein, bitte nichts ändern")
    precondition(subject.calendar.previews.isEmpty && subject.calendar.confirmed.isEmpty)

    let rejected = Flow()
    await rejected.model.submitText("Plane Gymnastik am 31. April 2031 um acht Uhr")
    await rejected.model.submitText("Wie lösche ich den Termin?")
    rejected.calendar.events = [
      rejected.calendar.event("other", title: "Bewegung mit anderen", hour: 8, room: "")
    ]
    await rejected.model.submitText("Lösche den anderen Termin")
    precondition(rejected.calendar.previews.isEmpty && rejected.calendar.confirmed.isEmpty)

    let preview = Flow()
    preview.calendar.events = [preview.calendar.events[0]]
    preview.calendar.suspendPreview = true
    let preparing = Task { await preview.model.submitAction(.remove) }
    await until { preview.calendar.previewContinuation != nil }
    preview.model.cancelSession()
    await preview.model.submitText("Termine morgen")
    let latestResponse = preview.model.response
    preview.calendar.previewContinuation!.resume()
    await preparing.value
    precondition(preview.model.edits.proposal == nil && preview.model.response == latestResponse)
    precondition(preview.calendar.confirmed.isEmpty)

    let late = Flow()
    var pending: CheckedContinuation<ConversationInterpretation, Never>?
    var lateReturned = false
    late.provider.reply = { _ in
      let value = await withCheckedContinuation { pending = $0 }
      lateReturned = true
      return value
    }
    let oldRequest = Task { await late.model.submitText("Erzähle mir bitte etwas Nettes") }
    await until { pending != nil }
    late.model.cancelSession()
    let currentQuestion = "Erzähle mir bitte etwas anderes"
    await late.model.submitText(currentQuestion)
    precondition(late.provider.requests.count == 1, "Canceled native work was admitted again")
    precondition(late.model.rounds.last?.user == currentQuestion, "Current request was lost")
    precondition(late.model.response.contains("vorherige Anfrage"))
    precondition(late.calendar.previews.isEmpty && late.calendar.confirmed.isEmpty)
    await late.model.submitText("Nächster Termin")
    let latest = late.model.response
    pending!.resume(
      returning: ConversationInterpretation(action: .conversation, reply: "Alte Antwort"))
    await until { lateReturned }
    await oldRequest.value
    precondition(late.model.response == latest && late.output.replies.last?.text == latest)
    precondition(late.provider.requests.count == 1 && late.provider.discards > 0)

    let recognition = Flow()
    recognition.input.suspend = true
    await recognition.model.beginTurn()
    let finishing = Task { await recognition.model.endTurn() }
    await until { recognition.input.pending != nil }
    recognition.model.cancelSession()
    recognition.input.pending!.resume(returning: "Lösche den Termin")
    await finishing.value
    precondition(recognition.calendar.previews.isEmpty && recognition.output.replies.isEmpty)

    let cancelledInput = Flow()
    cancelledInput.input.transcript = "Nächster Termin"
    let cancelledTurn = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      await cancelledInput.model.beginTurn()
      await cancelledInput.model.endTurn()
    }
    await cancelledTurn.value
    precondition(cancelledInput.input.state == .idle && !cancelledInput.model.isSessionRunning)
    precondition(cancelledInput.output.replies.isEmpty && cancelledInput.calendar.reads == 0)

    let history = Flow()
    history.provider.reply = { _ in
      ConversationInterpretation(
        action: .conversation, reply: "Guten Tag. Schön, dass Sie da sind.")
    }
    await history.spoken("Guten Tag")
    history.output.spokenText = "Guten Tag."
    await history.model.submitText("Was können Sie für mich tun?")
    let request = history.provider.requests.last!
    precondition(request.text == "Was können Sie für mich tun?")
    precondition(request.history.last?["spoken_answer"] == "Guten Tag.")
    precondition(request.history.last?["displayed_answer"] == nil)
    history.model.repeatResponse()
    precondition(history.output.replies.last?.text == history.model.response)
    history.model.pauseSession()
    precondition(!history.output.speaking && history.input.state == .idle)

    let interruption = Flow()
    interruption.provider.reply = { _ in
      ConversationInterpretation(action: .conversation, reply: "Guten Tag.")
    }
    await interruption.spoken("Guten Tag")
    precondition(interruption.output.speaking)
    interruption.input.onBargeIn?()
    await until { interruption.input.state == .recording }
    precondition(!interruption.output.speaking && interruption.model.sessionState == .listening)
    interruption.input.transcript = "Stopp"
    await interruption.model.endTurn()
    precondition(interruption.model.sessionState == .stopped && interruption.input.state == .idle)

    let failure = Flow()
    failure.calendar.failRead = true
    await failure.model.submitText("Termine heute")
    precondition(failure.model.response.contains("nicht gelesen"))
    precondition(failure.calendar.previews.isEmpty && failure.calendar.confirmed.isEmpty)
    print(
      "Voice flow passed: actual rules/router/state, live calendar facts, multi-turn creation, visible confirmation, selected target, topic change, cancellation, late results, heard history, repeat and maintenance warning"
    )
  }
}
