import RehaCore
import SwiftUI

typealias PreferencesStore = OrderedSettings<Preferences>

extension OrderedSettings where Value == Preferences {
  convenience init(core: NativeApplication) {
    #if DEBUG && targetEnvironment(simulator)
      var failNext = ProcessInfo.processInfo.arguments.contains("--preview-settings-failure")
      self.init(
        read: { try await core.preferences() },
        write: {
          if failNext {
            failNext = false
            print("Preview: rejecting first changed preferences write")
            throw LocalSpeechError.message("Test: Einstellungen konnten nicht gespeichert werden.")
          }
          return try await core.savePreferences(value: $0)
        }, describe: userMessage)
    #else
      self.init(
        read: { try await core.preferences() },
        write: { try await core.savePreferences(value: $0) }, describe: userMessage)
    #endif
  }
  func binding<T>(_ key: WritableKeyPath<Preferences, T>, fallback: T) -> Binding<T> {
    Binding(
      get: { self.value?[keyPath: key] ?? fallback },
      set: { new in self.change { $0[keyPath: key] = new } })
  }
}

struct SettingsSaveStatus: View {
  @Environment(PreferencesStore.self) private var store
  var body: some View {
    if let error = store.error {
      Section {
        Text(error).foregroundStyle(AppPalette.destructive)
        Text("Angezeigt wird der zuletzt gespeicherte Stand.").foregroundStyle(
          AppPalette.secondaryText)
        Button("Erneut versuchen") {
          if store.canRetry { store.retry() } else { Task { await store.load() } }
        }
        .accessibilityIdentifier("retry-settings")
      }
    }
  }
}

