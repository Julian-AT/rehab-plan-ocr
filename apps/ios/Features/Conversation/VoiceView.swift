import AVFoundation
import AppleServices
import FoundationModels
import RehaCore
import SwiftUI

struct VoiceSnapshot {
  let session: String
  let turn: UInt64
  let sequence: UInt64
  let revision: UInt64
  let response: String
  let question: VoiceModel.Question
  let recording: Bool
}
@MainActor @Observable final class VoiceModel {
  enum SessionState { case stopped, listening, thinking, speaking, paused }
  struct Round: Identifiable {
    let id = UUID()
    let user: String
    var textual = false
    var answer = ""
    var prepared = ConversationReply()
    var outputID: UUID?
    var heard = HeardSpeech()
    var spoken: String { heard.text }
  }
  private(set) var sessionState: SessionState = .stopped
  private(set) var rounds: [Round] = []
  private var running = false
  private var turnTask: Task<Void, Never>?
  private let calendarConversation: CalendarConversation
  private let understanding = CalendarUnderstandingSession()
  private var modelToken = UUID()
  typealias Question = ConversationState.Question
  let core: NativeApplication
  let recorder = LocalSpeechRecorder()
  let edits: EventSession
  private(set) var session = UUID().uuidString
  private(set) var turn: UInt64 = 0
  private(set) var sequence: UInt64 = 0
  private(set) var revision: UInt64 = 0
  var response = ""
  private var preparedResponse = ConversationReply()
  var failure: String?
  private var interaction = ConversationState.idle
  var question: Question {
    get { interaction.question }
    set {
      interaction.ask(newValue)
      if newValue == .action {
        candidates = []
        selected = nil
        // Completed receipts stay visible. Only an outstanding edit needs its
        // async session invalidated when the conversation changes subject.
        if edits.proposal != nil || edits.systemEvent != nil || edits.busy {
          edits.interrupt()
        }
      }
    }
  }
  var failures = 0
  var busy = false
  var candidates: [CalendarEvent] = []
  var selected: CalendarEvent?
  var intent: VoiceIntent {
    get { interaction.intent }
    set { interaction.intent = newValue }
  }
  var title = ""
  var date = Calendar.current.startOfDay(for: .now)
  var time = Date()
  var duration = 0
  private var responseTask: Task<CalendarUnderstanding, Error>?
  init(core: NativeApplication) {
    self.core = core
    edits = EventSession(core: core, origin: "voice")
    calendarConversation = CalendarConversation(fetch: { start, end in
      let iso = ISO8601DateFormatter()
      return try await core.eventRequest(
        "queryCalendarEvents",
        ["start_utc": iso.string(from: start), "end_utc": iso.string(from: end)],
        as: CalendarQueryResponse.self)
    })
    recorder.onEndpoint = { [weak self] in self?.turnTask = Task { await self?.endTurn() } }
    recorder.onBargeIn = { [weak self] in self?.interruptAnswer() }
    recorder.onFailure = { [weak self] message in
      self?.pauseSession()
      self?.failure = message
    }
  }
  private func installOutputCallbacks() {
    SpeechOutput.shared.onFinished = { [weak self] in self?.answerFinished() }
    SpeechOutput.shared.onFailure = { [weak self] message in
      self?.pauseSession()
      self?.failure = message
    }
  }
  var isSessionRunning: Bool { running }
  private func rememberSpoken() {
    guard !rounds.isEmpty else { return }
    let output = SpeechOutput.shared
    guard rounds[rounds.count - 1].outputID == output.responseID else { return }
    rounds[rounds.count - 1].heard.capture(
      playback: output.responseID, completedWords: output.spokenText)
  }
  private func answerFinished() {
    LocalDiagnostics.shared.record(.playback, .completed, correlation: session)
    rememberSpoken()
    guard running, edits.proposal == nil else { return }
    if UIAccessibility.isVoiceOverRunning {
      pauseSession()
      return
    }
    turnTask = Task { [weak self] in
      guard let self else { return }
      while self.busy && !Task.isCancelled { try? await Task.sleep(for: .milliseconds(25)) }
      guard !Task.isCancelled, self.running else { return }
      await self.beginTurn()
    }
  }
  func pauseSession() {
    LocalDiagnostics.shared.record(.interruption, .completed, correlation: session)
    let endedToken = modelToken
    running = false
    sessionState = .paused
    turnTask?.cancel()
    turnTask = nil
    responseTask?.cancel()
    understanding.discard()
    responseTask = nil
    SpeechOutput.shared.stop()
    rememberSpoken()
    recorder.cancelTurn()
    session = UUID().uuidString
    modelToken = UUID()
    busy = false
    edits.interrupt()
    Task { await calendarConversation.invalidate(endedToken) }
  }
  private func interruptAnswer() {
    guard running, edits.proposal == nil else { return }
    LocalDiagnostics.shared.record(.interruption, .completed, correlation: session)
    let endedToken = modelToken
    responseTask?.cancel()
    understanding.discard()
    responseTask = nil
    turnTask?.cancel()
    SpeechOutput.shared.stop()
    rememberSpoken()
    session = UUID().uuidString
    modelToken = UUID()
    busy = false
    edits.interrupt()
    turnTask = Task { [weak self] in
      guard let self else { return }
      await self.calendarConversation.invalidate(endedToken)
      await self.beginTurn(preRoll: true)
    }
  }
  func snapshot() -> VoiceSnapshot {
    VoiceSnapshot(
      session: session, turn: turn, sequence: sequence, revision: revision, response: response,
      question: question, recording: recorder.state == .recording)
  }
  func attach() -> VoiceSnapshot { snapshot() }
  private func say(_ text: String, question: Question? = nil) {
    installOutputCallbacks()
    SpeechOutput.shared.stop()
    rememberSpoken()
    let reply = ConversationReply(text)
    response = reply.text
    preparedResponse = reply
    if let question { self.question = question }
    sequence += 1
    revision += 1
    if !rounds.isEmpty {
      rounds[rounds.count - 1].answer = reply.text
      rounds[rounds.count - 1].prepared = reply
    }
    if running {
      sessionState = .speaking
      recorder.monitorForInterruption()
    }
    SpeechOutput.shared.speak(reply)
    if !rounds.isEmpty { rounds[rounds.count - 1].outputID = SpeechOutput.shared.responseID }
  }
  func repeatResponse() {
    installOutputCallbacks()
    SpeechOutput.shared.stop()
    rememberSpoken()
    if !rounds.isEmpty {
      rounds[rounds.count - 1].answer = preparedResponse.text
      rounds[rounds.count - 1].prepared = preparedResponse
    }
    if running {
      sessionState = .speaking
      recorder.monitorForInterruption()
    }
    SpeechOutput.shared.speak(preparedResponse)
    if !rounds.isEmpty { rounds[rounds.count - 1].outputID = SpeechOutput.shared.responseID }
  }
  func beginTurn(preRoll: Bool = false) async {
    failure = nil
    guard !busy, edits.proposal == nil else { return }
    if SpeechOutput.shared.speaking {
      SpeechOutput.shared.stop()
      rememberSpoken()
    }
    LocalDiagnostics.shared.record(.speechRecognition, .started, correlation: session)
    running = true
    sessionState = .listening
    turn += 1
    sequence += 1
    let current = session
    if question == .action { understanding.prepare() }
    recorder.contextualTitles = candidates.map { $0.values.title }
    do { try await recorder.beginTurn(preRoll: preRoll) } catch {
      if session == current {
        pauseSession()
        failure = error.localizedDescription
        response = error.localizedDescription
      }
    }
  }
  func endTurn() async {
    guard !busy else { return }
    busy = true
    sessionState = .thinking
    let current = session
    defer { if session == current { busy = false } }
    do {
      let text = try await recorder.endTurn()
      LocalDiagnostics.shared.record(
        .speechRecognition, .completed, correlation: current, count: text.count)
      guard session == current, !Task.isCancelled else { return }
      guard !text.isEmpty else {
        busy = false
        if running { await beginTurn() }
        return
      }
      recorder.monitorForInterruption()
      rounds.append(Round(user: text))
      if rounds.count > 100 { rounds.removeFirst() }
      await interpret(text)
    } catch {
      if session == current {
        pauseSession()
        failure = error.localizedDescription
      }
    }
  }
  private func failed(_ message: String = "Das habe ich noch nicht verstanden.") {
    failures += 1
    say(failures >= 2 ? "Bitte auf dem Bildschirm auswählen." : "\(message) \(response)")
  }
  private func interpret(_ text: String) async {
    guard !text.isEmpty else {
      failed("Ich habe keine Sprache erkannt.")
      return
    }
    let parsed = VoiceRules.parse(text)
    if parsed.action == .cancel {
      cancelSession()
      return
    }
    if parsed.negatedChange {
      say(
        VoiceAddress.saved().choose(
          "Es wird nichts geändert. Was möchtest du wissen?",
          "Es wird nichts geändert. Was möchten Sie wissen?"), question: .action)
      return
    }
    if VoiceRules.hasInvalidDate(text) {
      say("Dieses Datum ist ungültig. Bitte das Datum noch einmal nennen.")
      return
    }
    if CalendarQuestion.isRepeat(text) {
      repeatResponse()
      return
    }
    if let request = CalendarQuestion.direct(text) {
      question = .action
      await answerCalendar(request)
      return
    }
    switch question {
    case .title:
      title = text
      intent.title = text
      failures = 0
      await advanceCreation()
    case .date:
      if let date = VoiceRules.date(text, now: .now, calendar: .current) {
        intent.newDate = date
        self.date = date
        failures = 0
        await advance()
      } else {
        failed("An welchem Datum?")
      }
    case .time:
      if let minutes = VoiceRules.time(text) {
        intent.newTime = minutes
        failures = 0
        await advance()
      } else {
        failed("Um welche Uhrzeit?")
      }
    case .duration:
      if let minutes = VoiceRules.duration(text.contains("minut") ? text : text + " minuten"),
        minutes > 0
      {
        intent.duration = minutes
        failures = 0
        await advance()
      } else {
        failed("Wie viele Minuten dauert der Termin?")
      }
    case .event:
      let words = VoiceRules.normalized(text)
      let index = ["erste": 0, "zweite": 1, "dritte": 2].first { words.contains($0.key) }?.value
      let matches = candidates.filter { words.contains(VoiceRules.normalized($0.values.title)) }
      if let index, candidates.indices.contains(index) {
        await choose(candidates[index])
      } else if matches.count == 1 {
        await choose(matches[0])
      } else {
        failed("Welcher Termin ist gemeint?")
      }
    case .confirmation:
      say("Zum Speichern bitte die große Schaltfläche antippen.")
    case .action:
      guard ![.unsupported, .next, .list].contains(parsed.action) else {
        await converse(text)
        return
      }
      intent = parsed
      failures = 0
      if intent.action == .create {
        let extracted = VoiceRules.matches(
          "(?:namens|mit titel) (.+?)(?: am | um | morgen| heute|$)", text
        ).first
        intent.title = extracted?[1]
        title = intent.title ?? ""
        await advanceCreation()
      } else {
        await findEvents()
      }
    }
  }
  func submitText(_ text: String) async {
    guard !busy, !edits.busy, edits.proposal == nil else { return }
    let current = session
    recorder.cancelTurn()
    SpeechOutput.shared.stop()
    rememberSpoken()
    failure = nil
    busy = true
    running = false
    sessionState = .paused
    rounds.append(Round(user: text, textual: true))
    if rounds.count > 100 { rounds.removeFirst() }
    defer { if session == current { busy = false } }
    await interpret(text.trimmingCharacters(in: .whitespacesAndNewlines))
  }
  private func answerCalendar(_ request: CalendarQuestion, token: UUID? = nil) async {
    let current = session
    let isNew = token == nil
    let token = token ?? UUID()
    modelToken = token
    if isNew {
      understanding.discard()
      await calendarConversation.begin(token)
    }
    guard current == session, modelToken == token, !Task.isCancelled else { return }
    do {
      let result = try await calendarConversation.resolve(
        request, token: token, address: VoiceAddress.saved())
      guard current == session, modelToken == token, !Task.isCancelled else { return }
      candidates = result.events
      selected = candidates.count == 1 ? candidates.first : nil
      say(result.text, question: .action)
    } catch {
      guard current == session, !Task.isCancelled else { return }
      say(
        "Die Kalenderdaten konnten gerade nicht gelesen werden. Bitte erneut versuchen.",
        question: .action)
    }
  }
  private func converse(_ text: String) async {
    failures = 0
    guard SystemLanguageModel.default.isAvailable else {
      say(
        "Für freie Gespräche muss Apple Intelligence in den iPhone-Einstellungen aktiviert sein. Einfache Fragen wie „Termine morgen“ sind auch ohne Sprachmodell möglich.",
        question: .action)
      return
    }
    let current = session
    let token = UUID()
    modelToken = token
    LocalDiagnostics.shared.record(.tools, .started, correlation: current)
    await calendarConversation.begin(token)
    guard session == current, modelToken == token, !Task.isCancelled else { return }
    do {
      let context = try await calendarConversation.context()
      let history = rounds.dropLast().suffix(6).map {
        [
          "user": $0.user,
          $0.textual ? "displayed_answer" : "spoken_answer": $0.textual ? $0.answer : $0.spoken,
        ]
      }
      let task = Task { @MainActor [understanding] in
        try await understanding.respond(text: text, context: context, history: history)
      }
      responseTask = task
      let result = try await task.value
      guard session == current, modelToken == token, !Task.isCancelled else { return }
      responseTask = nil
      switch result.action {
      case .calendar:
        guard let query = result.query else { throw CalendarUnderstandingError.invalidRequest }
        await answerCalendar(try query.validated(), token: token)
      case .clarify:
        say(
          VoiceAddress.saved().choose(
            "Welchen Zeitraum oder welchen Termin meinst du?",
            "Welchen Zeitraum oder welchen Termin meinen Sie?"), question: .action)
      case .conversation:
        // A calendar utterance must not escape the factual answer builder.
        if CalendarQuestion.concernsCalendar(text)
          || result.reply.map(CalendarQuestion.concernsCalendar) == true
        {
          say(
            "Bitte die Kalenderfrage mit einem Zeitraum oder einem Terminbezug eingrenzen.",
            question: .action)
        } else {
          guard let reply = result.reply, !reply.isEmpty else {
            throw CalendarUnderstandingError.invalidRequest
          }
          say(reply, question: .action)
        }
      case .create, .update, .remove:
        let action: VoiceIntent.Action =
          result.action == .create ? .create : result.action == .update ? .update : .remove
        let change = try result.change?.validated(action: action)
        intent = change ?? VoiceIntent()
        intent.action = action
        selected = nil
        if action == .create {
          title = intent.title ?? ""
          await advanceCreation()
        } else {
          guard let query = result.query else { throw CalendarUnderstandingError.invalidRequest }
          var request = try query.validated()
          request.detail = .list
          let matches = try await calendarConversation.resolve(
            request, token: token, address: VoiceAddress.saved())
          guard session == current, modelToken == token, !Task.isCancelled else { return }
          candidates = matches.events
          if matches.total == 1, let event = candidates.first {
            await choose(event)
          } else if candidates.isEmpty {
            say(matches.text, question: .action)
          } else {
            say(
              VoiceAddress.saved().choose("Welchen Termin meinst du?", "Welchen Termin meinen Sie?")
                + " " + matches.text, question: .event)
          }
        }
      }
    } catch {
      guard session == current, modelToken == token, !Task.isCancelled else { return }
      responseTask = nil
      say(
        error is CalendarUnderstandingError
          ? "Bitte die Frage kürzer formulieren und einen eindeutigen Zeitraum oder Termin nennen."
          : "Die Antwort konnte gerade nicht erstellt werden. Bitte erneut versuchen oder in den Gesprächsdetails auswählen.",
        question: .action)
    }
  }
  func submitAction(_ action: VoiceIntent.Action) async {
    guard !busy && !edits.busy else { return }
    session = UUID().uuidString
    let current = session
    busy = true
    failure = nil
    SpeechOutput.shared.stop()
    rememberSpoken()
    let actionLabel: String =
      switch action {
      case .next: "Nächster Termin"
      case .list: "Heute"
      case .create: "Termin hinzufügen"
      case .update: "Termin ändern"
      case .remove: "Kalendereintrag löschen"
      default: "Kalender"
      }
    rounds.append(Round(user: actionLabel))
    if rounds.count > 100 { rounds.removeFirst() }
    defer { if session == current { busy = false } }
    running = false
    sessionState = .paused
    recorder.cancelTurn()
    edits.interrupt()
    failures = 0
    question = .action
    intent = VoiceIntent()
    intent.action = action
    if action == .list { intent.date = Calendar.current.startOfDay(for: .now) }
    selected = nil
    candidates = []
    if action == .create {
      title = ""
      await advanceCreation()
    } else {
      await findEvents()
    }
  }
  private func findEvents() async {
    if intent.action == .next || intent.action == .list {
      await answerCalendar(
        CalendarQuestion(
          detail: intent.action == .next ? .next : .list, date: intent.date,
          days: intent.action == .next && intent.date == nil ? 90 : 1,
          calendarName: intent.calendarName))
      return
    }
    let current = session
    do {
      let start = intent.date ?? Calendar.current.startOfDay(for: .now)
      let end = Calendar.current.date(
        byAdding: .day, value: intent.date == nil && intent.action != .list ? 90 : 1, to: start)!
      let iso = ISO8601DateFormatter()
      let response = try await core.eventRequest(
        "queryCalendarEvents",
        ["start_utc": iso.string(from: start), "end_utc": iso.string(from: end)],
        as: CalendarQueryResponse.self)
      var found = response.events
      guard session == current else { return }
      if let name = intent.calendarName {
        found = found.filter { VoiceRules.normalized($0.calendar_title) == name }
      }
      if intent.action == .next {
        found = found.filter { $0.values.end > .now }
        candidates = Array(found.prefix(1))
      } else {
        if let minutes = intent.referenceTime {
          found = found.filter {
            Calendar.current.component(.hour, from: $0.values.start) * 60
              + Calendar.current.component(.minute, from: $0.values.start) == minutes
          }
        }
        let terms = VoiceRules.referenceWords(intent.referenceText)
        if !terms.isEmpty {
          found = found.filter { event in
            terms.allSatisfy { VoiceRules.normalized(event.values.title).contains($0) }
          }
        }
        if let name = intent.calendarName {
          found = found.filter { VoiceRules.normalized($0.calendar_title) == name }
        }
        candidates = found
      }
      if candidates.isEmpty {
        say(
          response.warning + "In diesem Zeitraum wurden keine passenden lesbaren Termine gefunden.",
          question: .action)
        return
      }
      if intent.action == .next || intent.action == .list {
        say(
          response.warning + candidates.prefix(5).map(\.spoken).joined(separator: " ")
            + (candidates.count > 5 ? " Weitere Termine stehen auf dem Bildschirm." : ""),
          question: .action)
      } else if candidates.count == 1 {
        await choose(candidates[0])
      } else {
        say(
          VoiceAddress.saved().choose("Welchen Termin meinst du?", "Welchen Termin meinen Sie?"),
          question: .event)
      }
    } catch { if session == current { say(userMessage(error), question: .action) } }
  }
  func choose(_ event: CalendarEvent) async {
    let current = session
    selected = event
    failures = 0
    if intent.action == .remove {
      await edits.preview(kind: "remove", calendar: event.calendar_id, event: event, patch: [:])
      if session == current { presentProposal() }
    } else if intent.action == .update {
      await advance()
    } else {
      say(event.spoken, question: .action)
    }
  }
  func editSlots() async {
    recorder.cancelTurn()
    failures = 0
    switch question {
    case .title:
      guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
      intent.title = title
      intent.origins["title"] = .choice
    case .date:
      intent.newDate = Calendar.current.startOfDay(for: date)
      intent.origins["new_date"] = .choice
    case .time:
      intent.newTime =
        Calendar.current.component(.hour, from: time) * 60
        + Calendar.current.component(.minute, from: time)
      intent.origins["new_time"] = .choice
    case .duration:
      guard duration > 0 else { return }
      intent.duration = duration
      intent.origins["duration"] = .choice
    default: break
    }
    await advance()
  }
  private func advanceCreation() async {
    if intent.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
      say("Wie heißt der Termin?", question: .title)
    } else if intent.newDate == nil {
      say(
        VoiceAddress.saved().choose(
          "An welchem Datum hast du den Termin?", "An welchem Datum haben Sie den Termin?"),
        question: .date)
    } else if intent.newTime == nil {
      say("Um welche Uhrzeit beginnt der Termin?", question: .time)
    } else if intent.duration == nil {
      say("Wie viele Minuten dauert der Termin?", question: .duration)
    } else {
      await prepare()
    }
  }
  private func advance() async {
    if intent.action == .create {
      await advanceCreation()
    } else if intent.action == .update {
      if intent.newTime == nil && intent.newDate == nil && intent.title == nil
        && intent.duration == nil
      {
        say("Auf welche Uhrzeit soll der Termin verschoben werden?", question: .time)
      } else {
        await prepare()
      }
    }
  }
  private func prepare() async {
    let current = session
    let calendar = Calendar.current
    if intent.newDate == nil && selected != nil { intent.origins["new_date"] = .context }
    if intent.newTime == nil && selected != nil { intent.origins["new_time"] = .context }
    if intent.duration == nil && selected != nil { intent.origins["duration"] = .context }
    let base = intent.newDate ?? selected?.values.start ?? date
    let minutes =
      intent.newTime ?? selected.map {
        calendar.component(.hour, from: $0.values.start) * 60
          + calendar.component(.minute, from: $0.values.start)
      } ?? 0
    let hour = minutes / 60
    let minute = minutes % 60
    guard let start = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base),
      calendar.component(.hour, from: start) == hour,
      calendar.component(.minute, from: start) == minute
    else {
      say(
        "Diese Uhrzeit gibt es wegen der Zeitumstellung nicht. Bitte eine andere Zeit wählen.",
        question: .time)
      return
    }
    let length =
      intent.duration.map { Double($0) * 60 } ?? selected.map {
        $0.values.end.timeIntervalSince($0.values.start)
      } ?? 0
    guard length > 0 else {
      say("Wie viele Minuten dauert der Termin?", question: .duration)
      return
    }
    let iso = ISO8601DateFormatter()
    var patch: [String: JSONValue] = [:]
    let changesStart = intent.action == .create || intent.newTime != nil || intent.newDate != nil
    let effectiveStart = changesStart ? start : selected?.values.start ?? start
    if changesStart { patch["start_utc"] = .string(iso.string(from: start)) }
    if changesStart || intent.duration != nil {
      patch["end_utc"] = .string(iso.string(from: effectiveStart.addingTimeInterval(length)))
    }
    if let title = intent.title { patch["title"] = .string(title) }
    do {
      let p = try await core.preferences()
      guard session == current else { return }
      var target = selected?.calendar_id ?? p.calendarId
      if intent.action == .create, let name = intent.calendarName {
        let calendars = try JSONDecoder().decode(
          CalendarDestinations.self, from: await NativeBridge.request("eventCalendars")
        ).calendars.filter {
          VoiceRules.normalized($0.title) == name && $0.writable
            && (p.displayCalendarIds.contains($0.id) || p.calendarId == $0.id)
        }
        guard session == current else { return }
        guard calendars.count == 1 else {
          say(
            "Kalender nicht eindeutig ausgewählt. Bitte über Angaben direkt bearbeiten das Speicherziel wählen.",
            question: .action)
          return
        }
        target = calendars[0].id
      }
      if intent.action == .create {
        patch["title"] = .string(intent.title ?? "")
        patch["timezone"] = .string(calendar.timeZone.identifier)
        patch["location"] = .string("")
        patch["reminder_minutes"] = p.reminder.map { .number(Double($0)) } ?? .null
      }
      await edits.preview(
        kind: intent.action == .create ? "create" : "update", calendar: target, event: selected,
        patch: patch)
      if session == current { presentProposal() }
    } catch { if session == current { say(userMessage(error)) } }
  }
  private func presentProposal() {
    running = false
    sessionState = .paused
    recorder.cancelTurn()
    if let proposal = edits.proposal {
      say(proposal.conversationText(address: .saved()), question: .confirmation)
    } else if edits.systemEvent != nil {
      say("Einladungen und ganze Serien bitte im Systemkalender bearbeiten.", question: .action)
    } else {
      say(edits.error ?? "Bitte die Angaben auf dem Bildschirm prüfen.", question: .action)
    }
  }
  func confirmProposal() async {
    guard !busy else { return }
    let current = session
    recorder.cancelTurn()
    SpeechOutput.shared.stop()
    await edits.confirm()
    guard session == current else { return }
    candidates = []
    selected = nil
    say(edits.conversationResult ?? edits.error ?? "Bitte Kalender abgleichen.", question: .action)
  }
  func cancelSession(preserveResponse: Bool = false, reason: String = "action") {
    LocalDiagnostics.shared.record(.speechSession, .cancelled, correlation: session)
    #if DEBUG && targetEnvironment(simulator)
      if ProcessInfo.processInfo.arguments.contains("--agenda-fixture") {
        print("Voice session ended: \(reason), phase \(sessionState), question \(question)")
      }
    #endif
    let previousResponse = response
    let endedToken = modelToken
    running = false
    sessionState = .stopped
    turnTask?.cancel()
    turnTask = nil
    rounds = []
    modelToken = UUID()
    Task { await calendarConversation.clear(endedToken) }
    recorder.cancelTurn()
    edits.interrupt()
    busy = false
    session = UUID().uuidString
    revision += 1
    sequence += 1
    responseTask?.cancel()
    understanding.discard()
    responseTask = nil
    question = .action
    candidates = []
    selected = nil
    intent = VoiceIntent()
    title = ""
    failures = 0
    failure = nil
    response = preserveResponse ? previousResponse : ""
    if !preserveResponse { preparedResponse = ConversationReply() }
    SpeechOutput.shared.stop()
  }
}
