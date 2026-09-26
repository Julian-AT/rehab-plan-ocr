import Foundation

/// Each occurrence has exactly one section. Events already spanning midnight
/// belong to today; future occurrences belong to their start day. End is exclusive.
struct AgendaProjection {
    struct Day: Identifiable {
        let date: Date
        let events: [CalendarEvent]
        var id: Date { date }
    }
    let today: [CalendarEvent]
    let remaining: [CalendarEvent]
    let past: [CalendarEvent]
    let future: [Day]
    let nextID: String?

    init(events: [CalendarEvent], now: Date, calendar: Calendar = .current) {
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        var seen = Set<String>()
        let sorted = events.filter { $0.values.end > start && $0.values.end > $0.values.start && seen.insert($0.id).inserted }
            .sorted { ($0.values.start, $0.values.end, $0.id) < ($1.values.start, $1.values.end, $1.id) }
        today = sorted.filter { $0.values.start < end }
        remaining = today.filter { $0.values.end > now }
        past = today.filter { $0.values.end <= now }
        nextID = remaining.first { !$0.isAllDay && $0.values.start > now }?.id
        let groups = Dictionary(grouping: sorted.filter { $0.values.start >= end }) { calendar.startOfDay(for: $0.values.start) }
        future = groups.keys.sorted().map { Day(date: $0, events: groups[$0]!) }
    }
    func marker(for event: CalendarEvent, now: Date) -> String? {
        guard !event.isAllDay else { return nil }
        if event.values.start <= now && event.values.end > now { return "Jetzt" }
        return event.id == nextID ? "Als Nächstes" : nil
    }
}
