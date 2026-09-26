@preconcurrency import AppleServices
import Foundation
import RehaCore

/// Only Rust worker threads use synchronous callbacks. EventKit remains owned
/// by AppleServices' serial queue; SwiftUI uses the asynchronous entry point.
final class NativeBridge: AppleHost, Sendable {
  static func appError(_ error: Error) -> AppError {
    if let error = error as? AppError { return error }
    if let error = error as? NativeServiceError {
      switch error {
      case .permissionDenied: return .PermissionDenied
      case .invalidInput(let message): return .Validation(message: message)
      case .storage(let message): return .Storage(message: message)
      case .timeout(let operation): return .Timeout(operation: operation)
      case .uncertainWrite: return .UncertainWrite
      case .cancelled: return .Cancelled
      }
    }
    return .Storage(message: error.localizedDescription)
  }
  @MainActor static func request(_ command: String, _ arguments: [String: Any] = [:]) async throws
    -> Data
  {
    let data = try JSONSerialization.data(withJSONObject: arguments)
    return try await withCheckedThrowingContinuation { continuation in
      NativeServices.shared.perform(command, arguments: data) { continuation.resume(with: $0) }
    }
  }
  private func blocking(_ command: String, _ arguments: [String: Any] = [:]) throws -> [String: Any]
  {
    do {
      guard let operation = NativeOperation(rawValue: command) else {
        throw NativeServiceError.invalidInput("Unbekannte native Aktion.")
      }
      let data = try JSONSerialization.data(withJSONObject: arguments)
      let timeout =
        command == "recognize"
        ? min(60, max(0.001, (arguments["budget_ms"] as? Double ?? 60000) / 1000)) : 60
      let responseData = try NativeServiceCall.wait(for: operation, timeout: timeout) {
        completion in
        NativeServices.shared.perform(command, arguments: data, completion: completion)
      }
      let value = try JSONSerialization.jsonObject(with: responseData, options: .fragmentsAllowed)
      if value is NSNull { return [:] }
      guard let object = value as? [String: Any] else {
        throw NativeServiceError.storage("Native Antwort hat ein ungültiges Format.")
      }
      return object
    } catch { throw Self.appError(error) }
  }

  func calendarEventCall(command: String, arguments: String) throws -> String {
    let args = try JSONSerialization.jsonObject(with: Data(arguments.utf8)) as? [String: Any] ?? [:]
    let result = try blocking(command, args)
    return String(decoding: try JSONSerialization.data(withJSONObject: result), as: UTF8.self)
  }
  func decodePhoto(bytes: Data) throws -> Data {
    precondition(!Thread.isMainThread, "Photo decoding belongs to the Rust worker")
    do { return try NativePhoto.decode(bytes) } catch { throw Self.appError(error) }
  }

}

struct CalendarDestinations {
  struct Destination: Identifiable {
    let id: String
    let title: String
    let source: String
    let writable: Bool
    // swift-format-ignore: AlwaysUseLowerCamelCase
    let color_components: [Double]?
  }
  let calendars: [Destination]
}

func userMessage(_ error: Error) -> String {
  guard let app = error as? AppError else { return error.localizedDescription }
  switch app {
  case .Validation(let message), .Storage(let message): return message
  case .ExpiredScan: return "Dieser Plan wurde gelöscht oder ist noch nicht erkannt."
  case .StaleRevision:
    return "Es gibt neuere Änderungen. Vor erneutem Speichern den aktuellen Stand laden."
  case .StaleProposal: return "Die Prüfdaten wurden geändert. Erstelle eine neue Kalendervorschau."
  case .PermissionDenied:
    return "Kalenderzugriff fehlt. Zugriff erlauben oder eine ICS-Datei exportieren."
  case .Timeout: return "Die lokale Aktion hat zu lange gedauert. Bitte erneut versuchen."
  case .UncertainWrite:
    return "Der Schreibstatus ist unklar. Gleiche den Kalender vor weiteren Änderungen ab."
  case .Busy: return "Eine Erkennung läuft bereits. Bitte warten oder abbrechen."
  case .Cancelled: return "Erkennung abgebrochen. Ein bereits erstellter Entwurf bleibt erhalten."
  }
}

extension NativeApplication {
  func appendPages(id: String, pages: [String]) async throws -> Int {
    struct Response: Decodable { let count: Int }
    return try await eventRequest("appendPlanPages", ["id": id, "pages": pages], as: Response.self)
      .count
  }
}
