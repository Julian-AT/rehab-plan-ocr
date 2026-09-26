import EventKit
import RehaCore
import SwiftUI

struct CalendarSetupView: View {
  let core: NativeApplication
  var planID: String? = nil
  var embedded = false
  @Environment(PreferencesStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @State private var destinations: [CalendarDestinations.Destination] = []
  @State private var calendarID = ""
  @State private var remember = false
  @State private var busy = false
  @State private var error: String?
  @State private var recent: [String] = []
  var body: some View {
    if embedded { content } else { NavigationStack { content } }
  }
  private var content: some View {
    Form {
      Section {
        ForEach(
          destinations.filter(\.writable).sorted { a, b in
            let x = recent.firstIndex(of: a.id) ?? Int.max
            let y = recent.firstIndex(of: b.id) ?? Int.max
            return x == y ? (a.title, a.source, a.id) < (b.title, b.source, b.id) : x < y
          }
        ) { calendar in
          Button {
            calendarID = calendar.id
          } label: {
            CalendarChoiceRow(calendar: calendar, selected: calendarID == calendar.id)
          }.buttonStyle(.plain).disabled(busy)
            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
            .accessibilityIdentifier("destination-\(calendar.id)")
        }
      }
      if planID != nil { Toggle("Für neue Pläne merken", isOn: $remember) }
      if let error { Text(error).foregroundStyle(AppPalette.destructive) }
      if EKEventStore.authorizationStatus(for: .event) == .notDetermined
        || EKEventStore.authorizationStatus(for: .event) == .writeOnly
      {
        AppFormAction(title: "Kalenderzugriff erlauben", systemImage: "calendar", busy: busy) {
          Task { await load(requestAccess: true) }
        }
      } else if EKEventStore.authorizationStatus(for: .event) == .denied {
        Link(
          "Zugriff in Einstellungen erlauben",
          destination: URL(string: UIApplication.openSettingsURLString)!)
      } else if !busy && destinations.allSatisfy({ !$0.writable }) {
        Text("Kein beschreibbarer Kalender verfügbar.").foregroundStyle(AppPalette.secondaryText)
      }
      if busy { ProcessingRow(text: "Kalender laden …") }
    }.pageTitle("Speicherziel")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Fertig") { Task { await save() } }
            .disabled(busy || !destinations.contains { $0.id == calendarID && $0.writable })
            .accessibilityIdentifier("save-calendar-destination")
        }
        if !embedded {
          ToolbarItem(placement: .cancellationAction) {
            Button("Abbrechen") { dismiss() }.disabled(busy)
          }
        }
      }
      .task {
        await store.load()
        await load(requestAccess: false)
      }
  }
  private func load(requestAccess: Bool) async {
    busy = true
    defer { busy = false }
    do {
      let preferences = try await core.preferences()
      recent = preferences.recentCalendarIds
      if let planID {
        calendarID = try await core.planCalendar(id: planID).calendarId
      } else {
        calendarID = preferences.calendarId
      }
      if requestAccess { _ = try await NativeBridge.request("calendars", ["dedicated": false]) }
      guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return }
      destinations = try JSONDecoder().decode(
        CalendarDestinations.self, from: await NativeBridge.request("eventCalendars")
      ).calendars
      error = nil
    } catch { self.error = userMessage(error) }
  }
  private func save() async {
    busy = true
    defer { busy = false }
    do {
      if let planID { try await core.selectPlanCalendar(id: planID, calendarId: calendarID) }
      let selected = calendarID
      let makeDefault = planID == nil || remember
      store.change { p in
        if makeDefault { p.calendarId = selected }
        p.recentCalendarIds = [selected] + p.recentCalendarIds.filter { $0 != selected }.prefix(9)
      }
      if await store.flush() { dismiss() } else { error = store.error }
    } catch { self.error = userMessage(error) }
  }
}
struct CalendarChoiceRow: View {
  let calendar: CalendarDestinations.Destination
  let selected: Bool
  var body: some View {
    HStack(spacing: 10) {
      if let color = calendar.color_components, color.count == 3 {
        Circle().fill(Color(red: color[0], green: color[1], blue: color[2])).frame(
          width: 16, height: 16
        ).accessibilityHidden(true)
      }
      VStack(alignment: .leading, spacing: 2) {
        Text(calendar.title).font(.body)
        Text(calendar.source + (calendar.writable ? "" : " · Nur lesbar"))
          .font(.caption).foregroundStyle(AppPalette.secondaryText)
      }.fixedSize(horizontal: false, vertical: true)
      Spacer()
      if selected {
        Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint).accessibilityHidden(true)
      }
    }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(.rect)
      .accessibilityElement(
        children: .combine
      ).accessibilityAddTraits(
        selected ? [.isSelected] : [])
  }
}
struct CalendarPreferencesView: View {
  let core: NativeApplication
  @Environment(PreferencesStore.self) private var store
  @State private var destinations: [CalendarDestinations.Destination] = []
  @State private var error: String?
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
          .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
        }
        if destinations.isEmpty { Button("Kalenderzugriff erlauben") { Task { await load() } } }
      } header: {
        Text("Anzeigen und vorlesen")
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
        NavigationLink {
          CalendarSetupView(core: core, embedded: true)
        } label: {
          LabeledContent(
            "Speicherziel",
            value: destinations.first { $0.id == store.value?.calendarId }?.title
              ?? "Auswählen"
          )
          .frame(minHeight: 44).contentShape(.rect)
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
        .accessibilityIdentifier("calendar-destination")
        if let id = store.value?.calendarId, !id.isEmpty,
          store.value?.displayCalendarIds.contains(id) == false
        {
          AppFormAction(title: "Auch anzeigen") { select(id, true) }
        }
      } header: {
        Text("Neue Termine")
      }
      SettingsSaveStatus()
      if let error { Section { Text(error).foregroundStyle(AppPalette.destructive) } }
      Section {
        AppFormAction(title: "Kalender neu laden", systemImage: "arrow.clockwise") {
          Task { await load() }
        }
      }
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
