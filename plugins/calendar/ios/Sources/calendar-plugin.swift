import EventKit
import PhotosUI
import Tauri
import UIKit
import Vision
import WebKit

struct Values: Codable, Equatable {
  var title: String
  var start_utc: String
  var end_utc: String
  var timezone: String
  var location: String
  var notes: String
  var reminder_minutes: Int?
}
struct OwnedRecord: Decodable {
  let id: String
  let calendar_id: String
  let external_id: String?
  let approved: Values
}
struct SnapshotArgs: Decodable { let records: [OwnedRecord] }
struct CalendarArgs: Decodable { let dedicated: Bool? }
struct Operation: Decodable {
  let kind: String
  let id: String
  let calendar_id: String
  let external_id: String?
  let before: Values?
  let after: Values?
  let requires_resolution: Bool
}
struct WriteArgs: Decodable {
  let operation: Operation
  let recovery_only: Bool
}
struct PhotoArgs: Decodable { let base64: String }
struct ShareArgs: Decodable {
  let filename: String
  let content: String
}

final class CalendarPlugin: Plugin, UIImagePickerControllerDelegate, UINavigationControllerDelegate,
  PHPickerViewControllerDelegate
{
  private let store = EKEventStore()
  private let dedicatedCalendar = DedicatedCalendar()
  private let calendarQueue = DispatchQueue(label: "at.rehakalender.calendar")
  private weak var controller: UIViewController?
  private var captureInvoke: Invoke?
  private let iso = ISO8601DateFormatter()

  override func load(webview: WKWebView) {
    controller = webview.window?.rootViewController
    NotificationCenter.default.addObserver(
      forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
    ) { [weak self] _ in
      self?.captureInvoke?.reject("Aufnahme durch Hintergrundwechsel unterbrochen.")
      self?.captureInvoke = nil
    }
  }
  private func presenter() -> UIViewController? {
    var root =
      controller
      ?? UIApplication.shared.connectedScenes.compactMap {
        ($0 as? UIWindowScene)?.keyWindow?.rootViewController
      }.first
    while let presented = root?.presentedViewController { root = presented }
    return root
  }
  private func dictionary<T: Encodable>(_ value: T) throws -> [String: Any] {
    try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as! [String: Any]
  }
  private func values(_ event: EKEvent) -> Values {
    Values(
      title: event.title ?? "", start_utc: iso.string(from: event.startDate),
      end_utc: iso.string(from: event.endDate),
      timezone: event.timeZone?.identifier ?? "Europe/Vienna", location: event.location ?? "",
      notes: event.notes ?? "",
      reminder_minutes: event.alarms?.first.map { Int(-$0.relativeOffset / 60) })
  }
  private func marker(_ id: String) -> String { "reha-calendar://event/\(id)" }
  private func owns(_ event: EKEvent, _ id: String) -> Bool {
    event.url?.absoluteString == marker(id)
  }
  private func checkAccess(_ invoke: Invoke) -> Bool {
    guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
      invoke.reject("Kalenderzugriff fehlt. Vollzugriff erlauben oder ICS exportieren.")
      return false
    }
    return true
  }
  @objc func calendars(_ invoke: Invoke) throws {
    let args = try invoke.parseArgs(CalendarArgs.self)
    store.requestFullAccessToEvents { granted, error in
      guard granted else {
        invoke.reject(
          error?.localizedDescription ?? "Kalenderzugriff abgelehnt. ICS-Export bleibt verfügbar.")
        return
      }
      self.calendarQueue.async {
        var dedicatedID: String?
        var setupError: String?
        if args.dedicated == true {
          do {
            dedicatedID = try self.dedicatedCalendar.resolve(in: self.store).calendarIdentifier
          } catch {
            setupError = error.localizedDescription
          }
        }
        let calendars = self.store.calendars(for: .event).filter(\.allowsContentModifications).map {
          calendar in
          [
            "id": calendar.calendarIdentifier, "title": calendar.title,
            "source": calendar.source.title ?? "",
            "is_default": calendar.calendarIdentifier
              == self.store.defaultCalendarForNewEvents?.calendarIdentifier,
          ] as [String: Any]
        }
        var result: [String: Any] = ["calendars": calendars]
        if let dedicatedID { result["dedicated_id"] = dedicatedID }
        if let setupError { result["setup_error"] = setupError }
        invoke.resolve(result)
      }
    }
  }
  @objc func snapshot(_ invoke: Invoke) throws {
    let args = try invoke.parseArgs(SnapshotArgs.self)
    guard checkAccess(invoke) else { return }
    calendarQueue.async {
      var current: [String: Any] = [:]
      for record in args.records {
        if let external = record.external_id,
          let event = self.store.event(withIdentifier: external), self.owns(event, record.id),
          event.calendar.calendarIdentifier == record.calendar_id
        {
          current[record.id] = try? self.dictionary(self.values(event))
        }
      }
      invoke.resolve(["current": current])
    }
  }
  @objc func forgetCalendar(_ invoke: Invoke) {
    calendarQueue.async {
      self.dedicatedCalendar.forget()
      invoke.resolve()
    }
  }
  @objc func apply(_ invoke: Invoke) throws {
    let args = try invoke.parseArgs(WriteArgs.self)
    guard checkAccess(invoke) else { return }
    calendarQueue.async {
      let op = args.operation
      func finish(_ status: String, _ event: EKEvent? = nil, _ message: String? = nil) {
        var output: [String: Any] = ["id": op.id, "status": status]
        if let identifier = event?.eventIdentifier { output["external_id"] = identifier }
        if let message { output["error"] = message }
        invoke.resolve(output)
      }
      guard UUID(uuidString: op.id) != nil, !op.requires_resolution,
        ["create", "update", "remove"].contains(op.kind),
        let calendar = self.store.calendar(withIdentifier: op.calendar_id),
        calendar.allowsContentModifications
      else {
        finish("failed", nil, "Ungültiger Auftrag oder nicht beschreibbarer Kalender.")
        return
      }
      var existing: EKEvent?
      if let external = op.external_id { existing = self.store.event(withIdentifier: external) }
      if let event = existing,
        !self.owns(event, op.id) || event.calendar.calendarIdentifier != op.calendar_id
      {
        finish("conflict", nil, "Eintrag ist nicht diesem App-Import zugeordnet.")
        return
      }
      if op.kind == "create" || (args.recovery_only && existing == nil) {
        guard let expected = op.after ?? op.before,
          let date = self.iso.date(from: expected.start_utc)
        else {
          finish("failed", nil, "Datum fehlt.")
          return
        }
        let predicate = self.store.predicateForEvents(
          withStart: date.addingTimeInterval(-86400), end: date.addingTimeInterval(2 * 86400),
          calendars: [calendar])
        let matches = self.store.events(matching: predicate).filter { self.owns($0, op.id) }
        if matches.count > 1 {
          finish("conflict", nil, "Mehrere zugeordnete Einträge: manuell prüfen.")
          return
        }
        existing = matches.first ?? existing
      }
      if args.recovery_only {
        if op.kind == "remove" {
          finish(
            "uncertain", existing,
            "Löschstatus kann nicht sicher bewiesen werden. Im Kalender prüfen.")
          return
        }
        if let event = existing, let after = op.after, self.values(event) == after {
          finish("saved", event)
          return
        }
        finish(
          "uncertain", existing, "Schreibergebnis noch unklar. Kein neuer Termin wurde erstellt.")
        return
      }
      if op.kind == "create", let event = existing {
        if let after = op.after, self.values(event) == after {
          finish("saved", event)
        } else {
          finish("conflict", event, "Vorhandener App-Termin weicht ab.")
        }
        return
      }
      if op.kind != "create" {
        guard let event = existing, let before = op.before, self.values(event) == before else {
          finish(
            "conflict", existing,
            "Kalender wurde seit der Vorschau verändert. Vorschau erneut erstellen.")
          return
        }
      }
      do {
        if op.kind == "remove", let event = existing {
          try self.store.remove(event, span: .thisEvent, commit: true)
          finish("saved")
          return
        }
        guard let after = op.after, let start = self.iso.date(from: after.start_utc),
          let end = self.iso.date(from: after.end_utc), end > start,
          let timezone = TimeZone(identifier: after.timezone)
        else {
          finish("failed", nil, "Ungültige Terminzeit.")
          return
        }
        let event = existing ?? EKEvent(eventStore: self.store)
        event.calendar = calendar
        event.title = after.title
        event.startDate = start
        event.endDate = end
        event.timeZone = timezone
        event.location = after.location
        event.notes = after.notes
        event.url = URL(string: self.marker(op.id))
        if op.kind == "create" || op.before?.reminder_minutes != after.reminder_minutes {
          event.alarms = after.reminder_minutes.map { [EKAlarm(relativeOffset: -Double($0) * 60)] }
        }
        try self.store.save(event, span: .thisEvent, commit: true)
        finish("saved", event)
      } catch {
        finish("uncertain", existing, "EventKit konnte den Schreibstatus nicht sicher bestätigen.")
      }
    }
  }
  @objc func camera(_ invoke: Invoke) {
    DispatchQueue.main.async {
      guard self.captureInvoke == nil else {
        invoke.reject("Eine Aufnahme ist bereits geöffnet.")
        return
      }
      guard UIImagePickerController.isSourceTypeAvailable(.camera), let root = self.presenter()
      else {
        invoke.reject("Kamera nicht verfügbar. Foto importieren.")
        return
      }
      self.captureInvoke = invoke
      let picker = UIImagePickerController()
      picker.sourceType = .camera
      picker.delegate = self
      root.present(picker, animated: true)
    }
  }
  @objc func photos(_ invoke: Invoke) {
    DispatchQueue.main.async {
      guard self.captureInvoke == nil, let root = self.presenter() else {
        invoke.reject("Fotoauswahl nicht verfügbar.")
        return
      }
      self.captureInvoke = invoke
      var config = PHPickerConfiguration()
      config.filter = .images
      config.selectionLimit = 1
      config.preferredAssetRepresentationMode = .current
      let picker = PHPickerViewController(configuration: config)
      picker.delegate = self
      root.present(picker, animated: true)
    }
  }
  func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
    picker.dismiss(animated: true)
    captureInvoke?.reject("Aufnahme abgebrochen.")
    captureInvoke = nil
  }
  func imagePickerController(
    _ picker: UIImagePickerController,
    didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
  ) {
    picker.dismiss(animated: true)
    if let image = info[.originalImage] as? UIImage,
      let data = image.jpegData(compressionQuality: 0.96)
    {
      captureInvoke?.resolve(["base64": data.base64EncodedString(), "filename": "camera.jpg"])
    } else {
      captureInvoke?.reject("Aufnahme konnte nicht gelesen werden.")
    }
    captureInvoke = nil
  }
  func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    picker.dismiss(animated: true)
    let invoke = captureInvoke
    captureInvoke = nil
    guard let result = results.first else {
      invoke?.reject("Fotoauswahl abgebrochen.")
      return
    }
    result.itemProvider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) {
      data, _ in
      guard let data else {
        invoke?.reject("Foto nicht lokal verfügbar.")
        return
      }
      invoke?.resolve(["base64": data.base64EncodedString(), "filename": "photo-import.heic"])
    }
  }
  @objc func decodePhoto(_ invoke: Invoke) throws {
    let args = try invoke.parseArgs(PhotoArgs.self)
    guard let data = Data(base64Encoded: args.base64), data.count <= 40 * 1024 * 1024,
      let image = UIImage(data: data),
      image.size.width * image.scale * image.size.height * image.scale <= 50_000_000
    else {
      invoke.reject("Foto nicht lesbar oder zu groß.")
      return
    }
    let format = UIGraphicsImageRendererFormat()
    format.scale = image.scale
    format.opaque = true
    let upright = UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
      image.draw(at: .zero)
    }
    guard let png = upright.pngData() else {
      invoke.reject("Foto konnte nicht dekodiert werden.")
      return
    }
    invoke.resolve(["base64": png.base64EncodedString()])
  }
  @objc func recognize(_ invoke: Invoke) throws {
    let args = try invoke.parseArgs(PhotoArgs.self)
    guard let data = Data(base64Encoded: args.base64), let image = UIImage(data: data)?.cgImage
    else {
      invoke.reject("Bild für Vision fehlt.")
      return
    }
    DispatchQueue.global(qos: .userInitiated).async {
      let started = Date()
      let request = VNRecognizeTextRequest()
      request.recognitionLevel = .accurate
      request.recognitionLanguages = ["de-DE", "en-US"]
      request.usesLanguageCorrection = false
      do {
        try VNImageRequestHandler(cgImage: image).perform([request])
        var regions: [[String: Any]] = []
        var observations: [[String: Any]] = []
        for (index, observation) in (request.results ?? []).enumerated() {
          let candidates = observation.topCandidates(3)
          let bounds = observation.boundingBox
          let x = bounds.minX * Double(image.width)
          let y = (1 - bounds.maxY) * Double(image.height)
          let w = bounds.width * Double(image.width)
          let h = bounds.height * Double(image.height)
          let id = String(format: "region-%04d", index)
          regions.append([
            "id": id,
            "polygon": [
              ["x": x, "y": y], ["x": x + w, "y": y], ["x": x + w, "y": y + h],
              ["x": x, "y": y + h],
            ], "frame": "page", "kind": "text", "parent": "page", "children": [],
          ])
          observations.append([
            "id": "obs-\(id)", "text": candidates.first?.string ?? "", "region_ids": [id],
            "engine": "Apple Vision", "score": candidates.first?.confidence ?? 0,
            "alternatives": candidates.dropFirst().map(\.string),
          ])
        }
        invoke.resolve([
          "regions": regions, "observations": observations,
          "duration_ms": Int(Date().timeIntervalSince(started) * 1000),
          "manifest": [
            "engine": "Apple Vision", "revision": request.revision,
            "system_version": UIDevice.current.systemVersion, "language_correction": false,
          ],
        ])
      } catch { invoke.reject("Lokale Vision-Erkennung fehlgeschlagen.") }
    }
  }
  @objc func protectStorage(_ invoke: Invoke) throws {
    let root = try AppStorage.prepare()
    invoke.resolve(["path": root.path, "excluded_from_backup": true])
  }
  @objc func share(_ invoke: Invoke) throws {
    let args = try invoke.parseArgs(ShareArgs.self)
    let filename = URL(fileURLWithPath: args.filename).lastPathComponent
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent(filename)
    try args.content.write(to: url, atomically: true, encoding: .utf8)
    DispatchQueue.main.async {
      guard let root = self.presenter() else {
        try? FileManager.default.removeItem(at: directory)
        invoke.reject("Teilen nicht verfügbar.")
        return
      }
      let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
      sheet.popoverPresentationController?.sourceView = root.view
      sheet.completionWithItemsHandler = { _, _, _, _ in
        try? FileManager.default.removeItem(at: directory)
      }
      root.present(sheet, animated: true)
      invoke.resolve()
    }
  }
  @objc func deviceInfo(_ invoke: Invoke) {
    invoke.resolve([
      "model": UIDevice.current.model, "system": UIDevice.current.systemVersion,
      "physical_validation": false,
    ])
  }
}

@_cdecl("init_plugin_reha_calendar")
func initPlugin() -> Plugin { CalendarPlugin() }
