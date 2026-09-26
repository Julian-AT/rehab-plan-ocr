#if DEBUG && targetEnvironment(simulator)
import EventKit
import UIKit
import RehaCore

/// Only explicit UI-test launches on a simulator can create these synthetic
/// calendars. IDs are recorded so subsequent previews clean up only their data.
@MainActor enum PreviewFixtures {
    static func prepare(_ core: NativeApplication) async throws {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--agenda-fixture"), arguments.indices.contains(index + 1) else { return }
        let mode = arguments[index + 1]
        let store = EKEventStore()
        let original = try await core.preferences()
        if UserDefaults.standard.object(forKey: "preview.originalCalendar") == nil {
            UserDefaults.standard.set(original.calendarId, forKey: "preview.originalCalendar")
            UserDefaults.standard.set(original.displayCalendarIds, forKey: "preview.originalDisplay")
            UserDefaults.standard.set(original.appearance, forKey: "preview.originalAppearance")
            UserDefaults.standard.set(UserDefaults.standard.string(forKey: "agenda.density") ?? "overview", forKey: "preview.originalDensity")
            UserDefaults.standard.set(UserDefaults.standard.bool(forKey: "agenda.list"), forKey: "preview.originalList")
        }
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return }
        for id in UserDefaults.standard.stringArray(forKey: "preview.calendar.ids") ?? [] {
            if let calendar = store.calendar(withIdentifier: id) { try store.removeCalendar(calendar, commit: true) }
        }
        if mode == "cleanup" {
            var preferences = original
            preferences.calendarId = UserDefaults.standard.string(forKey: "preview.originalCalendar") ?? ""
            preferences.displayCalendarIds = UserDefaults.standard.stringArray(forKey: "preview.originalDisplay") ?? []
            preferences.appearance = UserDefaults.standard.string(forKey: "preview.originalAppearance") ?? "system"
            _ = try await core.savePreferences(value: preferences)
            UserDefaults.standard.set(UserDefaults.standard.string(forKey: "preview.originalDensity") ?? "overview", forKey: "agenda.density")
            UserDefaults.standard.set(UserDefaults.standard.bool(forKey: "preview.originalList"), forKey: "agenda.list")
            for key in ["preview.originalDensity", "preview.originalList", "preview.calendar.ids", "preview.originalCalendar", "preview.originalDisplay", "preview.originalAppearance"] { UserDefaults.standard.removeObject(forKey: key) }
            return
        }
        UserDefaults.standard.set("overview", forKey: "agenda.density")
        UserDefaults.standard.set(false, forKey: "agenda.list")
        guard let source = store.sources.first(where: { $0.sourceType == .local }) ?? store.defaultCalendarForNewEvents?.source else { return }
        var calendars: [EKCalendar] = []
        for index in 0..<2 {
            let calendar = EKCalendar(for: .event, eventStore: store)
            calendar.title = "Therapie"; calendar.source = source
            calendar.cgColor = (index == 0 ? UIColor.systemGreen : UIColor.systemOrange).cgColor
            try store.saveCalendar(calendar, commit: true); calendars.append(calendar)
        }
        UserDefaults.standard.set(calendars.map(\.calendarIdentifier), forKey: "preview.calendar.ids")
        var preferences = try await core.preferences()
        preferences.displayCalendarIds = mode == "no-selection" ? [] : calendars.map(\.calendarIdentifier)
        preferences.calendarId = calendars[0].calendarIdentifier
        preferences.appearance = arguments.contains("--preview-dark") ? "dark" : "light"
        _ = try await core.savePreferences(value: preferences)
        let now = Date(), day = Calendar.current.startOfDay(for: .now)
        func add(_ title: String, start: Date, end: Date, calendar: Int = 0, allDay: Bool = false, room: String = "Raum 2.14") throws {
            let event = EKEvent(eventStore: store)
            event.calendar = calendars[calendar]; event.title = title; event.location = room
            event.startDate = start; event.endDate = end; event.isAllDay = allDay
            event.notes = "Therapeut: Anna Beispiel\nKlinik: Laßnitzhöhe\nAbteilung: Therapiezentrum\nHinweise: Öffentliche synthetische Simulatorvorschau."
            try store.save(event, span: .thisEvent, commit: true)
        }
        if mode == "readable" {
            for offset in 0...8 {
                let date = Calendar.current.date(byAdding: .day, value: offset, to: day)!
                try add("Physiotherapie Tag \(offset)", start: date.addingTimeInterval(9 * 3600), end: date.addingTimeInterval(9.5 * 3600))
                try add("Kontrolle Tag \(offset)", start: date.addingTimeInterval(10 * 3600), end: date.addingTimeInterval(10 * 3600 + 60), room: "Raum 105, Erdgeschoss")
                try add("Training Tag \(offset)", start: date.addingTimeInterval(11 * 3600), end: date.addingTimeInterval(11.5 * 3600), room: "Turnsaal, 1. Stock")
                try add("Ergotherapie Tag \(offset)", start: date.addingTimeInterval(11 * 3600), end: date.addingTimeInterval(11.5 * 3600), calendar: 1, room: "Raum 202")
            }
        }
        if mode == "complete" || mode == "finishing" {
            try add("Erholung nach Physiotherapie", start: now.addingTimeInterval(-3600), end: now.addingTimeInterval(mode == "finishing" ? 5 : -1800))
        }
        if mode == "timeline" {
            try add("Physiotherapie", start: now.addingTimeInterval(-900), end: now.addingTimeInterval(1800))
            try add("Ergotherapie", start: now.addingTimeInterval(3600), end: now.addingTimeInterval(6300), calendar: 1, room: "Raum 105")
            try add("Entspannung", start: now.addingTimeInterval(9000), end: now.addingTimeInterval(11700), room: "Turnsaal")
        }
        if mode == "short" {
            try add("Kurztermin", start: now.addingTimeInterval(600), end: now.addingTimeInterval(660))
            try add("Kontrolle", start: now.addingTimeInterval(720), end: now.addingTimeInterval(780), calendar: 1)
        }
        if mode == "full" {
            try add("Frühgymnastik", start: day.addingTimeInterval(8 * 3600), end: day.addingTimeInterval(8.5 * 3600), room: "Turnsaal")
            try add("Physiotherapie", start: now.addingTimeInterval(-600), end: now.addingTimeInterval(1200))
            try add("Ärztliches Gespräch", start: now.addingTimeInterval(-300), end: now.addingTimeInterval(1500), calendar: 1, room: "Raum 105")
            try add("Übernacht-Beobachtung", start: day.addingTimeInterval(-3600), end: now.addingTimeInterval(900), room: "Station 1")
            try add("Aufenthalt Laßnitzhöhe", start: day, end: Calendar.current.date(byAdding: .day, value: 1, to: day)!, allDay: true, room: "")
        }
        if mode == "full" || mode == "one" {
            try add("Ergotherapie", start: now.addingTimeInterval(1800), end: now.addingTimeInterval(3600), room: "Raum 105")
        }
        if mode == "full" || mode == "future" {
            for offset in 1...5 {
                let date = Calendar.current.date(byAdding: .day, value: offset, to: day)!
                try add("Training Tag \(offset)", start: date.addingTimeInterval(9 * 3600), end: date.addingTimeInterval(9.5 * 3600), calendar: offset % 2, room: "Turnsaal")
            }
        }
    }
}
#endif
