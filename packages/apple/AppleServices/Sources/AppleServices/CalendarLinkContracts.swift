import Foundation

public enum NativeOwnedEventResolution: Sendable {
  case found(NativeCalendarEvent)
  case deleted, unavailable

  var legacyValue: [String: Any] {
    get throws {
      switch self {
      case .found(let event): ["status": "found", "event": try event.legacyValue]
      case .deleted: ["status": "deleted"]
      case .unavailable: ["status": "unavailable"]
      }
    }
  }
}

public enum NativeCalendarLinkState: Sendable, Equatable {
  case found(calendarID: String, externalID: String, ownershipURL: String?)
  case unavailable(reason: String?)
}
public struct NativeCalendarLinkResult: Sendable, Equatable {
  public let id: String
  public let state: NativeCalendarLinkState
}
public struct NativeCalendarLinkInspection: Sendable, Equatable {
  public let calendarIDs: [String]
  public let results: [NativeCalendarLinkResult]
}
