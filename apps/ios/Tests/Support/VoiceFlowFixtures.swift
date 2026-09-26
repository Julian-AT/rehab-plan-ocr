import Foundation
import RehaCore

#if REHA_PROVIDER_PROBE || (DEBUG && REHA_CUSTOM_ASSISTANT_TRIAL && targetEnvironment(simulator))
  // Deterministic recording, output, provider and calendar effects shared by
  // the host VoiceModel regressions and the explicitly selected app trial.
  @MainActor final class FlowInput: VoiceRecording {
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
    var didBegin: (() -> Void)?
    func beginTurn(preRoll: Bool) async throws {
      state = .recording
      didBegin?()
    }
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

  @MainActor final class FlowOutput: VoiceSpeaking {
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

  @MainActor final class FlowProvider: InterpretationProvider {
    let identity = InterpretationIdentity(
      provider: "flow-fixture", model: "invented", schemaVersion: 1)
    let capabilities: Set<InterpretationCapability> = [
      .calendar, .mutation, .conversation, .appHelp,
    ]
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

  @MainActor final class FlowCalendar {
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
        id: id, external_id: id, calendar_id: "visible", calendar_title: "Privat",
        source: "fixture",
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
      guard expected == nil || expected == scope else {
        throw CalendarQueryFailure.selectionChanged
      }
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

#endif
