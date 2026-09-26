import AppleServices
import Foundation
import RehaCore

extension NativeBridge {
  func calendarStatus() throws -> CalendarPlatformStatus {
    do {
      let result = try NativeServiceCall.waitValue(for: .calendarStatus) { completion in
        NativeServices.shared.calendarStatus(completion: completion)
      }
      let access: CalendarAccessStatus =
        switch result.access {
        case .fullAccess: .fullAccess
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        }
      return CalendarPlatformStatus(
        access: access, lastReadAt: result.lastReadAt,
        calendars: result.calendars.map {
          CalendarStatusItem(id: $0.id, title: $0.title, writable: $0.writable)
        }, unavailableCalendarIds: result.unavailableCalendarIDs)
    } catch { throw Self.appError(error) }
  }
}
