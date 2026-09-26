import Foundation

#if canImport(RehaCore)
  import RehaCore
#endif

extension NativeApplication {
  /// The store resolves an existing import or explicit plan destination before
  /// falling back to the default for an unbound draft. Preview never saves.
  @MainActor func previewPlanReplacement(
    id: String, timezone: String, isCurrent: @MainActor () -> Bool
  ) async throws -> DraftPreview {
    func checkCurrent() throws {
      try Task.checkCancellation()
      guard isCurrent() else { throw CancellationError() }
    }
    try checkCurrent()
    let preferences = try await preferences()
    try checkCurrent()
    let target = try await planCalendar(id: id)
    try checkCurrent()
    guard !target.calendarId.isEmpty else {
      throw AppError.Validation(message: "Kalender zuerst beim Plan einrichten.")
    }
    let preview = try await previewReplacement(
      id: id, calendarId: target.calendarId, timezone: timezone, reminder: preferences.reminder)
    try checkCurrent()
    return preview
  }
}
