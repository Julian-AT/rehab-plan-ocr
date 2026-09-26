import Foundation

@main
struct AgendaPolicyChecks {
  enum Failure: Error { case injected }
  static var checks = 0
  static func check(_ value: @autoclosure () -> Bool, _ message: String) {
    precondition(value(), message)
    checks += 1
  }
  final class FakeChannels {
    var journal = AlarmJournalEntry(expectedMinutes: 10, approvedMinutes: 10)
    var alarm: Int? = 10
    var notification = false
    var fail: String?
    var failureHasRun = false
    var calls: [String] = []
    func boundary(_ name: String) throws {
      calls.append(name)
      if fail == name && !failureHasRun {
        failureHasRun = true
        throw Failure.injected
      }
    }
    var io: ReminderTransfer.IO {
      ReminderTransfer.IO(
        journal: { entry in
          try self.boundary("journal-\(entry.phase)")
          self.journal = entry
        },
        addNotification: {
          try self.boundary("add")
          self.notification = true
        },
        notificationConfirmed: {
          try self.boundary("confirm")
          return self.notification
        },
        removeCalendarAlarm: {
          try self.boundary("remove-alarm")
          self.alarm = nil
        },
        restoreCalendarAlarm: { minutes in
          try self.boundary("restore-alarm")
          self.alarm = minutes
        },
        cancelNotification: {
          self.calls.append("cancel")
          self.notification = false
        })
    }
    func handoff() throws {
      _ = try ReminderTransfer.handoff(
        entry: journal, signature: "event-v1", fireAt: 100,
        reserveMinutes: 10, io: io)
    }
  }
  static func main() throws {
    let now = ISO8601DateFormatter().date(from: "2026-03-28T23:30:00Z")!
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Vienna")!
    let start = calendar.startOfDay(for: now)
    let nextDay = calendar.date(byAdding: .day, value: 1, to: start)!
    check(nextDay.timeIntervalSince(start) == 23 * 3600, "Spring DST day")
    let autumn = ISO8601DateFormatter().date(from: "2026-10-25T00:00:00Z")!
    let autumnStart = calendar.startOfDay(for: autumn)
    check(
      calendar.date(byAdding: .day, value: 1, to: autumnStart)!.timeIntervalSince(autumnStart) == 25
        * 3600, "Autumn DST day")
    let event = AgendaEvent(
      id: "a", start: now.timeIntervalSince1970,
      end: now.addingTimeInterval(1800).timeIntervalSince1970,
      timezone: "Europe/Vienna", title: "Physiotherapie", room: "")
    let snapshot = AgendaSnapshot(
      updatedAt: now.timeIntervalSince1970, access: "available", events: [event])
    check(snapshot.upcoming(at: now).count == 1, "Ongoing is upcoming")
    check(event.isRunning(at: now), "Exact start is running")
    check(!event.isRunning(at: event.endDate), "Exact end is finished")
    check(snapshot.upcoming(at: event.endDate).isEmpty, "Finished event removed")
    check(
      snapshot.allToday(at: event.endDate, calendar: calendar).count == 1,
      "Native Today retains completed appointments")
    check(
      snapshot.allToday(at: nextDay, calendar: calendar).isEmpty,
      "Native Today respects the next DST day")
    check(
      snapshot.presentation(at: event.endDate, calendar: calendar).today.count == 1,
      "Both shells retain completed events today")
    check(
      snapshot.presentation(at: now.addingTimeInterval(-86400), calendar: calendar).next?.id
        == event.id, "Next appointment can belong to a later day")
    check(
      snapshot.boundaries(after: now, calendar: calendar).contains(nextDay),
      "Calendar midnight boundary")
    check(
      snapshot.boundaries(after: now, calendar: calendar).contains(event.endDate),
      "Event end boundary")
    check(snapshot.state(at: now.addingTimeInterval(86401)) == "stale", "Stale data state")
    check(
      AgendaSnapshot.empty(access: "unavailable").state(at: now) == "unavailable",
      "Unavailable distinct from empty")
    check(AgendaFormat.room(event) == "Raum nicht angegeben", "Missing room")
    var preferences = ReminderPreferences(enabled: true)
    var many: [AgendaEvent] = []
    for index in 0..<90 {
      let begins = now.timeIntervalSince1970 + Double(1200 + index * 1200)
      many.append(
        AgendaEvent(
          id: "event-\(index)", start: begins, end: begins + 600,
          timezone: "Europe/Vienna", title: "Therapie", room: "204"))
    }
    let selected = ReminderPolicy.selected(
      Array(many.reversed()), now: now, preferences: preferences)
    check(
      selected.count == 60 && selected.contains("event-0") && selected.contains("event-59")
        && !selected.contains("event-60"), "Nearest 60 only")
    preferences.enabled = false
    check(
      ReminderPolicy.selected(many, now: now, preferences: preferences).isEmpty,
      "No permission / disabled")
    preferences.enabled = true
    preferences.minutes = nil
    check(ReminderPolicy.selected(many, now: now, preferences: preferences).isEmpty, "Off")
    check(
      ReminderPolicy.canSnooze(start: now.addingTimeInterval(301), now: now), "Snooze before start")
    check(
      !ReminderPolicy.canSnooze(start: now.addingTimeInterval(300), now: now),
      "Snooze at start refused")
    let original = AlarmJournalEntry(expectedMinutes: 10, approvedMinutes: 10)
    let ours = [CalendarAlarmDescriptor(relativeOffset: -600)]
    check(
      AlarmOwnership.manageable(ours, recurring: false, writable: true, entry: original),
      "Owned single alarm")
    for alarms in [
      [], [CalendarAlarmDescriptor(relativeOffset: -300)], ours + ours,
      [CalendarAlarmDescriptor(relativeOffset: -600, absolute: true)],
      [CalendarAlarmDescriptor(relativeOffset: -600, location: true)],
      [CalendarAlarmDescriptor(relativeOffset: -600, proximity: true)],
    ] {
      check(
        !AlarmOwnership.manageable(alarms, recurring: false, writable: true, entry: original),
        "Manual alarm protected")
    }
    check(
      !AlarmOwnership.manageable(ours, recurring: true, writable: true, entry: original),
      "Recurrence protected")
    check(
      !AlarmOwnership.manageable(ours, recurring: false, writable: false, entry: original),
      "Read-only calendar protected")
    let good = FakeChannels()
    try good.handoff()
    check(
      good.notification && good.alarm == nil && good.journal.phase == "app", "Single app channel")
    check(
      good.calls.firstIndex(of: "confirm")! < good.calls.firstIndex(of: "remove-alarm")!,
      "Confirm before remove")
    for boundary in ["journal-scheduling", "add", "confirm", "remove-alarm", "journal-app"] {
      let fake = FakeChannels()
      fake.fail = boundary
      do {
        try fake.handoff()
        preconditionFailure("Expected injected failure")
      } catch {}
      check(fake.alarm == 10 && !fake.notification, "Failure has one calendar channel: \(boundary)")
      try fake.handoff()
      check(
        fake.notification && fake.alarm == nil, "Replay reaches single app channel: \(boundary)")
    }
    // Simulate abrupt termination (no catch/rollback) at each durable phase.
    for phase in ["scheduling", "app", "restoring", "calendar"] {
      for hasAlarm in [false, true] {
        let fake = FakeChannels()
        fake.journal.phase = phase
        fake.notification = true
        fake.alarm = hasAlarm ? 10 : nil
        try fake.handoff()
        check(
          fake.notification && fake.alarm == nil && fake.journal.phase == "app",
          "Crash replay: \(phase)")
      }
    }
    for boundary in ["journal-restoring", "restore-alarm", "journal-calendar"] {
      let fake = FakeChannels()
      try fake.handoff()
      fake.fail = boundary
      do { _ = try ReminderTransfer.restore(entry: fake.journal, minutes: 15, io: fake.io) } catch {
      }
      check(fake.notification, "Failed restoration retains notification: \(boundary)")
      _ = try ReminderTransfer.restore(entry: fake.journal, minutes: 15, io: fake.io)
      check(
        !fake.notification && fake.alarm == 15 && fake.journal.phase == "calendar",
        "Restore retry: \(boundary)")
    }
    let encoded =
      try JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as! [String: Any]
    check(
      Set(encoded.keys) == Set(["schemaVersion", "updatedAt", "access", "events", "deletedIDs"]),
      "Versioned payload")
    let encodedEvent = (encoded["events"] as! [[String: Any]])[0]
    check(
      Set(encodedEvent.keys) == Set(["id", "start", "end", "timezone", "title", "room", "status"]),
      "Payload excludes private data")
    print("\(checks) agenda, DST, ownership and crash-recovery checks passed")
  }
}
