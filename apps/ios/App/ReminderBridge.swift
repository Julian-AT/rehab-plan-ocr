import AppleServices
import Foundation

extension NativeBridge {
  @MainActor static func requestCalendarAccess() async throws {
    try await value { NativeServices.shared.requestCalendarAccess(completion: $0) }
  }
  @MainActor static func reminderStatus() async throws -> NativeAgendaStatus {
    try await value { NativeServices.shared.reminderStatus(completion: $0) }
  }
  @MainActor static func requestReminderPermission() async throws -> NativeAgendaStatus {
    try await value { NativeServices.shared.requestReminderPermission(completion: $0) }
  }
  @MainActor static func testReminder() async throws -> NativeNotificationReceipt {
    try await value { NativeServices.shared.testReminder(completion: $0) }
  }
  @MainActor static func pendingEventOpen(acknowledge: String? = nil) async throws -> String? {
    try await value {
      NativeServices.shared.pendingEventOpen(acknowledge: acknowledge, completion: $0)
    }
  }
  @MainActor private static func value<Value: Sendable>(
    _ start: (@escaping @Sendable (Result<Value, Error>) -> Void) -> Void
  ) async throws -> Value {
    do {
      return try await withCheckedThrowingContinuation { continuation in
        start { continuation.resume(with: $0) }
      }
    } catch { throw appError(error) }
  }
}
