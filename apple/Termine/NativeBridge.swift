import Foundation
import RehaCore
@preconcurrency import AppleServices

/// Only Rust worker threads use synchronous callbacks. EventKit remains owned
/// by AppleServices' serial queue; SwiftUI uses the asynchronous entry point.
final class NativeBridge: AppleHost, @unchecked Sendable {
    private final class ResultBox: @unchecked Sendable {
        let lock = NSLock()
        private var value: Result<Data, Error>?
        func set(_ result: Result<Data, Error>) { lock.lock(); value = result; lock.unlock() }
        func get() -> Result<Data, Error>? { lock.lock(); defer { lock.unlock() }; return value }
    }
    @MainActor static func request(_ command: String, _ arguments: [String: Any] = [:]) async throws -> Data {
        let data = try JSONSerialization.data(withJSONObject: arguments)
        return try await withCheckedThrowingContinuation { continuation in
            NativeServices.shared.perform(command, arguments: data) { continuation.resume(with: $0) }
        }
    }
    private func blocking(_ command: String, _ arguments: [String: Any] = [:]) throws -> [String: Any] {
        precondition(!Thread.isMainThread, "Native callbacks must not block the main thread")
        let gate = DispatchSemaphore(value: 0)
        let box = ResultBox()
        do {
            let data = try JSONSerialization.data(withJSONObject: arguments)
            DispatchQueue.main.async {
                NativeServices.shared.perform(command, arguments: data) { result in
                    box.set(result); gate.signal()
                }
            }
            guard gate.wait(timeout: .now() + 60) == .success, let result = box.get() else { throw AppError.UncertainWrite }
            let responseData = try result.get()
            return (try JSONSerialization.jsonObject(with: responseData, options: .fragmentsAllowed)) as? [String: Any] ?? [:]
        } catch let error as AppError { throw error }
        catch {
            let message = error.localizedDescription
            if message.contains("Kalenderzugriff") { throw AppError.PermissionDenied }
            throw AppError.Storage(message: message)
        }
    }

    static func values(_ value: EventValues) -> [String: Any] {
        ["title": value.title, "start_utc": value.startUtc, "end_utc": value.endUtc,
         "timezone": value.timezone, "location": value.location, "notes": value.notes,
         "reminder_minutes": value.reminderMinutes.map { $0 as Any } ?? NSNull()]
    }
    static func record(_ value: ImportRecord) -> [String: Any] {
        ["id": value.id, "status": value.status, "calendar_id": value.calendarId,
         "external_id": value.externalId.map { $0 as Any } ?? NSNull(), "approved": values(value.approved)]
    }
    static func preferences(_ value: Preferences) -> [String: Any] {
        ["enabled": value.appRemindersEnabled, "minutes": value.appReminderMinutes.map { $0 as Any } ?? NSNull(),
         "sound": value.reminderSound, "preview": value.reminderPreview]
    }
    static func parseValues(_ value: [String: Any]) throws -> EventValues {
        func string(_ key: String) throws -> String {
            guard let result = value[key] as? String else { throw AppError.Storage(message: "Kalenderantwort unvollständig.") }
            return result
        }
        return try EventValues(title: string("title"), startUtc: string("start_utc"), endUtc: string("end_utc"), timezone: string("timezone"), location: string("location"), notes: string("notes"), reminderMinutes: (value["reminder_minutes"] as? NSNumber)?.uint32Value)
    }
    func snapshot(records: [ImportRecord]) throws -> LiveCalendar {
        let response = try blocking("snapshot", ["records": records.map(Self.record)])
        let current = try (response["current"] as? [String: [String: Any]] ?? [:]).mapValues(Self.parseValues)
        return LiveCalendar(current: current, protectedIds: response["protected_ids"] as? [String] ?? [])
    }
    func calendarEventCall(command: String, arguments: String) throws -> String {
        let args = try JSONSerialization.jsonObject(with: Data(arguments.utf8)) as? [String: Any] ?? [:]
        let result = try blocking(command, args)
        return String(decoding: try JSONSerialization.data(withJSONObject: result), as: UTF8.self)
    }
    func apply(operation: CalendarOperation, recoveryOnly: Bool) throws -> CalendarResult {
        let args: [String: Any] = ["kind": operation.kind.wireValue, "id": operation.id, "calendar_id": operation.calendarId,
            "external_id": operation.externalId.map { $0 as Any } ?? NSNull(),
            "before": operation.before.map(Self.values) ?? NSNull() as Any,
            "after": operation.after.map(Self.values) ?? NSNull() as Any, "requires_resolution": operation.requiresResolution]
        let response = try blocking("apply", ["operation": args, "recovery_only": recoveryOnly])
        return CalendarResult(id: response["id"] as? String ?? operation.id, status: WriteStatus(wireValue: response["status"] as? String ?? "uncertain"), externalId: response["external_id"] as? String, error: response["error"] as? String)
    }
    func decodePhoto(bytes: Data) throws -> Data {
        let result = try blocking("decodePhoto", ["base64": bytes.base64EncodedString()])
        guard let encoded = result["base64"] as? String, let decoded = Data(base64Encoded: encoded) else { throw AppError.Validation(message: "Foto konnte nicht gelesen werden.") }
        return decoded
    }
    func syncAgenda(records: [ImportRecord], preferences: Preferences) throws {
        _ = try blocking("agenda", ["records": records.map(Self.record), "preferences": Self.preferences(preferences)])
    }
    func forgetCalendar() throws { _ = try blocking("forgetCalendar") }
    func overlaps(events: [String:EventValues], exclude: [String]) throws -> [CalendarOverlap] {
        let response=try blocking("overlaps",["events":events.mapValues(Self.values),"exclude":exclude])
        return (response["overlaps"] as? [[String:String]] ?? []).map {
            CalendarOverlap(appointmentId:$0["appointment_id"] ?? "",externalId:$0["external_id"] ?? "",title:$0["title"] ?? "",startUtc:$0["start_utc"] ?? "",endUtc:$0["end_utc"] ?? "")
        }
    }
}

