import AppleServices
import Foundation
import RehaCore
import UIKit

extension LocalSpeechRecorder: VoiceRecording {}
extension SpeechOutput: VoiceSpeaking {}

extension VoiceModel {
  convenience init(core: NativeApplication) {
    self.init(
      dependencies: VoiceDependencies(
        now: { .now },
        calendar: {
          var calendar = Calendar(identifier: .gregorian)
          calendar.timeZone = .current
          return calendar
        }, address: { .saved() }, isVoiceOverRunning: { UIAccessibility.isVoiceOverRunning },
        fetchCalendar: { start, end, scope in
          try await core.calendarEvents(from: start, to: end, expecting: scope)
        }, preferences: { try await core.preferences() },
        destinations: {
          try await core.eventCalendars().map {
            VoiceCalendarDestination(id: $0.id, title: $0.title, writable: $0.writable)
          }
        },
        trace: { event in
          switch event {
          case .playbackCompleted(let session):
            LocalDiagnostics.shared.record(.playback, .completed, correlation: session)
          case .interrupted(let session, let reason):
            LocalDiagnostics.shared.record(
              .interruption, .completed, correlation: session, count: reason.rawValue)
          case .recognitionStarted(let session):
            LocalDiagnostics.shared.record(.speechRecognition, .started, correlation: session)
          case .recognitionCompleted(let session, let count):
            LocalDiagnostics.shared.record(
              .speechRecognition, .completed, correlation: session, count: count)
          case .interpretationStarted(let session):
            LocalDiagnostics.shared.record(.tools, .started, correlation: session)
          case .interpretationCompleted(let session, let action):
            LocalDiagnostics.shared.record(.tools, .completed, correlation: session, count: action)
          case .interpretationFailed(let session, let reason):
            LocalDiagnostics.shared.record(.tools, .failed, correlation: session, count: reason)
          case .calendarRead(let session, let completed):
            LocalDiagnostics.shared.record(
              .calendarRead, completed ? .completed : .started, correlation: session)
          case .cancelled(let session, let reason):
            LocalDiagnostics.shared.record(
              .speechSession, .cancelled, correlation: session, count: reason.rawValue)
          }
        }, errorMessage: userMessage,
        planEvidence: PlanEvidenceAccess(
          list: { try await core.archivePage(after: nil, limit: 5).plans },
          read: { try await core.planEvidence(request: $0) })),
      understanding: AssistantProviderSelection.make(),
      edits: EventSession(core: core, origin: "voice"),
      recorder: LocalSpeechRecorder(), output: SpeechOutput.shared)
  }
}
