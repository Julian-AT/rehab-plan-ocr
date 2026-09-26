import Foundation

enum PreviewFixtureTiming {
  static func completed(now: Date, calendar: Calendar) -> DateInterval {
    let day = calendar.startOfDay(for: now)
    // At midnight a positive-duration event on the new day cannot already be
    // over. Its first second finishes before the fixture UI becomes usable and
    // survives the calendar bridge's whole-second timestamp serialization.
    let end = max(day.addingTimeInterval(1), now.addingTimeInterval(-1800))
    return DateInterval(start: max(day, end.addingTimeInterval(-1800)), end: end)
  }
}