struct SettingsView: View {
  @SwiftUI.AppStorage("agenda.density") private var density = AgendaDensity.standard.rawValue
  @SwiftUI.AppStorage("agenda.list") private var listView = false
  enum Page { case appearance, reminders, recognition, storage }
  let core: NativeApplication
  var page: Page = .appearance
  @Environment(PreferencesStore.self) private var store
  @Environment(ScanModel.self) private var scanner
  @State private var reminderStatus = ""
  @State private var testingReminder = false
  @State private var testResult: String?
  @State private var testError: String?
  @State private var error: String?
  @State private var erase = false
  @State private var erasing = false
  @State private var requestingPermission = false
  @State private var editingDefault: CompletionDefault?
  @State private var addingDefault = false
  @State private var removingDefault: CompletionDefault?
  init(core: NativeApplication, page: Page = .appearance) {
    self.core = core
    self.page = page
  }
  private var title: String {
    switch page {
    case .appearance: "Darstellung"
    case .reminders: "Erinnerungen"
    case .recognition: "Erkennung"
    case .storage: "Aufbewahrung"
    }
  }
  var body: some View {
    Form {
      if let preferences = store.value {
        switch page {
        case .appearance:
          Section {
            Picker("Erscheinungsbild", selection: store.binding(\.appearance, fallback: "system")) {
              Text("System").tag("system")
              Text("Hell").tag("light")
              Text("Dunkel").tag("dark")
            }.accessibilityIdentifier("appearance-picker")
          } footer: {
            Text("Schriftgröße und Bedienungshilfen folgen den iPhone-Einstellungen.")
              .foregroundStyle(AppPalette.secondaryText)
          }
          Section {
            Picker("Kalendergröße", selection: $density) {
              ForEach(AgendaDensity.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
            }.accessibilityIdentifier("agenda-density")
            Toggle("Tagesliste", isOn: $listView).accessibilityIdentifier("agenda-list-setting")
          } header: {
            Text("Kalender")
          } footer: {
            Text(
              "Standard zeigt etwa fünf bis sechs Stunden. Übersicht zeigt mehr vom Tag, Großzügig mehr Details. Jede Stunde bleibt gleich hoch. Antippen öffnet alle Terminangaben. Bei vielen Überschneidungen oder großer Bedienungshilfenschrift erscheint die Tagesliste."
            ).foregroundStyle(AppPalette.secondaryText)
          }
          Section("Terminfarben") {
            ForEach(EventCategory.allCases, id: \.rawValue) { category in
              Label {
                Text(category.title)
              } icon: {
                Circle().fill(category.color).frame(width: 12, height: 12)
              }
            }
          }
        case .reminders:
          Section {
            Picker("Kalendererinnerung", selection: store.binding(\.reminder, fallback: nil)) {
              minuteOptions
            }
          } footer: {
            Text("Gilt für neue Termine. Bestehende Kalendererinnerungen bleiben erhalten.")
              .foregroundStyle(AppPalette.secondaryText)
          }
          Section {
            Toggle(
              "App-Erinnerungen",
              isOn: Binding(
                get: { store.value?.appRemindersEnabled ?? false },
                set: { enabled in
                  if enabled {
                    Task { await enableReminders() }
                  } else {
                    store.change { $0.appRemindersEnabled = false }
                  }
                })
            ).disabled(requestingPermission).accessibilityIdentifier("app-reminders")
            Picker("Vorlauf", selection: store.binding(\.appReminderMinutes, fallback: nil)) {
              minuteOptions
            }
            Toggle("Ton", isOn: store.binding(\.reminderSound, fallback: false))
              .accessibilityIdentifier("reminder-sound")
            Toggle(
              "Termindetails in Vorschau", isOn: store.binding(\.reminderPreview, fallback: false)
            ).accessibilityIdentifier("reminder-preview")
            Button {
              guard !testingReminder else { return }
              testingReminder = true
              testResult = nil
              testError = nil
              Task {
                defer { testingReminder = false }
                do {
                  let result =
                    try JSONSerialization.jsonObject(
                      with: await NativeBridge.request("testReminder")) as? [String: Any]
                  testResult =
                    result?["confirmed_pending"] as? Bool == true
                    ? "Testauftrag angenommen und vom System vorgemerkt. Anzeige nach fünf Sekunden angefordert."
                    : "Testauftrag angenommen. Die Zustellung wurde noch nicht beobachtet."
                } catch { testError = userMessage(error) }
              }
            } label: {
              HStack {
                if testingReminder { ProgressView() }
                Text(testingReminder ? "Test wird geplant …" : "Testerinnerung senden")
              }
              .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(.rect)
            }.disabled(testingReminder).accessibilityIdentifier("test-reminder")
            if let testResult {
              Text(testResult).font(.subheadline).foregroundStyle(AppPalette.secondaryText)
            }
            if let testError {
              Text(testError).font(.subheadline).foregroundStyle(AppPalette.destructive)
            }
          } footer: {
            Text(
              reminderStatus.isEmpty
                ? "Die App erinnert an importierte und innerhalb der App erstellte Termine. Bestätigte Planung und beobachtete Zustellung werden getrennt erfasst."
                : reminderStatus
            ).foregroundStyle(AppPalette.secondaryText)
          }
        case .recognition:
          Section {
            Picker(
              "Zeitzone",
              selection: store.binding(\.timezone, fallback: TimeZone.current.identifier)
            ) {
              ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { Text($0).tag($0) }
            }
          } footer: {
            Text("Fotos werden auf diesem iPhone erkannt. Die Zeitzone gilt für neue Pläne.")
              .foregroundStyle(AppPalette.secondaryText)
          }
          Section {
            ForEach(preferences.completionDefaults, id: \.id) { item in
              Button {
                editingDefault = item
              } label: {
                LabeledContent(item.treatment, value: fieldDescription(item.value))
              }.swipeActions { Button("Löschen", role: .destructive) { removingDefault = item } }
            }
            Button("Vorgabe hinzufügen", systemImage: "plus") { addingDefault = true }.disabled(
              preferences.completionDefaults.count >= 100)
          } header: {
            Text("Ergänzungsvorgaben")
          } footer: {
            Text("Vorgaben werden vorgeschlagen und erst bei der Terminprüfung angenommen.")
              .foregroundStyle(AppPalette.secondaryText)
          }
        case .storage:
          Section {
            Picker("Aufbewahren", selection: store.binding(\.retentionDays, fallback: nil)) {
              Text("Bis zum Löschen").tag(nil as UInt32?)
              Text("30 Tage").tag(UInt32(30) as UInt32?)
              Text("90 Tage").tag(UInt32(90) as UInt32?)
            }
          } footer: {
            Text("Unfertige und fehlgeschlagene Aufnahmen werden nie automatisch entfernt.")
              .foregroundStyle(AppPalette.secondaryText)
          }
          Section {
            Button("Alle lokalen Daten löschen", role: .destructive) { erase = true }
              .foregroundStyle(AppPalette.destructive).disabled(
                erasing)
          }
        }
      } else if store.error == nil {
        ProgressView("Einstellungen laden …")
      }
      SettingsSaveStatus()
    }
    .pickerStyle(.navigationLink)
    .pageTitle(title)
    .task {
      await store.load()
      if page == .reminders { await loadReminderStatus() }
    }
    .sheet(isPresented: $addingDefault) { NavigationStack { CompletionDefaultForm() } }
    .sheet(item: $editingDefault) { item in
      NavigationStack { CompletionDefaultForm(original: item) }
    }
    .confirmationDialog(
      "Vorgabe löschen?",
      isPresented: Binding(
        get: { removingDefault != nil }, set: { if !$0 { removingDefault = nil } }),
      titleVisibility: .visible
    ) {
      Button("Vorgabe löschen", role: .destructive) {
        if let id = removingDefault?.id {
          store.change { $0.completionDefaults.removeAll { $0.id == id } }
        }
        removingDefault = nil
      }.foregroundStyle(AppPalette.destructive)
    }
    .confirmationDialog(
      "Alle Fotos, Prüfdaten, Einstellungen und lokale Kalenderzuordnungen löschen? Kalendertermine bleiben bestehen.",
      isPresented: $erase, titleVisibility: .visible
    ) {
      Button("Alle lokalen Daten löschen", role: .destructive) {
        Task {
          erasing = true
          defer { erasing = false }
          do { try await scanner.eraseLocalData(store) } catch { self.error = userMessage(error) }
        }
      }.foregroundStyle(AppPalette.destructive)
    }
    .alert(
      "Einstellungen", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })
    ) {
      Button("OK", role: .cancel) { error = nil }
    } message: {
      Text(error ?? "")
    }
  }
  @ViewBuilder private var minuteOptions: some View {
    Text("Aus").tag(nil as UInt32?)
    ForEach([5, 10, 15, 30, 60], id: \.self) {
      Text("\($0) Minuten vorher").tag(UInt32($0) as UInt32?)
    }
  }
  private func loadReminderStatus() async {
    do {
      let response = try JSONDecoder().decode(
        AgendaResponse.self, from: await NativeBridge.request("reminderStatus"))
      reminderStatus =
        response.reminders.authorization == "denied"
        ? "Mitteilungen sind in den iPhone-Einstellungen ausgeschaltet."
        : response.reminders.error ?? ""
    } catch { self.error = userMessage(error) }
  }
  private func enableReminders() async {
    requestingPermission = true
    defer { requestingPermission = false }
    do {
      let response = try JSONDecoder().decode(
        AgendaResponse.self, from: await NativeBridge.request("requestReminderPermission"))
      let allowed = ["authorized", "provisional"].contains(response.reminders.authorization)
      store.change { $0.appRemindersEnabled = allowed }
      await loadReminderStatus()
    } catch { self.error = userMessage(error) }
  }
}

