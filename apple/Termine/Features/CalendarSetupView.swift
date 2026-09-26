import SwiftUI
import RehaCore
import EventKit

struct CalendarSetupView: View {
    let core: NativeApplication
    var planID: String? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var destinations: [CalendarDestinations.Destination] = []
    @State private var calendarID = ""
    @State private var remember = false
    @State private var busy = false
    @State private var error: String?
    @State private var recent: [String] = []
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(planID == nil ? "Neue Termine speichern in" : "Dieser Plan erhält genau einen Zielkalender.").font(.headline)
                    Button("Kalenderzugriff erlauben") { Task { await load(requestAccess: true) } }.disabled(busy)
                    Button("Laßnitzhöhe-Kalender verwenden") { Task { await dedicated() } }.disabled(busy)
                }
                Section("Kalender auswählen") {
                    ForEach(destinations.sorted { a, b in
                        let x = recent.firstIndex(of: a.id) ?? Int.max, y = recent.firstIndex(of: b.id) ?? Int.max
                        return x == y ? (a.title, a.source, a.id) < (b.title, b.source, b.id) : x < y
                    }) { calendar in
                        Button { calendarID = calendar.id } label: {
                            CalendarChoiceRow(calendar: calendar, selected: calendarID == calendar.id)
                        }.buttonStyle(.plain).disabled(!calendar.writable || busy)
                    }
                }
                if planID != nil { Toggle("Für neue Pläne merken", isOn: $remember) }
                Text("Ein neuer Standard verschiebt keine bestehenden Termine. Die Anzeigeauswahl wird getrennt eingestellt.").foregroundStyle(.secondary)
                if let error { Text(error).foregroundStyle(.red) }
                if EKEventStore.authorizationStatus(for: .event) == .denied {
                    Link("Zugriff in Einstellungen erlauben", destination: URL(string: UIApplication.openSettingsURLString)!)
                }
                if busy { ProcessingRow(text: "Kalender laden …") }
                Button { Task { await save() } } label: { Text("Diesen Kalender verwenden").frame(maxWidth: .infinity).controlHeight() }
                    .buttonStyle(PrimaryActionStyle()).disabled(busy || !destinations.contains { $0.id == calendarID && $0.writable })
            }.navigationTitle("Speicherziel")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() }.disabled(busy) } }
                .task { await load(requestAccess: false) }
        }
    }
    private func load(requestAccess: Bool) async {
        busy = true; defer { busy = false }
        do {
            let preferences = try await core.preferences(); recent = preferences.recentCalendarIds
            if let planID { calendarID = try await core.planCalendar(id: planID).calendarId } else { calendarID = preferences.calendarId }
            if requestAccess { _ = try await NativeBridge.request("calendars", ["dedicated": false]) }
            guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return }
            destinations = try JSONDecoder().decode(CalendarDestinations.self, from: await NativeBridge.request("eventCalendars")).calendars
            error = nil
        } catch { self.error = userMessage(error) }
    }
    private func dedicated() async {
        do {
            let response = try JSONDecoder().decode(CalendarDestinations.self, from: await NativeBridge.request("calendars", ["dedicated": true]))
            await load(requestAccess: false)
            if let id = response.dedicated_id { calendarID = id }
            if let message = response.setup_error { error = message }
        } catch { self.error = userMessage(error) }
    }
    private func save() async {
        busy = true; defer { busy = false }
        do {
            if let planID { try await core.selectPlanCalendar(id: planID, calendarId: calendarID) }
            var p = try await core.preferences()
            if planID == nil || remember { p.calendarId = calendarID }
            p.recentCalendarIds = [calendarID] + p.recentCalendarIds.filter { $0 != calendarID }.prefix(9)
            _ = try await core.savePreferences(value: p); dismiss()
        } catch { self.error = userMessage(error) }
    }
}
struct CalendarChoiceRow: View {
    let calendar: CalendarDestinations.Destination
    let selected: Bool
    var body: some View {
        HStack(spacing: 16) {
            if let color = calendar.color_components, color.count == 3 {
                Circle().fill(Color(red: color[0], green: color[1], blue: color[2])).frame(width: 16, height: 16).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(calendar.title).font(.headline)
                Text(calendar.source).foregroundStyle(.secondary)
                if !calendar.writable { Text("Nur anzeigen und vorlesen").foregroundStyle(.secondary) }
            }.fixedSize(horizontal: false, vertical: true)
            Spacer()
            if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint).accessibilityHidden(true) }
        }.controlHeight().accessibilityElement(children: .combine).accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
struct CalendarPreferencesView: View {
    let core: NativeApplication
    @State private var destinations: [CalendarDestinations.Destination] = []
    @State private var preferences: Preferences?
    @State private var setup = false
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        List {
            Section("Kalender anzeigen und vorlesen") {
                Text("Importierte Termine bleiben sichtbar. Weitere Kalender wählst du hier aus. Beschreibbare Termine können nach deiner Bestätigung auch geändert und gelöscht werden.")
                ForEach(destinations) { calendar in
                    Toggle(isOn: Binding(get: { preferences?.displayCalendarIds.contains(calendar.id) == true }, set: { value in Task { await select(calendar.id, value) } })) {
                        CalendarChoiceRow(calendar: calendar, selected: false)
                    }.disabled(busy)
                }
            }
            if let preferences {
                let missing = preferences.displayCalendarIds.filter { id in !destinations.contains { $0.id == id } }
                if !missing.isEmpty {
                    Section("Nicht verfügbare Kalender") {
                        ForEach(missing, id: \.self) { id in
                            Button("Kalender …\(id.suffix(6)) aus Anzeigeauswahl entfernen") { Task { await select(id, false) } }.controlHeight()
                        }
                    }
                }
            }
            Section("Neue Termine speichern in") {
                Text(destinations.first { $0.id == preferences?.calendarId } .map { "\($0.title) · \($0.source)" } ?? "Noch kein Kalender ausgewählt")
                Button("Speicherziel ändern") { setup = true }.controlHeight()
                if let id = preferences?.calendarId, !id.isEmpty, preferences?.displayCalendarIds.contains(id) == false {
                    Button("Auch anzeigen") { Task { await select(id, true) } }.controlHeight()
                }
            }
            if let error { Text(error).foregroundStyle(.red) }
            Button("Kalender neu laden") { Task { await load() } }.controlHeight()
        }.navigationTitle("Kalender")
            .task { await load() }
            .sheet(isPresented: $setup, onDismiss: { Task { await load() } }) { CalendarSetupView(core: core) }
    }
    private func load() async {
        do {
            preferences = try await core.preferences()
            _ = try await NativeBridge.request("calendars", ["dedicated": false])
            destinations = try JSONDecoder().decode(CalendarDestinations.self, from: await NativeBridge.request("eventCalendars")).calendars
            error = nil
        } catch { self.error = userMessage(error) }
    }
    private func select(_ id: String, _ visible: Bool) async {
        busy = true; defer { busy = false }
        do {
            var p = try await core.preferences(); p.displayCalendarIds.removeAll { $0 == id }
            if visible { p.displayCalendarIds.append(id) }
            preferences = try await core.savePreferences(value: p); error = nil
        } catch { self.error = userMessage(error) }
    }
}
