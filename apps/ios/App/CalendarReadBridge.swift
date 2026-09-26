import AppleServices
import Foundation
import RehaCore

extension NativeBridge {
  func queryCalendar(request: CalendarReadQuery) throws -> CalendarReadResult {
    let query = NativeCalendarQuery(
      calendarIDs: request.calendarIds, startUTC: request.startUtc,
      endUTC: request.endUtc, timezone: request.timezone,
      selectionRevision: request.selectionRevision,
      records: request.records.map(Self.nativeRecord))
    do {
      let result = try NativeServiceCall.waitValue(for: .queryEvents) { completion in
        NativeServices.shared.queryCalendar(query, completion: completion)
      }
      return CalendarReadResult(
        events: result.events.map(Self.readEvent),
        unavailableCalendarIds: result.unavailableCalendarIDs,
        unavailableEvents: result.unavailableEvents.map {
          CalendarReadUnavailableEvent(id: $0.id, startUtc: $0.startUTC, endUtc: $0.endUTC)
        })
    } catch { throw Self.appError(error) }
  }
  func resolveCalendarEvent(reference: CalendarReadReference) throws -> CalendarReadEvent? {
    let reference = NativeCalendarReference(
      calendarID: reference.calendarId,
      externalID: reference.externalId, occurrence: reference.occurrence,
      expectedStartUTC: reference.expectedStartUtc)
    do {
      let result = try NativeServiceCall.waitValue(for: .getEvent) { completion in
        NativeServices.shared.resolveCalendarEvent(reference, completion: completion)
      }
      return result.map(Self.readEvent)
    } catch { throw Self.appError(error) }
  }
  static func readEvent(_ event: NativeCalendarEvent) -> CalendarReadEvent {
    CalendarReadEvent(
      id: event.id, externalId: event.externalID, calendarId: event.calendarID,
      calendarTitle: event.calendarTitle, source: event.source, occurrence: event.occurrence,
      recurring: event.recurring, systemOnly: event.systemOnly, writable: event.writable,
      values: CalendarReadValues(
        title: event.values.title, startUtc: event.values.startUTC,
        endUtc: event.values.endUTC, timezone: event.values.timezone,
        location: event.values.location,
        reminderMinutes: event.values.reminderMinutes), metadataJson: event.metadataJSON,
      fingerprint: event.fingerprint, importId: event.importID)
  }
}