// Generated app-owned records already provide a stable ID for SwiftUI sheets.
// swift-format-ignore: AvoidRetroactiveConformances
extension CompletionDefault: @retroactive Identifiable {}

private struct CompletionDefaultForm: View {
  var original: CompletionDefault?
  @Environment(PreferencesStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @State private var clinic = ""
  @State private var treatment = ""
  @State private var field = "location"
  @State private var value = ""
  private var valid: Bool {
    !clinic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !treatment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && (field == "duration_minutes"
        ? (Int64(value).map { (1...1440).contains($0) } ?? false)
        : !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          && value.utf8.count <= 2000)
  }
  var body: some View {
    Form {
      Section {
        TextField("Einrichtung", text: $clinic)
        TextField("Behandlung", text: $treatment)
        Picker("Angabe", selection: $field) {
          Text("Dauer").tag("duration_minutes")
          Text("Raum").tag("location")
          Text("Therapeut:in").tag("therapist")
          Text("Vorbereitung").tag("preparation")
        }
        TextField(field == "duration_minutes" ? "Minuten" : "Vorgabe", text: $value)
          .keyboardType(field == "duration_minutes" ? .numberPad : .default)
      } footer: {
        Text("Alle Angaben sind erforderlich. Eine Dauer muss zwischen 1 und 1440 Minuten liegen.")
          .foregroundStyle(AppPalette.secondaryText)
      }
    }.pageTitle(original == nil ? "Neue Vorgabe" : "Vorgabe")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Übernehmen") {
            let item = CompletionDefault(
              id: original?.id ?? UUID().uuidString,
              clinic: clinic.trimmingCharacters(in: .whitespacesAndNewlines),
              treatment: treatment.trimmingCharacters(in: .whitespacesAndNewlines), field: field,
              value: field == "duration_minutes"
                ? .integer(value: Int64(value)!)
                : .text(value: value.trimmingCharacters(in: .whitespacesAndNewlines)))
            store.change { preferences in
              if let index = preferences.completionDefaults.firstIndex(where: { $0.id == item.id })
              {
                preferences.completionDefaults[index] = item
              } else {
                preferences.completionDefaults.append(item)
              }
            }
            dismiss()
          }.disabled(!valid)
        }
      }
      .onAppear {
        if let original {
          clinic = original.clinic
          treatment = original.treatment
          field = original.field
          value = fieldDescription(original.value)
        }
      }
  }
}
