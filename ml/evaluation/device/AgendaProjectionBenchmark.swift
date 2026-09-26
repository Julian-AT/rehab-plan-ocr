// Desktop projection microbenchmark using invented calendar events.
// Compile together with CalendarEvent.swift and AgendaProjection.swift.
// This excludes EventKit, rendering and speech; it cannot qualify device latency.
import Foundation

@main struct AgendaProjectionBenchmark {
  static func main() throws {
    let iterations = Int(CommandLine.arguments.dropFirst().first ?? "3") ?? 3
    precondition(iterations > 0)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Vienna")!
    let iso = ISO8601DateFormatter()
    let now = iso.date(from: "2030-09-17T08:00:00Z")!
    let constructionStart = DispatchTime.now().uptimeNanoseconds
    let events = (0..<84).map { index in
      let start = now.addingTimeInterval(Double(index / 12) * 86400 + Double(index % 12) * 1800)
      return CalendarEvent(
        id: "synthetic-\(index)", external_id: "synthetic-\(index)", calendar_id: "synthetic",
        calendar_title: "Prüfung", source: "synthetic", occurrence: iso.string(from: start),
        recurring: false, system_only: false, writable: true,
        values: CalendarEventValues(
          title: "Prüftermin", start_utc: iso.string(from: start),
          end_utc: iso.string(from: start.addingTimeInterval(1800)), timezone: "Europe/Vienna",
          location: "Raum 2", reminder_minutes: nil),
        metadata: .object([:]), fingerprint: "synthetic-\(index)")
    }
    let constructionMilliseconds =
      Double(DispatchTime.now().uptimeNanoseconds - constructionStart) / 1_000_000
    var count = 0
    let beginning = DispatchTime.now().uptimeNanoseconds
    for _ in 0..<iterations {
      let projection = AgendaProjection(events: events.reversed(), now: now, calendar: calendar)
      count += projection.today.count + projection.future.flatMap(\.events).count
      let day = DayAgenda(events: events, date: now, now: now, calendar: calendar)
      count += AgendaWindow(agenda: day, now: now, calendar: calendar).timed.count
    }
    let milliseconds = Double(DispatchTime.now().uptimeNanoseconds - beginning) / 1_000_000
    let result: [String: Any] = [
      "kind": "desktop-projection-microbenchmark", "synthetic_events": events.count,
      "iterations": iterations, "milliseconds": milliseconds, "checksum": count,
      "construction_milliseconds": constructionMilliseconds,
      "construction_and_projection_milliseconds": constructionMilliseconds + milliseconds,
      "device_latency_qualification": false,
    ]
    print(
      String(
        decoding: try JSONSerialization.data(withJSONObject: result, options: .sortedKeys),
        as: UTF8.self))
  }
}
