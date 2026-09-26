import AppleServices
import Foundation
import RehaCore

extension NativeBridge {
  func eventCalendars() throws -> [EventCalendarDestination] {
    do {
      let result = try NativeServiceCall.waitValue(for: .eventCalendars) { completion in
        NativeServices.shared.eventCalendars(completion: completion)
      }
      return result.map {
        EventCalendarDestination(
          id: $0.id, title: $0.title, source: $0.source,
          writable: $0.writable, colorComponents: $0.colorComponents)
      }
    } catch { throw Self.appError(error) }
  }
  func mutateEvent(request: EventMutationRequest) throws -> EventMutationResult {
    let proposal = request.proposal
    let kind: NativeEventMutationKind =
      switch proposal.kind {
      case .create: .create
      case .update: .update
      case .remove: .remove
      }
    let reminder: NativeEventReminderChange =
      switch proposal.patch.reminder {
      case .unchanged: .unchanged
      case .disabled: .disabled
      case .minutes(let minutes): .minutes(minutes)
      }
    let patch = proposal.patch
    let native = NativeEventMutationRequest(
      proposal: NativeEventEditProposal(
        token: proposal.token, session: proposal.session, revision: proposal.revision,
        expiresAt: proposal.expiresAt,
        kind: kind, calendarID: proposal.calendarId, calendarTitle: proposal.calendarTitle,
        before: proposal.before.map(Self.nativeEvent),
        patch: NativeEventEditPatch(
          title: patch.title, startUTC: patch.startUtc, endUTC: patch.endUtc,
          timezone: patch.timezone, location: patch.location, reminder: reminder),
        undoOf: proposal.undoOf, ownedID: proposal.ownedId, origin: proposal.origin),
      recoveryOnly: request.recoveryOnly)
    do {
      let result = try NativeServiceCall.waitValue(for: .mutateEvent) { completion in
        NativeServices.shared.mutateEvent(native, completion: completion)
      }
      let status: EventMutationStatus =
        switch result.status {
        case .saved: .saved
        case .failed: .failed
        case .uncertain: .uncertain
        case .conflict: .conflict
        case .acknowledged: .acknowledged
        }
      return EventMutationResult(
        status: status, event: result.event.map(Self.readEvent),
        operationId: result.operationID, message: result.message,
        maintenanceWarnings: result.maintenanceWarnings)
    } catch { throw Self.appError(error) }
  }
  static func nativeEvent(_ event: CalendarReadEvent) -> NativeCalendarEvent {
    NativeCalendarEvent(
      id: event.id, externalID: event.externalId, calendarID: event.calendarId,
      calendarTitle: event.calendarTitle, source: event.source, occurrence: event.occurrence,
      recurring: event.recurring, systemOnly: event.systemOnly, writable: event.writable,
      values: NativeCalendarValues(
        title: event.values.title, startUTC: event.values.startUtc,
        endUTC: event.values.endUtc, timezone: event.values.timezone,
        location: event.values.location,
        reminderMinutes: event.values.reminderMinutes), metadataJSON: event.metadataJson,
      fingerprint: event.fingerprint, importID: event.importId)
  }
}
