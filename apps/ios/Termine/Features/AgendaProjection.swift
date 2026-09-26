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

/// Calendar arithmetic, independent of wall-clock progress and view state.
struct AgendaWeek: Equatable, Hashable {
    let start: Date
    let end: Date
    let days: [Date]
    init(containing date: Date, calendar: Calendar = .current) {
        let day = calendar.startOfDay(for: date)
        let offset = (calendar.component(.weekday, from: day) + 5) % 7
        let start = calendar.date(byAdding: .day, value: -offset, to: day)!
        self.start = start
        end = calendar.date(byAdding: .day, value: 7, to: start)!
        days = (0..<7).map { calendar.date(byAdding: .day, value: $0, to: start)! }
    }
}

/// End-exclusive clipping means midnight events never appear on the wrong day.
/// Elapsed minutes keep durations and repeated/missing DST hours accurate.
struct DayAgenda {
    struct Segment: Identifiable {
        let event: CalendarEvent
        let start: Double
        let duration: Double
        var id: String { event.id }
    }
    let date: Date
    let end: Date
    let events: [CalendarEvent]
    let allDay: [CalendarEvent]
    let timed: [Segment]
    let isComplete: Bool
    let scrollMinute: Double
    var minutes: Double { end.timeIntervalSince(date) / 60 }

    init(events: [CalendarEvent], date: Date, now: Date, calendar: Calendar = .current) {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        self.date = start; self.end = end
        var seen = Set<String>()
        self.events = events.filter {
            $0.values.start < end && $0.values.end > start && $0.values.end > $0.values.start && seen.insert($0.id).inserted
        }.sorted { ($0.values.start, $0.values.end, $0.id) < ($1.values.start, $1.values.end, $1.id) }
        allDay = self.events.filter(\.isAllDay)
        timed = self.events.filter { !$0.isAllDay }.map {
            let clippedStart = max(start, $0.values.start)
            return Segment(event: $0, start: clippedStart.timeIntervalSince(start) / 60,
                           duration: min(end, $0.values.end).timeIntervalSince(clippedStart) / 60)
        }
        let isToday = calendar.isDate(start, inSameDayAs: now)
        isComplete = isToday && !self.events.isEmpty && self.events.allSatisfy { $0.values.end <= now }
        let target = isToday ? timed.first { $0.event.values.end > now } : timed.first
        let minute = target.map { isToday && $0.event.values.start <= now ? now.timeIntervalSince(start) / 60 : $0.start }
        scrollMinute = max(0, (minute ?? timed.first?.start ?? 8 * 60) - 30)
    }
}

/// The visible day is 06:00–18:00 in local civil time. Keep the full-day
/// projection intact for completion, all-day events and access to other times.
struct AgendaWindow {
    let start: Date
    let end: Date
    let timed: [DayAgenda.Segment]
    let outside: [CalendarEvent]
    let scrollMinute: Double
    var minutes: Double { end.timeIntervalSince(start) / 60 }

    init(agenda: DayAgenda, now: Date, calendar: Calendar = .current) {
        let start = calendar.date(bySettingHour: 6, minute: 0, second: 0, of: agenda.date)!
        let end = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: agenda.date)!
        self.start = start; self.end = end
        timed = agenda.timed.compactMap { segment in
            let event = segment.event
            let from = max(start, event.values.start), to = min(end, event.values.end)
            guard to > from else { return nil }
            return DayAgenda.Segment(event: event, start: from.timeIntervalSince(start) / 60,
                                     duration: to.timeIntervalSince(from) / 60)
        }
        outside = agenda.timed.map(\.event).filter { $0.values.end <= start || $0.values.start >= end }
        let today = calendar.isDate(agenda.date, inSameDayAs: now)
        let target = today ? timed.first { $0.event.values.end > now } : timed.first
        let minute = target.map { today && $0.event.values.start <= now ? now.timeIntervalSince(start) / 60 : $0.start }
        scrollMinute = min(end.timeIntervalSince(start) / 60, max(0, (minute ?? timed.first?.start ?? 120) - 30))
    }
}

struct TimelinePlacement: Identifiable {
    let segment: DayAgenda.Segment
    let column: Int
    var columns: Int
    let height: Double
    var id: String { segment.id }
}

enum AgendaLayout {
    /// Use visual hit areas for collision detection as well as real durations.
    /// Short adjacent events therefore remain separately tappable.
    static func place(_ segments: [DayAgenda.Segment], pointsPerHour: Double = 96, minimumHeight: Double = 44) -> [TimelinePlacement] {
        var result: [TimelinePlacement] = []
        var columnEnds: [Double] = []
        var groupStart = 0
        func finishGroup() {
            for index in groupStart..<result.count { result[index].columns = columnEnds.count }
        }
        for segment in segments.sorted(by: { ($0.start, $0.id) < ($1.start, $1.id) }) {
            if columnEnds.allSatisfy({ $0 <= segment.start }) {
                finishGroup(); groupStart = result.count; columnEnds = []
            }
            let height = max(minimumHeight, segment.duration * pointsPerHour / 60)
            let column = columnEnds.firstIndex { $0 <= segment.start } ?? columnEnds.count
            let visualEnd = segment.start + height / pointsPerHour * 60
            if column == columnEnds.count { columnEnds.append(visualEnd) } else { columnEnds[column] = visualEnd }
            result.append(TimelinePlacement(segment: segment, column: column, columns: 1, height: height))
        }
        finishGroup()
        return result
    }
}

