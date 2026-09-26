import Foundation

public enum NativeReminderAuthorization: String, Sendable {
  case notDetermined, denied, authorized, provisional

  public var allowsReminders: Bool { self == .authorized || self == .provisional }
}

/// A system reservation and an observed delivery are different facts.
public struct NativeNotificationReceipt: Sendable {
  public let accepted: Bool
  public let delaySeconds: TimeInterval
  public let confirmedPending: Bool
  public let observedDelivered: Bool

  var legacyValue: [String: Any] {
    [
      "accepted": accepted, "delay_seconds": delaySeconds,
      "confirmed_pending": confirmedPending, "observed_delivered": observedDelivered,
    ]
  }
}

public struct NativeReminderStatus: Sendable {
  public let authorization: NativeReminderAuthorization
  public let enabled: Bool
  public let planned: Int
  public let confirmedPending: Int
  public let observedDelivered: Int
  public let scheduled: Int
  public let calendar: Int
  public let protected: Int
  public let error: String?
  public let migrationVersion: Int

  var legacyValue: [String: Any] {
    [
      "authorization": authorization.rawValue, "enabled": enabled, "planned": planned,
      "confirmed_pending": confirmedPending, "observed_delivered": observedDelivered,
      "delivery_observation":
        "Nur noch im Mitteilungszentrum vorhandene Zustellungen sind beobachtbar.",
      "scheduled": scheduled, "calendar": calendar, "protected": protected,
      "error": error as Any? ?? NSNull(), "migrationVersion": migrationVersion,
    ]
  }
}

/// The live status is passed between queues as values. JSON remains confined to
/// the existing compatibility entry point and the separate durable widget file.
public struct NativeAgendaStatus: Sendable {
  public let snapshot: AgendaSnapshot
  public let presentation: AgendaPresentation
  public let reminders: NativeReminderStatus

  var legacyValue: [String: Any] {
    get throws {
      [
        "snapshot": try JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)),
        "presentation": try JSONSerialization.jsonObject(
          with: JSONEncoder().encode(presentation)),
        "reminders": reminders.legacyValue,
      ]
    }
  }
}
