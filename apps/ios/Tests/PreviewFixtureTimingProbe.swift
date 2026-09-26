import Foundation

@main struct PreviewFixtureTimingProbe {
  static func main() {
    for zone in ["UTC", "Europe/Vienna", "America/New_York"] {
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = TimeZone(identifier: zone)!
      for date in ["2026-03-29T12:00:00Z", "2026-09-18T12:00:00Z", "2026-10-25T12:00:00Z"] {
        let day = calendar.startOfDay(for: ISO8601DateFormatter().date(from: date)!)
        for offset in [0.0, 0.5, 600, 1799, 1800, 3600, 72000] {
          let now = day.addingTimeInterval(offset)
          let interval = PreviewFixtureTiming.completed(now: now, calendar: calendar)
          precondition(interval.duration > 0)
          precondition(interval.start >= day)
          precondition(calendar.isDate(interval.end, inSameDayAs: now))
          precondition(interval.end <= max(now, day.addingTimeInterval(1)))
          let iso = ISO8601DateFormatter()
          let start = iso.date(from: iso.string(from: interval.start))!
          let end = iso.date(from: iso.string(from: interval.end))!
          precondition(end > start && end > day)
        }
      }
    }
    print("Completed fixture remains on its selected civil day: 63 boundary cases passed")
  }
}
