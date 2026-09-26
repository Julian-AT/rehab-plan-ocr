import Foundation
import RehaCore

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
    await mutationRouting()
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

    for (input, title) in [
      ("Nicht löschen. Ändere nur den Namen dieses Termins in Gymnastik.", "Gymnastik"),
      ("Bitte nicht entfernen, benenne diesen Termin nur in Ergotherapie um.", "Ergotherapie"),
      (
        "Löschen Sie diesen Termin nicht; geben Sie diesem Termin nur den Namen Atemübung.",
        "Atemübung"
      ),
      (
        "Den Termin nicht löschen, sondern ändere nur den Titel dieses Termins auf „Sanfte Bewegung“.",
        "Sanfte Bewegung"
      ),
    ] {
      let rename = Flow()
      rename.provider.availability = .unavailable("No model assets")
      await rename.model.submitText("Nächster Termin")
      await rename.model.submitText(input)
      let proposal = rename.model.edits.proposal!
      precondition(proposal.kind == "update" && proposal.before?.id == "physio", input)
      precondition(
        proposal.patch.keys.sorted() == ["title"] && proposal.after?.title == title, input)
      precondition(proposal.after?.start_utc == proposal.before?.values.start_utc)
      precondition(proposal.after?.end_utc == proposal.before?.values.end_utc)
      precondition(proposal.after?.location == proposal.before?.values.location)
      precondition(proposal.after?.reminder_minutes == proposal.before?.values.reminder_minutes)
      precondition(rename.model.question == .confirmation && rename.calendar.confirmed.isEmpty)
      precondition(rename.provider.requests.isEmpty, "Complete rename rule started a model")
      rename.input.transcript = "Ja, speichern"
      await rename.model.endTurn()
      precondition(
        rename.calendar.confirmed.isEmpty && rename.model.response.contains("Schaltfläche"))
      await rename.model.confirmProposal()
      precondition(
        rename.calendar.confirmed.count == 1 && rename.model.response.contains("gespeichert"))
    }
    let renameText = "Nicht löschen. Ändere nur den Namen dieses Termins in Spaziergang."
    for previous in ["", "Termine heute"] {
      let ambiguous = Flow()
      ambiguous.provider.availability = .unavailable("No model assets")
      if !previous.isEmpty { await ambiguous.model.submitText(previous) }
      let reads = ambiguous.calendar.reads
      await ambiguous.model.submitText(renameText)
      precondition(ambiguous.calendar.previews.isEmpty && ambiguous.calendar.confirmed.isEmpty)
      precondition(ambiguous.calendar.reads == reads && ambiguous.provider.requests.isEmpty)
    }
    let staleRename = Flow()
    await staleRename.model.submitText("Nächster Termin")
    staleRename.calendar.events.removeFirst()
    await staleRename.model.submitText(renameText)
    precondition(staleRename.calendar.previews.isEmpty && staleRename.calendar.confirmed.isEmpty)
    let canceledRename = Flow()
    await canceledRename.model.submitText("Nächster Termin")
    await canceledRename.model.submitText(renameText)
    precondition(canceledRename.model.edits.proposal != nil)
    canceledRename.model.cancelSession()
    await canceledRename.model.confirmProposal()
    precondition(canceledRename.calendar.confirmed.isEmpty)
    let pendingTitle = Flow()
    await pendingTitle.model.submitAction(.create)
    precondition(pendingTitle.model.question == .title)
    await pendingTitle.model.submitText(renameText)
    precondition(
      pendingTitle.model.question == .action && pendingTitle.model.intent.action == .unsupported)
    precondition(pendingTitle.calendar.previews.isEmpty && pendingTitle.calendar.confirmed.isEmpty)
    let pendingTime = Flow()
    await pendingTime.model.submitAction(.update)
    await pendingTime.model.submitText("den ersten")
    precondition(pendingTime.model.question == .time)
    await pendingTime.model.submitText(
      "Nicht löschen. Ändere nur den Namen dieses Termins in „Halb zehn“.")
    precondition(
      pendingTime.model.question == .action && pendingTime.model.intent.action == .unsupported)
    precondition(pendingTime.calendar.previews.isEmpty && pendingTime.calendar.confirmed.isEmpty)
    for input in [
      "Nicht löschen. Ändere nur den Namen des anderen Termins in Gymnastik.",
      "Nicht löschen. Ändere nur die Namen dieser Termine in Gymnastik.",
      "Nicht löschen. Ändere nur den Namen dieses Termins nicht in Gymnastik.",
      "Nicht löschen. Ändere nur den Namen dieses Termins in Gymnastik und ändere die Dauer.",
      "Nicht löschen. Ändere nur den Namen dieses Termins in Gymnastik, nein Spaziergang.",
      "Nicht löschen. Ändere nur den Namen dieses Termins in irgendwas.",
      "Stopp, nicht löschen. Ändere nur den Namen dieses Termins in Gymnastik.",
    ] {
      let rejected = Flow()
      await rejected.model.submitText("Nächster Termin")
      await rejected.model.submitText(input)
      precondition(rejected.calendar.previews.isEmpty && rejected.calendar.confirmed.isEmpty, input)
    }

    let creation = Flow()
    creation.provider.availability = .unavailable("No model assets")
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
    precondition(creation.provider.requests.isEmpty)
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

  /// These are deterministic typed provider fakes, not model-quality evidence.
  @MainActor private static func mutationRouting() async {
    let knownCreate = "Bitte Gymnastik am 17.05.2031 um 8 Uhr eintragen."
    for (text, title, date, minutes) in [
      (knownCreate, "Gymnastik", "2031-05-17", 480),
      (
        "Kannst du bitte Ergotherapie morgen um halb zehn eintragen?", "Ergotherapie", "2031-05-16",
        570
      ),
      ("Ich möchte Atemübung am 18.05.2031 um 09:15 hinzufügen.", "Atemübung", "2031-05-18", 555),
    ] {
      let flow = Flow()
      let day = CalendarConversation.civilDate(date, calendar: flow.calendar.calendar)!
      flow.provider.reply = { _ in
        ConversationInterpretation(
          action: .create,
          change: VoiceIntent(
            action: .create, newDate: day, newTime: minutes, title: title,
            timezone: "Europe/Vienna"))
      }
      await flow.model.submitText(text)
      precondition(flow.provider.requests.count == 1 && flow.provider.requests[0].text == text)
      precondition(flow.model.intent.title == title && flow.model.intent.newDate == day)
      precondition(flow.model.intent.newTime == minutes && flow.model.intent.duration == nil)
      precondition(flow.model.question == .duration && flow.calendar.previews.isEmpty)
      await flow.model.submitText("30 Minuten")
      let proposal = flow.model.edits.proposal!
      precondition(proposal.kind == "create" && proposal.after?.title == title)
      let start = proposal.after!.start
      precondition(flow.calendar.calendar.startOfDay(for: start) == day)
      precondition(
        flow.calendar.calendar.component(.hour, from: start) * 60
          + flow.calendar.calendar.component(.minute, from: start) == minutes)
      precondition(proposal.after!.end.timeIntervalSince(start) == 1800)
      precondition(flow.provider.requests.count == 1 && flow.calendar.confirmed.isEmpty)
      precondition(flow.model.question == .confirmation)
      flow.input.transcript = "Ja, speichern"
      await flow.model.endTurn()
      precondition(flow.calendar.confirmed.isEmpty && flow.model.edits.proposal != nil)
      await flow.model.confirmProposal()
      precondition(flow.calendar.confirmed.count == 1)
    }

    for (text, removal) in [
      ("Bitte verschiebe diesen Termin auf morgen um elf Uhr.", false),
      ("Bitte diesen Termin löschen.", true),
    ] {
      let flow = Flow()
      await flow.model.submitText("Nächster Termin")
      let day = CalendarConversation.civilDate("2031-05-16", calendar: flow.calendar.calendar)!
      flow.provider.reply = { _ in
        ConversationInterpretation(
          action: removal ? .remove : .update,
          query: CalendarQuestion(usesLastPage: true, timezone: "Europe/Vienna"),
          change: removal
            ? nil
            : VoiceIntent(
              action: .update, newDate: day, newTime: 660,
              timezone: "Europe/Vienna"))
      }
      let reads = flow.calendar.reads
      await flow.model.submitText(text)
      let proposal = flow.model.edits.proposal!
      precondition(flow.provider.requests.count == 1 && flow.calendar.reads > reads)
      precondition(proposal.before?.id == "physio" && flow.model.question == .confirmation)
      precondition(proposal.patch.keys.sorted() == (removal ? [] : ["end_utc", "start_utc"]))
      if !removal {
        precondition(proposal.after?.start_utc == "2031-05-16T09:00:00Z")
        precondition(proposal.after?.end_utc == "2031-05-16T09:30:00Z")
        precondition(proposal.after?.title == proposal.before?.values.title)
        precondition(proposal.after?.location == proposal.before?.values.location)
        precondition(proposal.after?.reminder_minutes == proposal.before?.values.reminder_minutes)
      }
      precondition(flow.calendar.confirmed.isEmpty)
      flow.model.cancelSession()
      await flow.model.confirmProposal()
      precondition(flow.model.edits.proposal == nil && flow.calendar.confirmed.isEmpty)
    }

    for field in ["title", "duration", "time"] {
      let flow = Flow()
      await flow.model.submitText("Nächster Termin")
      let day = CalendarConversation.civilDate("2031-05-16", calendar: flow.calendar.calendar)!
      flow.provider.reply = { _ in
        ConversationInterpretation(
          action: .update,
          query: CalendarQuestion(usesLastPage: true, timezone: "Europe/Vienna"),
          change: VoiceIntent(
            action: .update, newDate: day,
            newTime: field == "time" ? 720 : 660,
            duration: field == "duration" ? 60 : nil,
            title: field == "title" ? "Termin" : nil, timezone: "Europe/Vienna"))
      }
      await flow.model.submitText("Bitte verschiebe diesen Termin auf morgen um elf Uhr.")
      precondition(flow.provider.requests.count == 1 && flow.model.question == .action, field)
      precondition(flow.calendar.previews.isEmpty && flow.calendar.confirmed.isEmpty)
    }

    // Invalid typed model fields cannot fall back to the old partial parser.
    for wrongField in ["title", "date", "time", "duration"] {
      let flow = Flow()
      let day = CalendarConversation.civilDate(
        wrongField == "date" ? "2031-05-18" : "2031-05-17",
        calendar: flow.calendar.calendar)!
      flow.provider.reply = { _ in
        ConversationInterpretation(
          action: .create,
          change: VoiceIntent(
            action: .create,
            newDate: day, newTime: wrongField == "time" ? 600 : 480,
            duration: wrongField == "duration" ? 30 : nil,
            title: wrongField == "title" ? "Ergotherapie" : "Gymnastik", timezone: "Europe/Vienna"))
      }
      await flow.model.submitText(knownCreate)
      precondition(flow.provider.requests.count == 1 && flow.model.question == .action, wrongField)
      precondition(flow.model.intent.action == .unsupported && flow.calendar.previews.isEmpty)
      precondition(flow.calendar.confirmed.isEmpty)
    }
    for text in [
      "Bitte diesen Termin nicht löschen.",
      "Bitte den ersten oder den zweiten Termin löschen.",
      "Bitte den anderen Termin löschen.",
      "Bitte diesen Termin löschen und einen neuen Termin erstellen.",
      "Stopp, bitte diesen Termin löschen.",
    ] {
      let flow = Flow()
      await flow.model.submitText("Termine heute")
      flow.provider.reply = { _ in
        ConversationInterpretation(
          action: .remove,
          query: CalendarQuestion(reference: "r1", timezone: "Europe/Vienna"))
      }
      await flow.model.submitText(text)
      precondition(flow.calendar.previews.isEmpty && flow.calendar.confirmed.isEmpty, text)
      precondition(flow.provider.requests.count <= 1)
    }
    let stale = Flow()
    await stale.model.submitText("Nächster Termin")
    stale.calendar.events.removeFirst()
    stale.provider.reply = { _ in
      ConversationInterpretation(
        action: .remove,
        query: CalendarQuestion(usesLastPage: true, timezone: "Europe/Vienna"))
    }
    await stale.model.submitText("Bitte diesen Termin löschen.")
    precondition(stale.provider.requests.count == 1 && stale.calendar.previews.isEmpty)

    // Complete commands and targeted slots keep working with no model installed.
    for text in [
      "Erstelle einen Termin namens Sanfte Gymnastik morgen um zehn Uhr für 30 Minuten.",
      "Verschiebe meine Physiotherapie heute auf morgen um elf Uhr",
      "Lösche meine Physiotherapie heute",
    ] {
      let flow = Flow()
      flow.provider.availability = .unavailable("No model assets")
      await flow.model.submitText(text)
      precondition(flow.model.question == .confirmation && flow.model.edits.proposal != nil, text)
      precondition(flow.provider.requests.isEmpty && flow.calendar.confirmed.isEmpty)
    }
    for text in [
      knownCreate, "Bitte verschiebe diesen Termin auf morgen um elf Uhr.",
      "Bitte diesen Termin löschen.",
    ] {
      let unavailable = Flow()
      unavailable.provider.availability = .unavailable("No model assets")
      await unavailable.model.submitText(text)
      precondition(unavailable.model.rounds.last?.user == text)
      precondition(unavailable.model.response.contains("No model assets"))
      precondition(unavailable.model.question == .action && unavailable.provider.requests.isEmpty)
      precondition(unavailable.calendar.previews.isEmpty && unavailable.calendar.confirmed.isEmpty)
    }
    let failure = Flow()
    failure.provider.reply = { _ in throw InterpretationError.invalidRequest }
    await failure.model.submitText(knownCreate)
    precondition(failure.provider.requests.count == 1 && failure.model.question == .action)
    precondition(failure.calendar.previews.isEmpty && failure.calendar.confirmed.isEmpty)

    let late = Flow()
    var pending: CheckedContinuation<ConversationInterpretation, Never>?
    var returned = false
    late.provider.reply = { _ in
      let result = await withCheckedContinuation { pending = $0 }
      returned = true
      return result
    }
    let task = Task { await late.model.submitText(knownCreate) }
    await until { pending != nil }
    late.model.cancelSession()
    await late.model.submitText("Termine heute")
    let response = late.model.response
    pending!.resume(
      returning: ConversationInterpretation(
        action: .create,
        change: VoiceIntent(
          action: .create,
          newDate: CalendarConversation.civilDate("2031-05-17", calendar: late.calendar.calendar),
          newTime: 480, title: "Gymnastik", timezone: "Europe/Vienna")))
    await until { returned }
    await task.value
    precondition(late.provider.requests.count == 1 && late.model.response == response)
    precondition(late.model.question == .action && late.model.intent.action == .unsupported)
    precondition(late.calendar.previews.isEmpty && late.calendar.confirmed.isEmpty)
  }
}
