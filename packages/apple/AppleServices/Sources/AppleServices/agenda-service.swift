import BackgroundTasks
import CryptoKit
import EventKit
import Foundation
import UIKit
@preconcurrency import UserNotifications
import WidgetKit

private struct AgendaPrivateState: Codable {
  var schemaVersion = 1
  var records: [OwnedRecord] = []
  var preferences = ReminderPreferences()
  var journal: [String: AlarmJournalEntry] = [:]
  var pendingOpen: String?
  var migrationVersion = 0
}
struct AgendaSyncArgs: Decodable {
  var records: [OwnedRecord]
  var preferences: ReminderPreferences
}

enum AgendaError: LocalizedError {
  case message(String)
  var errorDescription: String? {
    if case .message(let message) = self { return message }
    return nil
  }
}

// EventKit and the private write-ahead journal have one serial owner, including
// the existing calendar import bridge. Never wait for notification callbacks on main.
final class AgendaService: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
  static let shared = AgendaService()
  static let category = "REHA_APPOINTMENT"
  static let noSnoozeCategory = "REHA_APPOINTMENT_OPEN"
  static let backgroundID = "at.rehakalender.personal.agenda-refresh"
  let queue = DispatchQueue(label: "at.rehakalender.agenda")
  let store = EKEventStore()
  private let center = UNUserNotificationCenter.current()
  private let notifications: any NotificationAdapter
  private var notificationState = NotificationSnapshot(
    authorization: "notDetermined", pending: [], delivered: [])
  private var pendingRequests: [String: UNNotificationRequest] = [:]
  private var additions: [String: UNNotificationRequest] = [:]
  private var reservations: [String: UUID] = [:]
  private var generation: UInt64 = 0
  private let notificationTimeout: TimeInterval
  private lazy var deadline = NotificationDeadline(queue: queue, seconds: notificationTimeout)
  private var refreshing = false
  private var refreshAgain = false
  private var confirming = false
  private var cycleID = UUID().uuidString
  private var unresolvedBatchAdds: [String: String] = [:]
  private var completions: [(Result<[String: Any], Error>) -> Void] = []
  private var state = AgendaPrivateState()
  private var privateURL: URL?
  private var started = false
  private var loadError: String?
  private var lastError: String?
  private var lastCalendarRead: Date?
  private var snapshot = AgendaSnapshot.empty()
  private var scheduledRefresh: DispatchWorkItem?
  private var observers: [NSObjectProtocol] = []
  private let iso = ISO8601DateFormatter()
  private let storageRoot: URL?
  private let widgetRoot: URL?
  init(
    storageRoot: URL? = nil, widgetRoot: URL? = nil,
    notifications: any NotificationAdapter = SystemNotificationAdapter(),
    notificationTimeout: TimeInterval = 20
  ) {
    self.notifications = notifications
    self.notificationTimeout = notificationTimeout
    self.storageRoot = storageRoot
    self.widgetRoot = widgetRoot
    super.init()
  }

  func start(registerBackground: Bool = true) {
    guard !started else { return }
    started = true
    center.delegate = self
    let open = UNNotificationAction(
      identifier: "OPEN", title: "Termin öffnen", options: [.foreground])
    let snooze = UNNotificationAction(
      identifier: "SNOOZE", title: "In 5 Minuten erinnern", options: [])
    center.setNotificationCategories([
      UNNotificationCategory(
        identifier: Self.category, actions: [open, snooze], intentIdentifiers: [], options: []),
      UNNotificationCategory(
        identifier: Self.noSnoozeCategory, actions: [open], intentIdentifiers: [], options: []),
    ])
    if registerBackground {
      queue.async { self.loadPrivateState() }
    } else {
      loadPrivateState()
    }
    guard registerBackground else { return }
    // Called from the native entry point, before didFinishLaunching returns.
    BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.backgroundID, using: nil) {
      [weak self] task in
      guard let self else {
        task.setTaskCompleted(success: false)
        return
      }
      let completion = BackgroundCompletion(task)
      task.expirationHandler = { completion.finish(false) }
      self.queue.async {
        self.requestRefresh { result in
          completion.finish((try? result.get()) != nil && self.lastError == nil)
          self.scheduleBackground()
        }
      }
    }
    for name in [UIApplication.didBecomeActiveNotification, .EKEventStoreChanged] {
      observers.append(
        NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) {
          [weak self] _ in
          guard let self else { return }
          self.queue.async {
            self.scheduledRefresh?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.refreshSafely() }
            self.scheduledRefresh = work
            self.queue.asyncAfter(deadline: .now() + 1, execute: work)
          }
        })
    }
    observers.append(
      NotificationCenter.default.addObserver(
        forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
      ) { [weak self] _ in
        self?.scheduleBackground()
      })
  }

  private func loadPrivateState() {
    do {
      privateURL = try (storageRoot ?? AppStorage.prepare()).appendingPathComponent(
        "agenda-private-v1.json")
      if let privateURL, FileManager.default.fileExists(atPath: privateURL.path) {
        state = try JSONDecoder().decode(
          AgendaPrivateState.self, from: Data(contentsOf: privateURL))
        guard state.schemaVersion == 1 else {
          throw AgendaError.message("Erinnerungsdaten haben eine unbekannte Version.")
        }
      }
    } catch {
      loadError = "Erinnerungsdaten konnten nicht gelesen werden: \(error.localizedDescription)"
    }
  }

  private func scheduleBackground() {
    let request = BGAppRefreshTaskRequest(identifier: Self.backgroundID)
    request.earliestBeginDate = Date().addingTimeInterval(3600)
    // A rejected background request does not affect the calendar reserve.
    try? BGTaskScheduler.shared.submit(request)
  }
  private func persist() throws {
    if let loadError { throw AgendaError.message(loadError) }
    guard let privateURL else { throw AgendaError.message("Privater Erinnerungsspeicher fehlt.") }
    try JSONEncoder().encode(state).write(
      to: privateURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
  }
  private func pending() throws -> [UNNotificationRequest] { Array(pendingRequests.values) }
  private func authorized() throws -> Bool {
    ["authorized", "provisional"].contains(notificationState.authorization)
  }
  private func reserve(_ request: UNNotificationRequest) throws {
    if pendingRequests[request.identifier] == nil && additions[request.identifier] == nil {
      let ids = Set(pendingRequests.keys).union(additions.keys).union(reservations.keys)
      guard ids.count < 64,
        !request.identifier.hasPrefix("reha.event.")
          || ids.filter({ $0.hasPrefix("reha.event.") }).count < ReminderPolicy.limit
      else {
        throw AgendaError.message("Mitteilungsplätze belegt. Kalenderreserve bleibt zuständig.")
      }
    }
    additions[request.identifier] = request
  }
  private func install(_ snapshot: NotificationSnapshot) {
    notificationState = snapshot
    pendingRequests = Dictionary(uniqueKeysWithValues: snapshot.pending.map { ($0.identifier, $0) })
  }
  /// Coalesces callers. A state change during an async callback requests another
  /// pass; every waiter receives the final current state, never an older payload.
  func requestRefresh(_ completion: ((Result<[String: Any], Error>) -> Void)? = nil) {
    if let completion { completions.append(completion) }
    if refreshing {
      refreshAgain = true
      return
    }
    refreshing = true
    beginCycle()
  }
  private func beginCycle() {
    cycleID = UUID().uuidString
    let token = cycleID
    let version = generation
    LocalDiagnostics.shared.record(.reminderSelection, .started, correlation: token)
    refreshAgain = false
    additions = [:]
    deadline.run {
      await self.notifications.snapshot()
    } completion: { result in
      guard self.cycleID == token else { return }
      guard self.generation == version else {
        self.beginCycle()
        return
      }
      do {
        self.install(try result.get())
        self.lastError = nil
        self.confirming = false
        try self.refresh()
        let requests = Array(self.additions.values)
        let reservation = UUID()
        for request in requests {
          self.reservations[request.identifier] = reservation
          self.unresolvedBatchAdds[request.identifier] = token
        }
        LocalDiagnostics.shared.record(
          .reminderPlan, .started, correlation: token, count: requests.count)
        self.additions = [:]
        self.deadline.run(
          operation: {
            var failures = false
            for request in requests {
              guard await self.cycleIsCurrent(token, version: version) else { break }
              do { try await self.notifications.add(request) } catch { failures = true }
              await self.batchAddFinished(request.identifier, token: token, version: version)
            }
            for request in requests {
              await self.batchAddFinished(request.identifier, token: token, version: version)
            }
            return (await self.notifications.snapshot(), failures)
          },
          late: { _ in
            self.release(requests, reservation: reservation)
            self.requestRefresh()
          }
        ) { result in
          self.release(requests, reservation: reservation)
          guard self.cycleID == token else { return }
          guard self.generation == version else {
            self.beginCycle()
            return
          }
          do {
            let (confirmed, failed) = try result.get()
            self.install(confirmed)
            self.confirming = true
            try self.refresh()
            if failed {
              self.lastError =
                "Mitteilung konnte nicht geplant werden. Kalenderreserve bleibt erhalten."
            }
          } catch { self.lastError = error.localizedDescription }
          self.confirming = false
          if self.refreshAgain { self.beginCycle() } else { self.finishRefresh() }
        }
      } catch {
        self.lastError = error.localizedDescription
        self.finishRefresh()
      }
    }
  }
  private func batchAddFinished(_ id: String, token: String, version: UInt64) async {
    await withCheckedContinuation { continuation in
      queue.async {
        if self.unresolvedBatchAdds[id] == token {
          let current = self.refreshing && self.cycleID == token && self.generation == version
          // Retire the stale physical request before permitting a new cycle to
          // submit or adopt this logical identifier. Timeout alone never releases it.
          if !current {
            self.notifications.removePending([id])
            self.pendingRequests.removeValue(forKey: id)
          }
          self.unresolvedBatchAdds.removeValue(forKey: id)
          if !current { self.requestRefresh() }
        }
        continuation.resume()
      }
    }
  }
  private func cycleIsCurrent(_ token: String, version: UInt64) async -> Bool {
    await withCheckedContinuation { continuation in
      queue.async {
        continuation.resume(
          returning: self.refreshing && self.cycleID == token && self.generation == version)
      }
    }
  }
  private func release(_ requests: [UNNotificationRequest], reservation: UUID) {
    for request in requests where reservations[request.identifier] == reservation {
      reservations.removeValue(forKey: request.identifier)
    }
  }
  private func finishRefresh() {
    LocalDiagnostics.shared.record(
      .reminderConfirmed, lastError == nil ? .completed : .failed, correlation: cycleID,
      count: pendingRequests.keys.filter { $0.hasPrefix("reha.event.") }.count)
    refreshing = false
    let callbacks = completions
    completions = []
    let result = Result { try response() }
    for callback in callbacks { callback(result) }
  }
  func readStatus(_ completion: @escaping @Sendable (Result<[String: Any], Error>) -> Void) {
    let version = generation
    deadline.run {
      await self.notifications.snapshot()
    } completion: { result in
      do {
        let snapshot = try result.get()
        if self.generation == version { self.install(snapshot) }
        completion(Result { try self.response() })
      } catch { completion(.failure(error)) }
    }
  }
  private func requestID(_ id: String) -> String { "reha.event.\(id)" }
  private func oneOffIDs(_ prefix: String) -> [String] {
    Set(pendingRequests.keys).union(additions.keys).union(reservations.keys).union(
      notificationState.delivered
    )
    .filter { $0 == prefix || $0.hasPrefix(prefix + ".") }
  }
  private func retireOneOff(_ prefix: String) {
    let ids = oneOffIDs(prefix) + [prefix]
    for id in ids {
      pendingRequests.removeValue(forKey: id)
      additions.removeValue(forKey: id)
      reservations.removeValue(forKey: id)
    }
    notifications.removePending(ids)
    notifications.removeDelivered(ids)
  }
  private func cancel(_ id: String) {
    let request = requestID(id)
    pendingRequests.removeValue(forKey: request)
    additions.removeValue(forKey: request)
    notifications.removePending([request])
    notifications.removeDelivered([request])
    retireOneOff("reha.snooze.\(id)")
  }
  private func alarms(_ event: EKEvent) -> [CalendarAlarmDescriptor] {
    (event.alarms ?? []).map {
      CalendarAlarmDescriptor(
        relativeOffset: $0.relativeOffset,
        absolute: $0.absoluteDate != nil, location: $0.structuredLocation != nil)
    }
  }
  private func matches(_ event: EKEvent, minutes: Int?) -> Bool {
    AlarmOwnership.matches(alarms(event), minutes: minutes)
  }
  private func manageable(_ event: EKEvent, entry: AlarmJournalEntry) -> Bool {
    AlarmOwnership.manageable(
      alarms(event), recurring: event.hasRecurrenceRules || event.isDetached,
      writable: event.calendar.allowsContentModifications, entry: entry)
  }

  // Existing review comparisons use the logical app-managed alarm. This does not
  // change stored approved values. Unknown/manual alarms always stay visible.
  func logicalReminder(for event: EKEvent, actual: Int?) -> Int? {
    guard let id = event.url?.lastPathComponent, let entry = state.journal[id],
      manageable(event, entry: entry)
    else { return actual }
    return entry.approvedMinutes
  }
  /// Only a journaled, still-manageable app alarm is normalized for edit receipts.
  /// Foreign and externally changed alarms keep their complete physical snapshot.
  func comparisonAlarmEntry(for event: EKEvent) -> AlarmJournalEntry? {
    guard let id = event.url?.lastPathComponent,
      event.url?.absoluteString == "reha-calendar://event/\(id)",
      let entry = state.journal[id], manageable(event, entry: entry)
    else { return nil }
    return entry
  }
  func alarmIsProtected(_ event: EKEvent, approvedMinutes: Int?) -> Bool {
    guard let id = event.url?.lastPathComponent else { return true }
    let entry =
      state.journal[id]
      ?? AlarmJournalEntry(expectedMinutes: approvedMinutes, approvedMinutes: approvedMinutes)
    return !manageable(event, entry: entry)
  }
  func editingAlarmState(_ event: EKEvent) throws -> [String: Any]? {
    guard let id = event.url?.lastPathComponent,
      event.url?.absoluteString == "reha-calendar://event/\(id)",
      state.records.contains(where: { $0.id == id }), let entry = state.journal[id]
    else { return nil }
    return try JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as? [String: Any]
  }
  func manuallyEditedAlarm(_ event: EKEvent, restoring saved: [String: Any]? = nil) throws {
    guard let id = event.url?.lastPathComponent,
      event.url?.absoluteString == "reha-calendar://event/\(id)",
      state.records.contains(where: { $0.id == id })
    else { return }
    generation &+= 1
    cancel(id)
    if let saved {
      state.journal[id] = try JSONDecoder().decode(
        AlarmJournalEntry.self, from: JSONSerialization.data(withJSONObject: saved))
    } else {
      var entry = state.journal[id] ?? AlarmJournalEntry(expectedMinutes: nil, approvedMinutes: nil)
      entry.phase = "protected"
      state.journal[id] = entry
    }
    try persist()
  }
  // Called only after an explicitly approved EventKit write that changed alarms.
  func approvedAlarmChanged(id: String, minutes: Int?) throws {
    generation &+= 1
    cancel(id)
    state.journal[id] = AlarmJournalEntry(expectedMinutes: minutes, approvedMinutes: minutes)
    try persist()
  }

  enum Lookup {
    case found(EKEvent)
    case deleted, unavailable
  }
  func lookup(_ record: OwnedRecord) -> Lookup {
    guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return .unavailable }
    let marker = "reha-calendar://event/\(record.id)"
    if let external = record.external_id, let event = store.event(withIdentifier: external) {
      // A moved event remains visible, while its stored calendar binding is untouched.
      return event.url?.absoluteString == marker ? .found(event) : .unavailable
    }
    guard let calendar = store.calendar(withIdentifier: record.calendar_id),
      let date = iso.date(from: record.approved.start_utc)
    else { return .unavailable }
    let predicate = store.predicateForEvents(
      withStart: date.addingTimeInterval(-366 * 86400),
      end: date.addingTimeInterval(366 * 86400), calendars: [calendar])
    let found = store.events(matching: predicate).filter { $0.url?.absoluteString == marker }
    if found.count == 1, let event = found.first { return .found(event) }
    if found.count > 1 { return .unavailable }
    // A readable, still-existing calendar plus an absent identifier/marker is
    // required before declaring deletion. Revoked access never deletes records.
    return .deleted
  }
  private func model(_ event: EKEvent, id: String) -> AgendaEvent {
    AgendaEvent(
      id: id, start: event.startDate.timeIntervalSince1970,
      end: event.endDate.timeIntervalSince1970,
      timezone: event.timeZone?.identifier ?? TimeZone.current.identifier,
      title: event.title ?? "Termin", room: event.location ?? "")
  }
  func sync(
    _ args: AgendaSyncArgs, completion: @escaping @Sendable (Result<[String: Any], Error>) -> Void
  ) throws {
    if let loadError { throw AgendaError.message(loadError) }
    generation &+= 1
    // Rust supplies committed app-owned records. The native cache is needed for
    // foreground/OS background refresh while the web interface is not running.
    let records = args.records.filter { $0.status == "saved" && $0.external_id != nil }
    let incoming = Set(records.map(\.id))
    for record in state.records where !incoming.contains(record.id) {
      if case .found(let event) = lookup(record), let entry = state.journal[record.id],
        manageable(event, entry: entry)
      {
        try restore(event, record: record, minutes: entry.expectedMinutes)
      }
      cancel(record.id)
      state.journal.removeValue(forKey: record.id)
    }
    state.records = records
    state.preferences = args.preferences
    try persist()
    requestRefresh(completion)
  }
  func activate(
    _ preferences: ReminderPreferences,
    completion: @escaping @Sendable (Result<[String: Any], Error>) -> Void
  ) {
    center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
      self.queue.async {
        do {
          if let error { throw error }
          if granted {
            self.state.preferences = preferences
            self.state.preferences.enabled = true
            try self.persist()
          }
          self.requestRefresh(completion)
        } catch { completion(.failure(error)) }
      }
    }
  }
  private func refreshSafely() { requestRefresh() }
  private func refresh() throws {
    if let loadError { throw AgendaError.message(loadError) }
    let now = Date()
    guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
      // Keep private ownership evidence so alarms can be restored after access
      // returns. Stale app alerts would be unsafe when events cannot be read.
      for record in state.records { cancel(record.id) }
      snapshot = .empty(access: state.records.isEmpty ? "empty" : "unavailable")
      try publish()
      return
    }
    store.refreshSourcesIfNecessary()
    var events: [(OwnedRecord, EKEvent, AgendaEvent)] = []
    var deleted: [String] = []
    var unavailable = false
    for record in state.records {
      switch lookup(record) {
      case .found(let event):
        guard event.endDate > event.startDate else {
          unavailable = true
          cancel(record.id)
          continue
        }
        events.append((record, event, model(event, id: record.id)))
      case .deleted:
        deleted.append(record.id)
        cancel(record.id)
        state.journal.removeValue(forKey: record.id)
      case .unavailable:
        unavailable = true
        cancel(record.id)
      }
    }
    var effective = state.preferences
    effective.enabled = try effective.enabled && authorized()
    let eligible = events.filter { record, event, _ in
      let entry =
        state.journal[record.id]
        ?? AlarmJournalEntry(
          expectedMinutes: record.approved.reminder_minutes,
          approvedMinutes: record.approved.reminder_minutes)
      return manageable(event, entry: entry)
    }.map { $0.2 }
    let selected = ReminderPolicy.selected(eligible, now: now, preferences: effective)
    let requests = try pending()
    let pendingMap = Dictionary(uniqueKeysWithValues: requests.map { ($0.identifier, $0) })
    var errors: [String] = []
    // Free displaced requests before filling the next 60 slots, even when the
    // underlying SQL record order changes or appointments move in the calendar.
    events.sort { left, right in
      let a = selected.contains(left.0.id)
      let b = selected.contains(right.0.id)
      return a != b ? !a : left.2.start < right.2.start
    }
    for (record, event, value) in events {
      do {
        if value.endDate <= now {
          cancel(record.id)
          continue
        }
        var entry =
          state.journal[record.id]
          ?? AlarmJournalEntry(
            expectedMinutes: record.approved.reminder_minutes,
            approvedMinutes: record.approved.reminder_minutes)
        guard manageable(event, entry: entry) else {
          cancel(record.id)
          entry.phase = "protected"
          state.journal[record.id] = entry
          try persist()
          continue
        }
        state.journal[record.id] = entry
        if selected.contains(record.id), let minutes = effective.minutes {
          try schedule(
            value, event: event, record: record, minutes: minutes, pending: pendingMap, now: now)
        } else {
          // A notification already delivered for an unchanged future event must
          // not turn back into a second calendar alert at its old trigger time.
          if entry.phase == "app", let fire = entry.fireAt, fire <= now.timeIntervalSince1970,
            entry.signature == signature(value, minutes: effective.minutes), effective.enabled
          {
            continue
          }
          let reserve =
            state.preferences.enabled ? state.preferences.minutes : entry.expectedMinutes
          try restore(event, record: record, minutes: reserve)
        }
      } catch { errors.append(error.localizedDescription) }
    }
    // Retire orphaned request identifiers left by a crash or calendar deletion.
    let liveIDs = Set(events.map { $0.0.id })
    for request in requests {
      if let id = request.content.userInfo["importID"] as? String,
        !liveIDs.contains(id), request.identifier != "reha.test"
      {
        cancel(id)
      }
    }
    if effective.enabled { state.migrationVersion = 1 }
    try persist()
    snapshot = AgendaSnapshot(
      updatedAt: now.timeIntervalSince1970,
      access: unavailable ? "unavailable" : events.isEmpty ? "empty" : "available",
      events: events.map { $0.2 }
        .sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }, deletedIDs: deleted)
    try publish()
    if !errors.isEmpty {
      throw AgendaError.message(
        "\(errors.count) Erinnerungen brauchen einen erneuten Abgleich. \(errors[0])")
    }
  }
  private func signature(_ event: AgendaEvent, minutes: Int?) -> String {
    let text =
      "\(event.id)|\(event.start)|\(event.end)|\(event.timezone)|\(event.title)|\(event.room)|\(minutes ?? -1)|\(state.preferences.sound)|\(state.preferences.preview)"
    return SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
  }
  private func content(_ event: AgendaEvent, minutes: Int, signature: String)
    -> UNMutableNotificationContent
  {
    let content = UNMutableNotificationContent()
    content.title =
      state.preferences.preview
      ? "\(event.title) in \(minutes) Minuten" : "Termin in \(minutes) Minuten"
    content.body =
      state.preferences.preview
      ? "\(AgendaFormat.time(event)) · \(AgendaFormat.room(event))"
      : "Termindetails in der App ansehen."
    content.categoryIdentifier = minutes > 5 ? Self.category : Self.noSnoozeCategory
    content.threadIdentifier = "reha-appointments"
    if state.preferences.sound { content.sound = .default }
    content.userInfo = [
      "importID": event.id, "signature": signature, "start": event.start, "end": event.end,
      "timezone": event.timezone, "title": state.preferences.preview ? event.title : "Termin",
      "room": state.preferences.preview ? event.room : "", "preview": state.preferences.preview,
    ]
    return content
  }
  private func schedule(
    _ value: AgendaEvent, event: EKEvent, record: OwnedRecord, minutes: Int,
    pending: [String: UNNotificationRequest], now: Date
  ) throws {
    let id = requestID(record.id)
    let fire = value.startDate.addingTimeInterval(-Double(minutes * 60))
    let fingerprint = signature(value, minutes: minutes)
    var entry = state.journal[record.id]!
    guard unresolvedBatchAdds[id] == nil else {
      if entry.phase == "app" { try restore(event, record: record, minutes: entry.expectedMinutes) }
      throw AgendaError.message(
        "Ein älterer Mitteilungsauftrag wartet noch auf eine Systemantwort. Der Kalenderalarm bleibt erhalten."
      )
    }
    let isConfirmed = pending[id]?.content.userInfo["signature"] as? String == fingerprint
    if entry.phase == "app", entry.signature == fingerprint, isConfirmed { return }
    if entry.phase == "app", !isConfirmed, let oldFire = entry.fireAt,
      oldFire > now.timeIntervalSince1970
    {
      // Request was lost/revoked. Put the reserve back before retrying.
      try restore(event, record: record, minutes: entry.expectedMinutes)
      entry = state.journal[record.id]!
    }
    if !isConfirmed {
      guard !confirming else {
        try restore(event, record: record, minutes: minutes)
        throw AgendaError.message(
          "Mitteilung noch nicht vom System bestätigt. Kalenderreserve bleibt erhalten.")
      }
      entry.phase = "scheduling"
      entry.signature = fingerprint
      entry.fireAt = fire.timeIntervalSince1970
      state.journal[record.id] = entry
      try persist()
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = TimeZone(secondsFromGMT: 0)!
      var components = calendar.dateComponents(
        [.year, .month, .day, .hour, .minute, .second], from: fire)
      components.timeZone = calendar.timeZone
      try reserve(
        UNNotificationRequest(
          identifier: id, content: content(value, minutes: minutes, signature: fingerprint),
          trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
      return
    }
    let io = transferIO(
      event: event, record: record, value: value, fingerprint: fingerprint,
      fire: fire, minutes: minutes)
    _ = try ReminderTransfer.handoff(
      entry: entry, signature: fingerprint,
      fireAt: fire.timeIntervalSince1970, reserveMinutes: minutes, io: io)
    notifications.removeDelivered([id])
    retireOneOff("reha.snooze.\(record.id)")
  }
  private func transferIO(
    event: EKEvent, record: OwnedRecord, value: AgendaEvent,
    fingerprint: String, fire: Date, minutes: Int
  ) -> ReminderTransfer.IO {
    ReminderTransfer.IO(
      journal: { entry in
        self.state.journal[record.id] = entry
        try self.persist()
      },
      addNotification: {
        throw AgendaError.message("Mitteilung muss vor der Alarmübergabe bestätigt sein.")
      },
      notificationConfirmed: {
        try self.pending().contains {
          $0.identifier == self.requestID(record.id)
            && $0.content.userInfo["signature"] as? String == fingerprint
        }
      },
      removeCalendarAlarm: {
        guard let live = self.store.event(withIdentifier: event.eventIdentifier),
          live.url == event.url, self.model(live, id: record.id) == value,
          let entry = self.state.journal[record.id], self.manageable(live, entry: entry)
        else {
          self.cancel(record.id)
          throw AgendaError.message("Termin wurde während der Einplanung verändert.")
        }
        if !(live.alarms ?? []).isEmpty {
          live.alarms = nil
          try self.store.save(live, span: .thisEvent, commit: true)
        }
        guard let saved = self.store.event(withIdentifier: live.eventIdentifier),
          (saved.alarms ?? []).isEmpty
        else {
          throw AgendaError.message("Kalenderalarm konnte nicht sicher übergeben werden.")
        }
      },
      restoreCalendarAlarm: { minutes in
        guard let live = self.store.event(withIdentifier: event.eventIdentifier),
          live.url == event.url,
          let entry = self.state.journal[record.id], self.manageable(live, entry: entry)
        else {
          self.cancel(record.id)
          throw AgendaError.message("Geänderter Kalenderalarm bleibt geschützt.")
        }
        if !self.matches(live, minutes: minutes) {
          live.alarms = minutes.map { [EKAlarm(relativeOffset: -Double($0 * 60))] }
          try self.store.save(live, span: .thisEvent, commit: true)
        }
        guard let saved = self.store.event(withIdentifier: live.eventIdentifier),
          self.matches(saved, minutes: minutes)
        else {
          throw AgendaError.message("Kalenderreserve konnte nicht bestätigt werden.")
        }
      },
      cancelNotification: { self.cancel(record.id) })
  }
  private func restore(_ event: EKEvent, record: OwnedRecord, minutes: Int?) throws {
    let entry =
      state.journal[record.id]
      ?? AlarmJournalEntry(
        expectedMinutes: record.approved.reminder_minutes,
        approvedMinutes: record.approved.reminder_minutes)
    guard manageable(event, entry: entry) else {
      cancel(record.id)
      return
    }
    if entry.phase == "calendar", matches(event, minutes: minutes), entry.expectedMinutes == minutes
    {
      // No write on an unchanged refresh. Cancellation also resolves a crash
      // after the final calendar journal write but before request cancellation.
      cancel(record.id)
      return
    }
    let value = model(event, id: record.id)
    let io = transferIO(
      event: event, record: record, value: value, fingerprint: "",
      fire: Date(), minutes: minutes ?? 10)
    _ = try ReminderTransfer.restore(entry: entry, minutes: minutes, io: io)
  }
  private func publish() throws {
    guard
      let root = widgetRoot
        ?? FileManager.default.containerURL(
          forSecurityApplicationGroupIdentifier: AgendaSnapshot.group)
    else {
      throw AgendaError.message("Gemeinsamer Widget-Speicher ist nicht verfügbar.")
    }
    var url = root.appendingPathComponent(AgendaSnapshot.filename)
    let previous = AgendaSnapshot.read(from: root)
    let changed =
      previous.access != snapshot.access || previous.events != snapshot.events
      || previous.deletedIDs != snapshot.deletedIDs
      || snapshot.updatedAt - previous.updatedAt > 3600
    try JSONEncoder().encode(snapshot).write(
      to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    var resources = URLResourceValues()
    resources.isExcludedFromBackup = true
    try url.setResourceValues(resources)
    if changed { WidgetCenter.shared.reloadTimelines(ofKind: AgendaSnapshot.widgetKind) }
  }
  func response() throws -> [String: Any] {
    let permission = notificationState.authorization
    let payload = try JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot))
    return [
      "snapshot": payload,
      "presentation": try presentation(),
      "reminders": [
        "authorization": permission, "enabled": state.preferences.enabled,
        "planned": state.journal.values.filter { ["scheduling", "app"].contains($0.phase) }.count,
        "confirmed_pending": pendingRequests.keys.filter { $0.hasPrefix("reha.event.") }.count,
        "observed_delivered": notificationState.delivered.filter {
          $0.hasPrefix("reha.event.") || ($0 == "reha.test" || $0.hasPrefix("reha.test."))
        }.count,
        "delivery_observation":
          "Nur noch im Mitteilungszentrum vorhandene Zustellungen sind beobachtbar.",
        "scheduled": try pending().filter { $0.identifier.hasPrefix("reha.event.") }.count,
        "calendar": state.journal.values.filter { $0.phase == "calendar" }.count,
        "protected": state.journal.values.filter { $0.phase == "protected" }.count,
        "error": lastError as Any? ?? NSNull(), "migrationVersion": state.migrationVersion,
      ],
    ]
  }
  func calendarStatus() -> [String: Any] {
    let access = EKEventStore.authorizationStatus(for: .event)
    let allowed = access == .fullAccess
    let calendars =
      allowed
      ? store.calendars(for: .event).map {
        ["id": $0.calendarIdentifier, "title": $0.title, "writable": $0.allowsContentModifications]
          as [String: Any]
      } : []
    if allowed { lastCalendarRead = Date() }
    return [
      "access": allowed
        ? "fullAccess"
        : access == .denied ? "denied" : access == .restricted ? "restricted" : "notDetermined",
      "last_read_at": lastCalendarRead.map { iso.string(from: $0) } as Any? ?? NSNull(),
      "calendars": calendars,
    ]
  }
  func presentation() throws -> [String: Any] {
    try JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot.presentation(at: Date())))
      as! [String: Any]
  }
  func pendingOpen(acknowledge: String?) throws -> [String: Any] {
    if let acknowledge, state.pendingOpen == acknowledge {
      state.pendingOpen = nil
      try persist()
    }
    return ["id": state.pendingOpen as Any? ?? NSNull()]
  }
  func forget() throws {
    generation &+= 1
    guard state.records.isEmpty || EKEventStore.authorizationStatus(for: .event) == .fullAccess
    else {
      throw AgendaError.message(
        "Zum sicheren Löschen zuerst Kalenderzugriff erlauben, damit Kalendererinnerungen erhalten bleiben."
      )
    }
    for record in state.records {
      switch lookup(record) {
      case .found(let event):
        if let entry = state.journal[record.id], manageable(event, entry: entry) {
          try restore(
            event, record: record, minutes: state.preferences.minutes ?? entry.expectedMinutes)
        }
      case .unavailable:
        throw AgendaError.message(
          "Ein Kalender ist nicht zugänglich. Daten nach dem Abgleich löschen.")
      case .deleted: break
      }
      cancel(record.id)
    }
    retireOneOff("reha.test")
    state = AgendaPrivateState()
    try persist()
    snapshot = .empty()
    try publish()
  }
  /// A one-off notification uses the reserved slot and reports acceptance separately.
  func testNotification(_ completion: @escaping @Sendable (Result<[String: Any], Error>) -> Void) {
    scheduleOne(
      make: {
        let content = UNMutableNotificationContent()
        content.title = "Testerinnerung"
        content.body = "Der Testauftrag wurde vor fünf Sekunden angenommen."
        if self.state.preferences.sound { content.sound = .default }
        return UNNotificationRequest(
          identifier: "reha.test", content: content,
          trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false))
      }, completion: completion)
  }
  func snooze(id: String, completion: @escaping @Sendable (Result<[String: Any], Error>) -> Void) {
    scheduleOne(
      make: {
        guard let record = self.state.records.first(where: { $0.id == id }),
          case .found(let event) = self.lookup(record),
          ReminderPolicy.canSnooze(start: event.startDate, now: Date()),
          self.state.preferences.enabled,
          let entry = self.state.journal[id], entry.phase == "app",
          self.manageable(event, entry: entry)
        else {
          throw AgendaError.message("Dieser Termin kann nicht mehr geschlummert werden.")
        }
        guard
          Set(self.pendingRequests.keys).union(self.reservations.keys).filter({
            $0.hasPrefix("reha.snooze.")
              && !($0 == "reha.snooze.\(id)" || $0.hasPrefix("reha.snooze.\(id)."))
          }).count < 3
        else {
          throw AgendaError.message("Die drei Schlummerplätze sind belegt.")
        }
        let value = self.model(event, id: id)
        let content = self.content(
          value, minutes: max(1, Int(ceil(event.startDate.timeIntervalSinceNow / 60)) - 5),
          signature: self.signature(value, minutes: self.state.preferences.minutes))
        return UNNotificationRequest(
          identifier: "reha.snooze.\(id)", content: content,
          trigger: UNTimeIntervalNotificationTrigger(timeInterval: 300, repeats: false))
      }, completion: completion)
  }
  private func scheduleOne(
    make: @escaping @Sendable () throws -> UNNotificationRequest,
    completion: @escaping @Sendable (Result<[String: Any], Error>) -> Void
  ) {
    let version = generation
    let reservation = UUID()
    deadline.run {
      await self.notifications.snapshot()
    } completion: { result in
      do {
        guard self.generation == version else {
          throw AgendaError.message("Erinnerungseinstellungen wurden geändert. Auftrag verworfen.")
        }
        self.install(try result.get())
        guard try self.authorized() else {
          throw AgendaError.message(
            "Mitteilungen sind nicht erlaubt. In den iPhone-Einstellungen freigeben.")
        }
        let template = try make()
        guard
          !self.reservations.keys.contains(where: {
            $0 == template.identifier || $0.hasPrefix(template.identifier + ".")
          })
        else { throw AgendaError.message("Dieser Mitteilungsauftrag wird bereits bearbeitet.") }
        // Unique physical IDs prevent a timed-out callback from replacing or
        // removing a newer test/snooze request for the same logical slot.
        self.retireOneOff(template.identifier)
        let request = UNNotificationRequest(
          identifier: template.identifier + "." + reservation.uuidString,
          content: template.content, trigger: template.trigger)
        try self.reserve(request)
        self.additions.removeValue(forKey: request.identifier)
        self.reservations[request.identifier] = reservation
        self.deadline.run(
          operation: {
            try await self.notifications.add(request)
            let valid = await self.oneIsCurrent(
              request.identifier, reservation: reservation, version: version)
            if !valid || Task.isCancelled { self.notifications.removePending([request.identifier]) }
            return await self.notifications.snapshot()
          },
          late: { _ in
            self.notifications.removePending([request.identifier])
            self.requestRefresh()
          }
        ) { result in
          self.release([request], reservation: reservation)
          do {
            guard self.generation == version else {
              self.notifications.removePending([request.identifier])
              throw AgendaError.message(
                "Erinnerungseinstellungen wurden geändert. Auftrag verworfen.")
            }
            let system = try result.get()
            self.install(system)
            completion(
              .success([
                "accepted": true,
                "delay_seconds": (request.trigger as? UNTimeIntervalNotificationTrigger)?
                  .timeInterval ?? 0,
                "confirmed_pending": system.pending.contains {
                  $0.identifier == request.identifier
                },
                "observed_delivered": system.delivered.contains(request.identifier),
              ]))
          } catch {
            self.notifications.removePending([request.identifier])
            completion(.failure(error))
          }
        }
      } catch { completion(.failure(error)) }
    }
  }
  private func oneIsCurrent(_ id: String, reservation: UUID, version: UInt64) async -> Bool {
    await withCheckedContinuation { continuation in
      queue.async {
        continuation.resume(
          returning: self.generation == version && self.reservations[id] == reservation)
      }
    }
  }
  func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .list, .sound])
  }
  func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping @Sendable () -> Void
  ) {
    queue.async {
      guard let id = response.notification.request.content.userInfo["importID"] as? String else {
        completionHandler()
        return
      }
      if response.actionIdentifier == "SNOOZE" {
        self.snooze(id: id) { result in
          if case .failure(let error) = result { self.lastError = error.localizedDescription }
          completionHandler()
        }
        return
      }
      defer { completionHandler() }
      do {
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier
          || response.actionIdentifier == "OPEN"
        {
          self.state.pendingOpen = id
          try self.persist()
        }
      } catch { self.lastError = error.localizedDescription }
    }
  }
}
private final class BackgroundCompletion: @unchecked Sendable {
  private let lock = NSLock()
  private var task: BGTask?
  init(_ task: BGTask) { self.task = task }
  func finish(_ success: Bool) {
    lock.lock()
    defer { lock.unlock() }
    task?.setTaskCompleted(success: success)
    task = nil
  }
}
@_cdecl("reha_agenda_start")
public func rehaAgendaStart() { AgendaService.shared.start() }
