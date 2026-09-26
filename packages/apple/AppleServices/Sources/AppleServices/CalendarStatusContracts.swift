import Foundation

public enum NativeCalendarAccessStatus: String, Sendable {
  case fullAccess, denied, restricted, notDetermined
}

public struct NativeCalendarStatusItem: Sendable {
  public let id: String
  public let title: String
  public let writable: Bool
}

/// Observed EventKit state only; selection and pending journals belong to Core.
public struct NativeCalendarPlatformStatus: Sendable {
  public let access: NativeCalendarAccessStatus
  public let lastReadAt: String?
  public let calendars: [NativeCalendarStatusItem]
  public let unavailableCalendarIDs: [String]

  var legacyValue: [String: Any] {
    [
      "access": access.rawValue, "last_read_at": lastReadAt as Any? ?? NSNull(),
      "calendars": calendars.map {
        ["id": $0.id, "title": $0.title, "writable": $0.writable] as [String: Any]
      },
      "unavailable_calendar_ids": unavailableCalendarIDs,
    ]
  }
}
