import SwiftUI
import RehaCore

struct SettingsView: View {
    let core: NativeApplication
    let changed: (String) -> Void
    var recognitionOnly = false
    @State private var preferences: Preferences?
    @State private var error: String?
    var body: some View {
        Group {
            if let preferences { SettingsForm(core: core, initial: preferences, changed: changed, recognitionOnly: recognitionOnly) }
            else if let error { ContentUnavailableView(error, systemImage: "exclamationmark.triangle") }
            else { ProgressView("Einstellungen laden …") }
        }.task { do { preferences = try await core.preferences() } catch { self.error = userMessage(error) } }
    }
}
private struct SettingsForm: View {
    let core: NativeApplication
    let initial: Preferences
    let changed: (String) -> Void
    let recognitionOnly: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var preferences: Preferences
    @State private var error: String?
    @State private var busy = false
    @State private var erase = false
    @State private var discard = false
    @State private var reminders = ""
    init(core: NativeApplication, initial: Preferences, changed: @escaping (String) -> Void, recognitionOnly: Bool) {
        self.core = core; self.initial = initial; self.changed = changed; self.recognitionOnly = recognitionOnly
        _preferences = State(initialValue: initial)
    }
    var body: some View {
        NavigationStack {
            List {
                if !recognitionOnly {
                Section("Darstellung") {
                    AppearanceControls()
                    Picker("Erscheinungsbild", selection: $preferences.appearance) {
                        Text("System").tag("system"); Text("Hell").tag("light"); Text("Dunkel").tag("dark")
                    }
                }
                Section("Kalender") {
                    Picker("Zeitzone für neue Pläne", selection: $preferences.timezone) {
                        ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Kalendererinnerung", selection: $preferences.reminder) {
                        Text("Aus").tag(nil as UInt32?)
                        ForEach([5, 10, 15, 30, 60], id: \.self) { Text("\($0) Minuten vorher").tag(UInt32($0) as UInt32?) }
                    }
                }
                Section("App-Erinnerungen") {
                    Toggle("App-Erinnerungen verwenden", isOn: Binding(get: { preferences.appRemindersEnabled }, set: { enabled in if enabled { Task { await enable() } } else { preferences.appRemindersEnabled = false } }))
                    Picker("Vorlauf", selection: $preferences.appReminderMinutes) {
                        Text("Aus").tag(nil as UInt32?)
                        ForEach([5, 10, 15, 30, 60], id: \.self) { Text("\($0) Minuten").tag(UInt32($0) as UInt32?) }
                    }
                    Toggle("Ton", isOn: $preferences.reminderSound)
                    Toggle("Termindetails in Vorschau", isOn: $preferences.reminderPreview)
                    if !reminders.isEmpty { Text(reminders).font(.subheadline).foregroundStyle(.secondary) }
                    Button("Testerinnerung senden") { Task { do { _ = try await NativeBridge.request("testReminder") } catch { self.error = userMessage(error) } } }
                }
                }
                if recognitionOnly {
                Section { Text("Die Erkennung läuft auf diesem iPhone. Ergänzungsvorgaben werden bei passenden Behandlungen vorgeschlagen.") }
                Section {
                    ForEach($preferences.completionDefaults, id: \.id) { $item in
                        VStack(alignment: .leading) {
                            TextField("Einrichtung", text: $item.clinic)
                            TextField("Behandlung", text: $item.treatment)
                            Picker("Angabe", selection: $item.field) {
                                Text("Dauer").tag("duration_minutes"); Text("Raum").tag("location")
                                Text("Therapeut:in").tag("therapist"); Text("Vorbereitung").tag("preparation")
                            }
                            TextField("Vorgabe", text: Binding(get: { fieldDescription(item.value) }, set: { item.value = item.field == "duration_minutes" ? .integer(value: Int64($0) ?? 0) : .text(value: $0) }))
                            Button("Vorgabe entfernen", role: .destructive) { preferences.completionDefaults.removeAll { $0.id == item.id } }
                        }
                    }
                    Button("Vorgabe hinzufügen", systemImage: "plus") {
                        preferences.completionDefaults.append(CompletionDefault(id: UUID().uuidString, clinic: "", treatment: "", field: "location", value: .text(value: "")))
                    }
                } header: { Text("Ergänzungsvorgaben") } footer: { Text("Vorgaben werden nur vorgeschlagen und müssen bei der Terminprüfung angenommen werden.") }
                }
                if !recognitionOnly {
                Section("Aufbewahrung") {
                    Picker("Aufbewahren", selection: $preferences.retentionDays) {
                        Text("Bis zum Löschen").tag(nil as UInt32?)
                        Text("30 Tage nach Aufnahme").tag(UInt32(30) as UInt32?)
                        Text("90 Tage nach Aufnahme").tag(UInt32(90) as UInt32?)
                    }
                    Text("Fotos und Prüfdaten bleiben erhalten, bis du sie löschst. Unfertige und fehlgeschlagene Aufnahmen werden nie automatisch entfernt.")
                    Button("Alle lokalen Daten löschen", role: .destructive) { erase = true }.disabled(busy)
                }
                }
                if let error { Text(error).foregroundStyle(.red) }
                if busy { ProgressView("Wird gespeichert …") }
            }
            .pageTitle(recognitionOnly ? "Erkennung" : "Einstellungen")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { if preferences != initial { discard = true } else { dismiss() } } }
                ToolbarItem(placement: .confirmationAction) { Button("Speichern") { Task { await save() } }.disabled(busy) }
            }
            .interactiveDismissDisabled(preferences != initial || busy)
            .confirmationDialog("Änderungen verwerfen?", isPresented: $discard, titleVisibility: .visible) { Button("Verwerfen", role: .destructive) { dismiss() } }
            .confirmationDialog("Alle Fotos, Prüfdaten, Einstellungen und lokale Kalenderzuordnungen löschen? Kalendertermine bleiben bestehen.", isPresented: $erase, titleVisibility: .visible) {
                Button("Alle lokalen Daten löschen", role: .destructive) {
                    Task {
                        busy = true; defer { busy = false }
                        do { try await core.eraseAll(); changed("system"); dismiss() } catch { self.error = userMessage(error) }
                    }
                }
            }
            .task { await reminderStatus() }
        }
    }
    private func save() async {
        busy = true; defer { busy = false }
        do { preferences = try await core.savePreferences(value: preferences); changed(preferences.appearance); dismiss() }
        catch { self.error = userMessage(error) }
    }
    private func reminderStatus() async {
        do {
            let value = try JSONDecoder().decode(AgendaResponse.self, from: await NativeBridge.request("reminderStatus"))
            reminders = value.reminders.authorization == "denied" ? "Mitteilungen sind in den iPhone-Einstellungen ausgeschaltet." : value.reminders.error ?? ""
        } catch { self.error = userMessage(error) }
    }
    private func enable() async {
        busy = true; defer { busy = false }
        do {
            let result = try JSONDecoder().decode(AgendaResponse.self, from: await NativeBridge.request("requestReminderPermission"))
            preferences.appRemindersEnabled = ["authorized", "provisional"].contains(result.reminders.authorization)
            await reminderStatus()
        } catch { self.error = userMessage(error) }
    }
}
