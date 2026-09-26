import Foundation
import os

public enum NativeServiceError: Error, LocalizedError, Sendable, Equatable {
  case permissionDenied
  case invalidInput(String)
  case storage(String)
  case timeout(String)
  case uncertainWrite
  case cancelled

  public var errorDescription: String? {
    switch self {
    case .permissionDenied: "Kalenderzugriff fehlt."
    case .invalidInput(let message), .storage(let message): message
    case .timeout: "Die lokale Aktion hat zu lange gedauert. Bitte erneut versuchen."
    case .uncertainWrite: "Schreibstatus unklar. Abgleich erforderlich."
    case .cancelled: "Aktion abgebrochen."
    }
  }
}

/// Command identity defines timeout semantics; localized error text never does.
public enum NativeOperation: String, Sendable {
  case eventCalendars, queryEvents, getEvent, mutateEvent, editSystemEvent
  case resolveOwnedEvent, inspectCalendarLinks, calendarStatus, calendars
  case snapshot, overlaps, forgetCalendar, apply, agenda, agendaPresentation
  case enableReminders, requestReminderPermission, reminderStatus, pendingEventOpen, testReminder
  case camera, photos, decodePhoto, recognize, protectStorage, share, deviceInfo

  var timeoutFailure: NativeServiceError {
    switch self {
    case .apply, .mutateEvent, .editSystemEvent, .agenda, .enableReminders, .calendars:
      .uncertainWrite
    default: .timeout(rawValue)
    }
  }
}

/// Adapter for synchronous FFI workers only; never call from an async task or UI
/// thread. Completion state is owned by the lock; late replies are discarded.
public enum NativeServiceCall {
  public typealias Completion = @Sendable (Result<Data, Error>) -> Void
  private enum State { case waiting, completed(Result<Data, Error>), expired }

  public static func wait(
    for operation: NativeOperation, timeout: TimeInterval = 60,
    start: (@escaping Completion) -> Void
  ) throws -> Data {
    precondition(!Thread.isMainThread, "Native callbacks must not block the main thread")
    guard timeout.isFinite, timeout > 0 else {
      throw NativeServiceError.invalidInput("Zeitbudget ungültig.")
    }
    let state = OSAllocatedUnfairLock<State>(initialState: .waiting)
    let gate = DispatchSemaphore(value: 0)
    start { result in
      let accepted = state.withLock { state in
        guard case .waiting = state else { return false }
        state = .completed(result)
        return true
      }
      if accepted { gate.signal() }
    }
    _ = gate.wait(timeout: .now() + timeout)
    let result: Result<Data, Error>? = state.withLock { state in
      if case .completed(let result) = state { return result }
      state = .expired
      return nil
    }
    guard let result else { throw operation.timeoutFailure }
    return try result.get()
  }
}