/// A deliberate left swipe advances the selected civil day, including DST.
enum AgendaNavigation {
    static func swipedDate(_ date: Date, horizontal: Double, vertical: Double, calendar: Calendar = .current) -> Date? {
        guard abs(horizontal) >= 40, abs(horizontal) > abs(vertical) * 1.5 else { return nil }
        return calendar.date(byAdding: .day, value: horizontal < 0 ? 1 : -1, to: calendar.startOfDay(for: date))
    }
}

enum AgendaDensity: String, CaseIterable {
    case overview, standard, spacious
    var title: String { switch self { case .overview: "Übersicht"; case .standard: "Standard"; case .spacious: "Großzügig" } }
    var pointsPerHour: Double { switch self { case .overview: 44; case .standard: 72; case .spacious: 112 } }
}

/// Preserve chronological positions and genuine overlaps, stretching only the
/// intervals that need room for complete labels. Short appointments never hide
/// their location/therapist or collide with a following appointment's hit area.
struct ReadableAgendaLayout {
    struct Item: Identifiable {
        let placement: TimelinePlacement
        let top: Double
        let height: Double
        var id: String { placement.id }
    }
    let items: [Item]
    let knots: [Double]
    let positions: [Double]
    var height: Double { positions.last ?? 0 }
    func minute(at y: Double) -> Double {
        guard let upper = positions.firstIndex(where: { $0 >= y }) else { return knots.last ?? 720 }
        guard upper > 0 else { return 0 }
        let fraction = (y - positions[upper - 1]) / max(1, positions[upper] - positions[upper - 1])
        return knots[upper - 1] + fraction * (knots[upper] - knots[upper - 1])
    }
    func y(_ minute: Double) -> Double {
        guard let upper = knots.firstIndex(where: { $0 >= minute }) else { return height }
        guard upper > 0 else { return 0 }
        let fraction = (minute - knots[upper - 1]) / (knots[upper] - knots[upper - 1])
        return positions[upper - 1] + fraction * (positions[upper] - positions[upper - 1])
    }
    /// All pages share the projection; overlap columns remain specific to each day.
    init(segments: [DayAgenda.Segment], projection: ReadableAgendaLayout, pointsPerHour: Double) {
        knots = projection.knots; positions = projection.positions
        items = AgendaLayout.place(segments, pointsPerHour: pointsPerHour, minimumHeight: 0).map { item in
            let top = projection.y(item.segment.start)
            return Item(placement: item, top: top,
                        height: max(44, projection.y(item.segment.start + item.segment.duration) - top - 4))
        }
    }
    init(_ segments: [DayAgenda.Segment], minutes: Double = 720, pointsPerHour: Double, heights: [String: Double] = [:]) {
        let placements = AgendaLayout.place(segments, pointsPerHour: pointsPerHour, minimumHeight: 0)
        let knots = Set([0, minutes] + segments.flatMap { [$0.start, $0.start + $0.duration] }).sorted()
        var positions = knots.map { $0 / 60 * pointsPerHour }
        for item in placements.sorted(by: { $0.segment.start + $0.segment.duration < $1.segment.start + $1.segment.duration }) {
            let start = knots.firstIndex(of: item.segment.start)!
            let end = knots.firstIndex(of: item.segment.start + item.segment.duration)!
            let missing = max(0, max(100, heights[item.id] ?? 100) + 4 - (positions[end] - positions[start]))
            if missing > 0 { for index in end..<positions.count { positions[index] += missing } }
        }
        self.knots = knots; self.positions = positions
        self.items = placements.map { item in
            let start = knots.firstIndex(of: item.segment.start)!, end = knots.firstIndex(of: item.segment.start + item.segment.duration)!
            return Item(placement: item, top: positions[start], height: positions[end] - positions[start] - 4)
        }
    }
}

/// A tie belongs to vertical scrolling; a decision is never changed mid-gesture.
struct AgendaAxisLock {
    enum Axis { case horizontal, vertical }
    private(set) var axis: Axis?
    mutating func update(x: Double, y: Double) -> Axis? {
        if axis == nil, max(abs(x), abs(y)) >= 6 {
            axis = abs(x) > abs(y) ? .horizontal : .vertical
        }
        return axis
    }
    mutating func reset() { axis = nil }
}
