#if DEBUG && REHA_CUSTOM_ASSISTANT_TRIAL && targetEnvironment(simulator)
  import Foundation
  import RehaCore

  /// An explicit simulator experiment. Recognition is scripted; provider, dialog,
  /// proposal UI and SpeechOutput are the app's actual implementations.
  @MainActor final class AssistantVoiceTrial {
    static var active: AssistantVoiceTrial?
    static let cases = [
      "calendar-audio", "minimal-create", "rename-confirm", "late-cancel", "live-confirm",
    ]
    static let query = "Zeige mir die Termine für übermorgen."
    static let room = "In welchem Raum ist dieser Termin?"
    static let rename = "Nicht löschen. Ändere nur den Namen dieses Termins in Gymnastik."
    static let create = "Bitte Gymnastik am 17.05.2031 um 8 Uhr eintragen."
    private(set) var status = "ready"
    private let runID: String
    private let scenario: String
    private let core: NativeApplication
    private let expectedModel: String
    private let signal: AssistantVoiceTrialSignal?
    private let calendar = FlowCalendar()
    private let input = FlowInput()
    private var model: VoiceModel!
    private var provider: TrialProvider!
    private var script: Task<Void, Never>?
    private var sampler: Task<Void, Never>?
    private var phase = 0
    private var cancelled = 0
    private var events: [[String: Any]] = []
    private var turns: [[String: Any]] = []
    private var admissions: [[String: Any]] = []
    private var previews: [[String: Any]] = []
    private var confirmations: [[String: Any]] = []
    private var audio: [[String: Any]] = []
    private var audioIndexes: [UUID: Int] = [:]
    private var completedAudio: Set<UUID> = []
    private var confirmationAudio: [String: Any]?
    private var readCount = 0
    private var redundantTitle = false
    private var lateYesDelivered = false
    private var lateYesSnapshot: [String: Any]?
    private var failure: String?
    private var liveSnapshots: [[String: Any]] = []
    private var cancelledSnapshot: [String: Any]?
    private var lateSnapshot: [String: Any]?
    private var lastWrite = ContinuousClock.now
    private var started = ContinuousClock.now

    static func makeIfRequested(core: NativeApplication) -> VoiceModel? {
      let args = ProcessInfo.processInfo.arguments
      func value(_ flag: String) -> String? {
        guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else {
          return nil
        }
        return args[index + 1]
      }
      guard let scenario = value("--assistant-voice-trial"), cases.contains(scenario),
        let id = value("--assistant-voice-run"), let uuid = UUID(uuidString: id),
        let expected = value("--assistant-voice-model"), !expected.isEmpty
      else { return nil }
      // SwiftUI can reconstruct NativeShell while retaining its State. Reuse the
      // one trial owner so a discarded initialValue cannot publish competing state.
      if let active, active.core === core, active.scenario == scenario,
        active.runID == uuid.uuidString.lowercased(), active.expectedModel == expected
      {
        return active.model
      }
      let trial = AssistantVoiceTrial(
        core: core, scenario: scenario, runID: uuid.uuidString.lowercased(), expectedModel: expected
      )
      active = trial
      return trial.model
    }

    private init(core: NativeApplication, scenario: String, runID: String, expectedModel: String) {
      self.core = core
      self.scenario = scenario
      self.runID = runID
      self.expectedModel = expectedModel
      self.signal = AssistantVoiceTrialSignal(runID: runID, scenario: scenario)
      calendar.events = [Self.event(room: "Raum 2.14")]
      let selected = AssistantProviderSelection.make(arguments: ["--assistant-model-trial"])
      provider = TrialProvider(base: selected, owner: self)
      if selected.identity.provider != "custom-qwen-trial"
        || selected.identity.model != expectedModel
        || !expectedModel.hasPrefix("assistant-development-002/")
        || selected.availability != .available
      {
        failure = "The exact available assistant-development-002 provider was not selected."
        status = "failed"
      }
      let base =
        scenario == "live-confirm"
        ? EventMutationClient(
          register: { try core.registerEventSession() },
          invalidate: { _ = try? core.invalidateEventSession(session: $0) },
          preview: { try await core.previewEventMutation(request: $0) },
          confirm: { try await core.confirmEventProposal(request: $0) },
          undo: { try await core.previewEventUndo(request: $0) })
        : calendar.client
      let client = EventMutationClient(
        register: base.register, invalidate: base.invalidate,
        preview: { [self] request in
          await captureLive("before-preview")
          let result = try await base.preview(request)
          if case .proposal(let value) = result {
            previews.append(try object(EventProposalView(value)))
          }
          save()
          return result
        },
        confirm: { [self] request in
          confirmations.append([
            "token": request.token, "confirmation": String(describing: request.confirmation),
            "phase": phase,
          ])
          save()
          let result = try await base.confirm(request)
          await captureLive("after-confirm")
          return result
        }, undo: base.undo)
      model = VoiceModel(
        dependencies: VoiceDependencies(
          now: { [calendar] in calendar.now }, calendar: { [calendar] in calendar.calendar },
          address: { .sie }, isVoiceOverRunning: { false },
          fetchCalendar: { [self] start, end, scope in try await fetch(start, end, scope) },
          preferences: { [self] in
            scenario == "live-confirm" ? try await core.preferences() : calendar.preferences()
          },
          destinations: { [] }, trace: { [weak self] in self?.trace($0) },
          errorMessage: { $0.localizedDescription }),
        understanding: provider, edits: EventSession(origin: "voice", client: client),
        recorder: input, output: SpeechOutput.shared)
      input.didBegin = { [weak self] in self?.beginScript() }
      sampler = Task { [weak self] in
        while !Task.isCancelled {
          guard let self else { return }
          self.sampleAudio()
          if self.started.duration(to: .now) > .seconds(240) {
            self.failure = "Trial observation deadline exceeded"
            self.status = "failed"
            self.script?.cancel()
            self.provider.releaseHeld()
            self.model.pauseSession()
            self.save()
            return
          }
          if self.lastWrite.duration(to: .now) > .milliseconds(250) { self.save() }
          try? await Task.sleep(for: .milliseconds(30))
        }
      }
      save()
    }

    private static func event(room: String) -> CalendarEvent {
      CalendarEvent(
        id: "trial-event", external_id: "trial-event", calendar_id: "visible",
        calendar_title: "Privat", source: "fixture",
        occurrence: "", recurring: false, system_only: false, writable: true,
        values: CalendarEventValues(
          title: "Physiotherapie", start_utc: "2031-05-17T08:00:00Z",
          end_utc: "2031-05-17T08:30:00Z", timezone: "Europe/Vienna", location: room,
          reminder_minutes: 10),
        metadata: .object([:]), fingerprint: room)
    }
    private func object<T: Encodable>(_ value: T) throws -> [String: Any] {
      guard
        let result = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
          as? [String: Any]
      else {
        throw InterpretationError.invalidRequest
      }
      return result
    }
    private func fetch(_ start: Date, _ end: Date, _ scope: AgendaSelection?) async throws
      -> CalendarQueryResponse
    {
      readCount += 1
      if scenario == "live-confirm" {
        return try await core.calendarEvents(from: start, to: end, expecting: scope)
      }
      return try calendar.fetch(start, end, scope)
    }
    private func captureLive(_ label: String) async {
      guard scenario == "live-confirm" else { return }
      do {
        let result = try await core.calendarEvents(
          from: calendar.now, to: calendar.now.addingTimeInterval(3 * 86400))
        liveSnapshots.append(["label": label, "events": try result.events.map(object)])
      } catch { failure = "Live calendar snapshot failed: \(error)" }
    }
    private func snapshot() -> [String: Any] {
      [
        "question": String(describing: model.question),
        "title": model.intent.title as Any? ?? NSNull(),
        "new_date": model.intent.newDate.map {
          CalendarConversation.day($0, calendar: calendar.calendar)
        } as Any? ?? NSNull(),
        "new_time": model.intent.newTime as Any? ?? NSNull(),
        "duration": model.intent.duration as Any? ?? NSNull(),
        "last_user": model.rounds.last?.user as Any? ?? NSNull(),
        "response_id": SpeechOutput.shared.responseID.uuidString,
        "response": model.response, "session": model.session, "running": model.isSessionRunning,
        "busy": model.busy, "proposal": model.edits.proposal?.token as Any? ?? NSNull(),
        "preview_count": previews.count, "confirmation_count": confirmations.count,
        "provider_admissions": admissions.count,
        "read_count": readCount, "audio_speaking": SpeechOutput.shared.speaking,
      ]
    }
    private func trace(_ event: VoiceTrace) {
      if case .playbackCompleted = event {
        let response = SpeechOutput.shared.responseID
        completedAudio.insert(response)
        events.append([
          "kind": "audio-completed", "response_id": response.uuidString, "phase": phase,
        ])
        return
      }
      guard case .cancelled(let reason) = event else { return }
      cancelled += 1
      events.append([
        "kind": "cancel", "session": reason, "confirmations": confirmations.count, "phase": phase,
      ])
      script?.cancel()
      script = nil
      phase += 1
      provider.releaseHeld()
      Task { [weak self] in
        guard let self else { return }
        await self.captureLive("after-cancel")
        if self.cancelledSnapshot == nil { self.cancelledSnapshot = self.snapshot() }
        self.status = "cancelled"
        self.save()
        if self.scenario == "late-cancel" {
          do {
            try await self.until { self.admissions.last?["delivery_returned"] as? Bool == true }
            try await Task.sleep(for: .milliseconds(100))
            self.lateSnapshot = self.snapshot()
            self.status = "late-drained"
          } catch {
            self.failure = "Late native delivery did not drain: \(error)"
            self.status = "failed"
          }
          self.save()
        }
      }
    }
    private func beginScript() {
      guard script == nil, failure == nil, phase < 2 else { return }
      status = "running"
      script = Task { [weak self] in
        guard let self else { return }
        do {
          switch self.scenario {
          case "calendar-audio":
            try await self.deliver(Self.query)
            self.calendar.events = [Self.event(room: "Raum 3.42")]
            try await self.deliver("Und der Raum dazu?")
            self.status = "flow-finished"
          case "minimal-create":
            try await self.deliver(Self.create)
            if self.model.question == .title {
              self.redundantTitle = true
              try await self.deliver("Gymnastik")
            }
            try await self.deliver("30 Minuten")
            try await self.until { self.model.edits.proposal != nil }
            // Deliver a late recognizer final, not a new microphone turn. The
            // proposal must still require its visible confirmation button.
            self.input.transcript = "Ja, speichern"
            self.lateYesDelivered = true
            await self.model.endTurn()
            try await self.waitForAudio()
            self.lateYesSnapshot = self.snapshot()
            self.status = "proposal"
          case "rename-confirm", "live-confirm":
            if self.scenario == "live-confirm" {
              try await self.deliver("Nächster Termin")
              try await self.deliver(Self.room)
            } else {
              try await self.deliver(Self.query)
            }
            try await self.deliver(Self.rename)
            try await self.until { self.model.edits.proposal != nil }
            self.status = "proposal"
          case "late-cancel":
            try await self.deliver(Self.query)
          default: throw InterpretationError.invalidRequest
          }
          self.save()
        } catch {
          if !Task.isCancelled {
            self.failure = String(describing: error)
            self.status = "failed"
            self.save()
          }
        }
        // Keep the finished script owner until an explicit cancel/restart.
      }
    }
    private func deliver(_ text: String) async throws {
      try Task.checkCancellation()
      if input.state != .recording { await model.beginTurn() }
      let words = text.split(separator: " ")
      let prefix = words.prefix(max(1, words.count / 2)).joined(separator: " ")
      for chunk in [prefix, text] {
        input.transcript = chunk
        events.append(["kind": "transcript-chunk", "text": chunk, "phase": phase])
        try await Task.sleep(for: .milliseconds(80))
      }
      await model.endTurn()
      try Task.checkCancellation()
      turns.append(["text": text, "phase": phase, "state": snapshot()])
      save()
      try await waitForAudio()
    }
    private func waitForAudio() async throws {
      try await until { !self.model.busy && !SpeechOutput.shared.speaking }
      guard SpeechOutput.shared.phase != .failed else { throw CocoaError(.featureUnsupported) }
      sampleAudio()
    }
    private func until(_ condition: () -> Bool) async throws {
      let deadline = ContinuousClock.now + .seconds(45)
      while !condition(), ContinuousClock.now < deadline {
        try Task.checkCancellation()
        try await Task.sleep(for: .milliseconds(30))
      }
      guard condition() else { throw InterpretationError.deadlineExceeded }
    }
    private func sampleAudio() {
      let output = SpeechOutput.shared
      guard !output.preparedReply.text.isEmpty else { return }
      let index: Int
      if let found = audioIndexes[output.responseID] {
        index = found
      } else {
        index = audio.count
        guard index < 64 else {
          failure = "Too many audio responses"
          return
        }
        audioIndexes[output.responseID] = index
        audio.append([
          "response_id": output.responseID.uuidString, "prepared_text": output.preparedReply.text,
          "prepared_speech": output.preparedReply.speech, "playing_frames": 0, "peak_level": 0.0,
        ])
      }
      audio[index]["spoken_text"] = output.spokenText
      audio[index]["phase"] = output.phase.rawValue
      audio[index]["completed"] = completedAudio.contains(output.responseID)
      if output.phase == .playing {
        audio[index]["playing_frames"] = (audio[index]["playing_frames"] as? Int ?? 0) + 1
        audio[index]["peak_level"] = max(audio[index]["peak_level"] as? Double ?? 0, output.level)
      }
      func words(_ value: String) -> [String] {
        value.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter {
          !$0.isEmpty
        }
      }
      let spoken = words(output.spokenText)
      if !confirmations.isEmpty, model.response.hasPrefix("Der Termin ist gespeichert."),
        !model.busy, output.phase == .idle, completedAudio.contains(output.responseID),
        !spoken.isEmpty,
        [words(output.preparedReply.text), words(output.preparedReply.speech)].contains(spoken),
        (audio[index]["playing_frames"] as? Int ?? 0) > 0,
        (audio[index]["peak_level"] as? Double ?? 0) > 0
      {
        confirmationAudio = [
          "response_id": output.responseID.uuidString, "response": model.response,
        ]
        status = "confirmed-audio-finished"
      }
    }
    private func save() {
      guard model != nil else { return }
      lastWrite = .now
      let report: [String: Any] = [
        "schema_version": 1, "run_id": runID, "case_id": scenario, "qualified": false,
        "full_voice_workflow": false, "real_asr": false, "human_listening": false,
        "provider": provider.identity.provider, "model_identity": provider.identity.model,
        "expected_model_identity": expectedModel,
        "voice_id": SpeechOutput.shared.voiceID, "voice_name": SpeechOutput.shared.voiceName,
        "voice_rate": SpeechOutput.shared.rate, "status": status,
        "failure": failure as Any? ?? NSNull(),
        "calendar_mode": scenario == "live-confirm" ? "owned-live-fixture" : "fake",
        "today": "2031-05-15", "timezone": "Europe/Vienna",
        "transcript_source": "scripted-recognizer-output",
        "events": events, "turns": turns, "admissions": admissions, "previews": previews,
        "confirmations": confirmations, "cancel_count": cancelled, "audio": audio,
        "confirmation_audio": confirmationAudio as Any? ?? NSNull(),
        "redundant_title_prompt": redundantTitle, "late_yes_delivered": lateYesDelivered,
        "late_yes_snapshot": lateYesSnapshot as Any? ?? NSNull(), "live_snapshots": liveSnapshots,
        "cancelled_snapshot": cancelledSnapshot as Any? ?? NSNull(),
        "late_snapshot": lateSnapshot as Any? ?? NSNull(), "state": snapshot(),
      ]
      do {
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
          .write(
            to: URL.documentsDirectory.appendingPathComponent(
              "assistant-voice-\(runID)-\(scenario).json"), options: .atomic)
        if signal?.publish(status) != true {
          failure = "Trial status channel unavailable"
          status = "failed"
        }
      } catch {
        status = "failed"
        failure = "Evidence write failed: \(error)"
      }
    }

    @MainActor private final class TrialProvider: InterpretationProvider {
      let base: any InterpretationProvider
      unowned let owner: AssistantVoiceTrial
      var identity: InterpretationIdentity { base.identity }
      var capabilities: Set<InterpretationCapability> { base.capabilities }
      var availability: InterpretationAvailability { base.availability }
      private var held: CheckedContinuation<Void, Never>?
      init(base: any InterpretationProvider, owner: AssistantVoiceTrial) {
        self.base = base
        self.owner = owner
      }
      func prepare() { base.prepare() }
      func discard() { base.discard() }
      func releaseHeld() {
        held?.resume()
        held = nil
      }
      func interpret(_ request: InterpretationRequest) async throws -> ConversationInterpretation {
        guard owner.admissions.count < 32 else { throw InterpretationError.invalidRequest }
        let index = owner.admissions.count
        owner.admissions.append([
          "text": request.text, "context": request.context, "history": request.history,
          "phase": owner.phase, "model_identity": identity.model, "status": "admitted",
        ])
        owner.save()
        do {
          let result = try await base.interpret(request)
          let context =
            try JSONSerialization.jsonObject(with: Data(request.context.utf8)) as? [String: Any]
          let references = (context?["last_page"] as? [[String: Any]] ?? []).compactMap {
            $0["reference"] as? String
          }
          let sample = InterpretationEvaluation.Sample(
            id: "voice", text: request.text,
            today: CalendarConversation.day(request.now, calendar: request.calendar),
            timezone: request.calendar.timeZone.identifier, references: references,
            selected: references.count == 1 ? references.first : nil)
          owner.admissions[index]["typed_result"] = try InterpretationEvaluation.operation(
            result, sample: sample)
          owner.admissions[index]["status"] = "returned"
          if owner.scenario == "late-cancel" {
            owner.status = "native-return-held"
            owner.save()
            await withCheckedContinuation { held = $0 }
          }
          owner.admissions[index]["delivery_returned"] = true
          owner.save()
          return result
        } catch {
          owner.admissions[index]["status"] = "error"
          owner.admissions[index]["error"] = String(describing: error)
          owner.admissions[index]["delivery_returned"] = true
          owner.save()
          throw error
        }
      }
    }
  }

#endif
