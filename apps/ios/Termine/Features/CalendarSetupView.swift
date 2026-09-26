import EventKit
import RehaCore
import SwiftUI

struct CalendarSetupView: View {
  let core: NativeApplication
  var planID: String? = nil
  var embedded = false
  @Environment(PreferencesStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @Environment(\.openURL) private var openURL
  @Environment(\.scenePhase) private var scenePhase
  @State private var destinations: [CalendarDestinations.Destination] = []
  @State private var calendarID = ""
  @State private var remember = false
  @State private var operation: String?
  @State private var error: String?
  @State private var recent: [String] = []
  @State private var access = EKEventStore.authorizationStatus(for: .event)
  @State private var initialized = false
  @State private var generation = UUID()
  private var busy: Bool { operation != nil }
  private var valid: Bool { destinations.contains { $0.id == calendarID && $0.writable } }
  var body: some View {
    if embedded { content } else { NavigationStack { content } }
  }
  private var content: some View {
    Form {
      Section {
        if access == .fullAccess {
          LabeledContent("Kalenderzugriff", value: "Erlaubt")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Kalenderzugriff").accessibilityValue("Erlaubt")
            .accessibilityIdentifier("destination-access")
        } else if access == .notDetermined || access == .writeOnly {
          Button("Kalenderzugriff erlauben") {
            perform("Zugriff prüfen …") { await load(requestAccess: true) }
          }.disabled(busy)
        } else {
          LabeledContent(
            "Kalenderzugriff", value: access == .restricted ? "Eingeschränkt" : "Verweigert")
          Button("Einstellungen öffnen") {
            openURL(URL(string: UIApplication.openSettingsURLString)!)
          }
        }
        Button("Klinik-Kalender auswählen") {
          perform("Klinik-Kalender auswählen …") {
            await load(requestAccess: true, dedicated: true)
          }
        }
        .disabled(busy || access == .denied || access == .restricted)
        .accessibilityIdentifier("select-clinic-calendar")
      } header: {
        HStack {
          Text("Speicherziel")
          Spacer()
          ContextHelp(
            "Speicherziel",
            "Die Auswahl gilt für neue Termine beziehungsweise diesen Plan. Bestehende Termine werden nicht verschoben. Anzeigen und Vorlesen werden getrennt eingestellt."
          )
        }
      }
      Section("Kalender auswählen") {
        ForEach(
          destinations.sorted { a, b in
            let x = recent.firstIndex(of: a.id) ?? Int.max
            let y = recent.firstIndex(of: b.id) ?? Int.max
            return x == y ? (a.title, a.source, a.id) < (b.title, b.source, b.id) : x < y
          }
        ) { calendar in
          Button {
            calendarID = calendar.id
          } label: {
            CalendarChoiceRow(calendar: calendar, selected: calendarID == calendar.id)
          }.buttonStyle(.plain).disabled(!calendar.writable || busy)
        }
      }
      if planID != nil { Toggle("Für neue Pläne merken", isOn: $remember).disabled(busy) }
      if let error { Text(error).foregroundStyle(AppPalette.destructive) }
      if let operation { ProcessingRow(text: operation) }
    }.pageTitle("Speicherziel")
      .toolbar {
        if !embedded {
          ToolbarItem(placement: .cancellationAction) {
            Button("Abbrechen") { dismiss() }.disabled(busy)
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Fertig") { perform("Auswahl speichern …") { await save() } }
            .disabled(busy || !valid).accessibilityIdentifier("save-calendar-destination")
        }
      }
      .interactiveDismissDisabled(busy).navigationBarBackButtonHidden(embedded && busy)
      .task {
        guard !busy else { return }
        let token = generation
        operation = "Kalender laden …"
        defer { if generation == token { operation = nil } }
        await store.load()
        await load()
      }
      .onChange(of: scenePhase) { _, phase in
        if phase == .active && !busy { perform("Kalender laden …") { await load() } }
      }
      .onDisappear {
        generation = UUID()
        operation = nil
      }
  }
  private func perform(_ title: String, action: @escaping @MainActor () async -> Void) {
    guard !busy else { return }
    let token = generation
    operation = title
    Task {
      guard generation == token else { return }
      await action()
      if generation == token { operation = nil }
    }
  }
  private func load(requestAccess: Bool = false, dedicated: Bool = false) async {
    let token = generation
    do {
      let preferences = try await core.preferences()
      var selected = calendarID
      if !initialized {
        if let planID {
          selected = try await core.planCalendar(id: planID).calendarId
        } else {
          selected = preferences.calendarId
        }
      }
      var response: CalendarDestinations?
      if requestAccess {
        response = try JSONDecoder().decode(
          CalendarDestinations.self,
          from: await NativeBridge.request("calendars", ["dedicated": dedicated]))
      }
      let authorization = EKEventStore.authorizationStatus(for: .event)
      let available =
        authorization == .fullAccess
        ? try JSONDecoder().decode(
          CalendarDestinations.self, from: await NativeBridge.request("eventCalendars")
        ).calendars : []
      guard token == generation, !Task.isCancelled else { return }
      recent = preferences.recentCalendarIds
      access = authorization
      destinations = available
      calendarID = response?.dedicated_id ?? selected
      initialized = true
      error = response?.setup_error
    } catch {
      guard token == generation, !Task.isCancelled else { return }
      access = EKEventStore.authorizationStatus(for: .event)
      self.error = userMessage(error)
    }
  }
  private func save() async {
    guard valid else { return }
    let token = generation
    let selected = calendarID
    do {
      if let planID { try await core.selectPlanCalendar(id: planID, calendarId: selected) }
      let makeDefault = planID == nil || remember
      store.change { p in
        if makeDefault { p.calendarId = selected }
        p.recentCalendarIds = [selected] + p.recentCalendarIds.filter { $0 != selected }.prefix(9)
      }
      let saved = await store.flush()
      guard token == generation, !Task.isCancelled else { return }
      if saved { dismiss() } else { error = store.error }
    } catch { if token == generation { self.error = userMessage(error) } }
  }
}
struct CalendarChoiceRow: View {
  let calendar: CalendarDestinations.Destination
  let selected: Bool
  var body: some View {
    HStack(spacing: AppSpacing.section) {
      if let color = calendar.color_components, color.count == 3 {
        Circle().fill(Color(red: color[0], green: color[1], blue: color[2])).frame(
          width: 16, height: 16
        ).accessibilityHidden(true)
      }
      VStack(alignment: .leading, spacing: AppSpacing.small) {
        Text(calendar.title).font(.headline)
        Text(calendar.source).foregroundStyle(.secondary)
        if !calendar.writable { Text("Nur anzeigen und vorlesen").foregroundStyle(.secondary) }
      }.fixedSize(horizontal: false, vertical: true)
      Spacer()
      if selected {
        Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint).accessibilityHidden(true)
      }
    }.controlHeight().accessibilityElement(children: .combine).accessibilityAddTraits(
      selected ? [.isSelected] : [])
  }
}
struct CalendarPreferencesView: View {
  let core: NativeApplication
  @Environment(PreferencesStore.self) private var store
  @State private var destinations: [CalendarDestinations.Destination] = []
  @State private var error: String?
  private var destinationTitle: String {
    destinations.first { $0.id == store.value?.calendarId }.map {
      "\($0.title) · \($0.source)"
    } ?? "Noch nicht ausgewählt"
  }
  var body: some View {
    Form {
      Section {
        ForEach(destinations) { calendar in
          Toggle(
            isOn: Binding(
              get: { store.value?.displayCalendarIds.contains(calendar.id) == true },
              set: { visible in select(calendar.id, visible) })
          ) {
            CalendarChoiceRow(calendar: calendar, selected: false)
          }
        }
        if destinations.isEmpty { Button("Kalenderzugriff erlauben") { Task { await load() } } }
      } header: {
        HStack {
          Text("Anzeigen und vorlesen")
          Spacer()
          ContextHelp(
            "Anzeigen und vorlesen",
            "Importierte Termine bleiben sichtbar. Weitere Kalender können hier ausgewählt werden.")
        }
      }
      if let preferences = store.value {
        let missing = preferences.displayCalendarIds.filter { id in
          !destinations.contains { $0.id == id }
        }
        if !missing.isEmpty {
          Section("Nicht verfügbare Kalender") {
            ForEach(missing, id: \.self) { id in
              Button("Kalender …\(id.suffix(6)) aus Auswahl entfernen") { select(id, false) }
            }
          }
        }
      }
      Section {
        LabeledContent("Speicherziel", value: destinationTitle)
          .accessibilityElement(children: .ignore)
          .accessibilityLabel("Speicherziel").accessibilityValue(destinationTitle)
          .accessibilityIdentifier("calendar-destination")
        NavigationLink("Speicherziel ändern") { CalendarSetupView(core: core, embedded: true) }
        if let id = store.value?.calendarId, !id.isEmpty,
          store.value?.displayCalendarIds.contains(id) == false
        {
          Button("Auch anzeigen") { select(id, true) }
        }
      } header: {
        HStack {
          Text("Neue Termine")
          Spacer()
          ContextHelp(
            "Neue Termine", "Ein neues Speicherziel verschiebt keine bestehenden Termine.")
        }
      }
      SettingsSaveStatus()
      if let error { Section { Text(error).foregroundStyle(AppPalette.destructive) } }
      Section { Button("Kalender neu laden") { Task { await load() } } }
    }.pageTitle("Kalender").task {
      await store.load()
      await load()
    }
  }
  private func load() async {
    do {
      _ = try await NativeBridge.request("calendars", ["dedicated": false])
      destinations = try JSONDecoder().decode(
        CalendarDestinations.self, from: await NativeBridge.request("eventCalendars")
      ).calendars
      error = nil
    } catch { self.error = userMessage(error) }
  }
  private func select(_ id: String, _ visible: Bool) {
    store.change { p in
      p.displayCalendarIds.removeAll { $0 == id }
      if visible { p.displayCalendarIds.append(id) }
    }
  }
}
