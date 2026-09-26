import Foundation

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
