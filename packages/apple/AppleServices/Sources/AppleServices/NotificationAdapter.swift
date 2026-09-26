import Foundation
@preconcurrency import UserNotifications

struct NotificationSnapshot {
  var authorization: String
  var pending: [UNNotificationRequest]
  var delivered: Set<String>
}

/// The notification service never blocks EventKit's serial queue.
protocol NotificationAdapter: Sendable {
  func snapshot() async -> NotificationSnapshot
  func add(_ request: UNNotificationRequest) async throws
  func removePending(_ ids: [String])
  func removeDelivered(_ ids: [String])
}

struct SystemNotificationAdapter: NotificationAdapter {
  func removePending(_ ids: [String]) {
    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
  }
  func removeDelivered(_ ids: [String]) {
    UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
  }
  func snapshot() async -> NotificationSnapshot {
    let center = UNUserNotificationCenter.current()
    async let settings = center.notificationSettings()
    async let pending = center.pendingNotificationRequests()
    async let delivered = center.deliveredNotifications()
    let authorization: String
    switch await settings.authorizationStatus {
    case .authorized: authorization = "authorized"
    case .provisional: authorization = "provisional"
    case .denied: authorization = "denied"
    default: authorization = "notDetermined"
    }
    return await NotificationSnapshot(
      authorization: authorization, pending: pending,
      delivered: Set(delivered.map { $0.request.identifier }))
  }
  func add(_ request: UNNotificationRequest) async throws {
    try await UNUserNotificationCenter.current().add(request)
  }
}