struct AgendaResponse: Decodable, Sendable {
    let snapshot: AgendaSnapshot
    let reminders: ReminderStatus
    struct ReminderStatus: Decodable, Sendable {
        let authorization: String
        let enabled: Bool
        let error: String?
    }
}
struct CalendarDestinations: Decodable {
    struct Destination: Decodable, Identifiable {
        let id: String; let title: String; let source: String; let writable: Bool; let color_components: [Double]?
    }
    let calendars: [Destination]
    let dedicated_id: String?
    let setup_error: String?
}

func userMessage(_ error: Error) -> String {
    guard let app = error as? AppError else { return error.localizedDescription }
    switch app {
    case .Validation(let message), .Storage(let message): return message
    case .ExpiredScan: return "Dieser Plan wurde gelöscht oder ist noch nicht erkannt."
    case .StaleRevision: return "Es gibt neuere Änderungen. Lade den aktuellen Stand, bevor du erneut speicherst."
    case .StaleProposal: return "Die Prüfdaten wurden geändert. Erstelle eine neue Kalendervorschau."
    case .PermissionDenied: return "Kalenderzugriff fehlt. Erlaube den Zugriff oder exportiere eine ICS-Datei."
    case .UncertainWrite: return "Der Schreibstatus ist unklar. Gleiche den Kalender vor weiteren Änderungen ab."
    case .Busy: return "Eine Erkennung läuft bereits. Bitte warten oder abbrechen."
    case .Cancelled: return "Erkennung abgebrochen. Ein bereits erstellter Entwurf bleibt erhalten."
    }
}

extension OperationKind {
    var wireValue: String {
        switch self { case .create: "create"; case .update: "update"; case .remove: "remove"; case .unchanged: "unchanged"; case .keep: "keep"; case .protected: "protected"; case .ambiguous: "ambiguous"; case .conflict: "conflict" }
    }
}
extension WriteStatus {
    init(wireValue: String) {
        switch wireValue { case "saved": self = .saved; case "failed": self = .failed; case "conflict": self = .conflict; default: self = .uncertain }
    }
}

extension NativeApplication {
    func appendPages(id: String, pages: [String]) async throws -> Int {
        struct Response: Decodable { let count: Int }
        return try await eventRequest("appendPlanPages", ["id": id, "pages": pages], as: Response.self).count
    }
}
