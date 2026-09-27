import Foundation
import RehaCore

enum VoiceRecordingState { case idle, preparing, recording, finishing }

@MainActor protocol VoiceRecording: AnyObject {
  var turnID: UUID { get set }
  var state: VoiceRecordingState { get }
  var transcript: String { get }
  var level: Double { get }
  var failure: String? { get }
  var contextualTitles: [String] { get set }
  var onEndpoint: (() -> Void)? { get set }
  var onBargeIn: (() -> Void)? { get set }
  var onFailure: ((String) -> Void)? { get set }
  func beginTurn(preRoll: Bool) async throws
  func endTurn() async throws -> String
  func monitorForInterruption()
  func cancelTurn()
}

@MainActor protocol VoiceSpeaking: AnyObject {
  var turnID: UUID { get set }
  var speaking: Bool { get }
  var responseID: UUID { get }
  var spokenText: String { get }
  var onFinished: (() -> Void)? { get set }
  var onFailure: ((String) -> Void)? { get set }
  func speak(_ reply: ConversationReply)
  func stop()
  func prepare()
}

extension VoiceSpeaking {
  func prepare() {}
}

enum VoiceTrace {
  case playbackCompleted(String)
  case interrupted(String, VoiceInterruptionReason)
  case recognitionStarted(String)
  case recognitionCompleted(String, Int)
  case interpretationStarted(String)
  case interpretationCompleted(String, Int)
  case interpretationFailed(String, Int)
  case calendarRead(String, Bool)
  case cancelled(String, VoiceCancellationReason)
}

// Stable technical categories; never include recognized words or error text.
enum VoiceCancellationReason: Int {
  case action = 1
  case spokenStop, tab, background, systemInterruption, routeChange
  case mediaReset, mediaLost, erase, settings
}
enum VoiceInterruptionReason: Int {
  case userPause = 1
  case microphoneFailure, playbackFailure, voiceOver, speechOnset
  case microphoneStartup, recognitionFinalization
}

struct VoiceCalendarDestination {
  let id: String
  let title: String
  let writable: Bool
}

/// Platform effects are supplied once. The production and deterministic runners
/// share the same rules, router, conversation state, preview and confirmation flow.
@MainActor struct VoiceDependencies {
  let now: () -> Date
  let calendar: () -> Calendar
  let address: () -> VoiceAddress
  let isVoiceOverRunning: () -> Bool
  let fetchCalendar: CalendarConversation.Fetch
  let preferences: () async throws -> Preferences
  let destinations: () async throws -> [VoiceCalendarDestination]
  let trace: (VoiceTrace) -> Void
  let errorMessage: (Error) -> String
  var planEvidence: PlanEvidenceAccess? = nil
}
