import SwiftUI
import RehaCore
import AppleServices
import EventKit

@MainActor @Observable final class TodayModel {
    enum Availability { case loading, ready, noAccess, noSelection, failed }
    var events: [CalendarEvent] = []
    var availability: Availability = .loading
    var error: String?
    private var revision = 0
    func refresh(_ core: NativeApplication) async {
        revision += 1; let request = revision
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            events = []; availability = .noAccess; return
        }
        struct Response: Decodable { let events: [CalendarEvent] }
        do {
            let history = try await core.history(); let preferences = try await core.preferences()
            guard request == revision else { return }
            guard !preferences.displayCalendarIds.isEmpty || !history.imports.isEmpty else {
                events = []; availability = .noSelection; return
            }
            _ = try await NativeBridge.request("agenda", ["records": history.imports.map(NativeBridge.record), "preferences": NativeBridge.preferences(preferences)])
            let start = Calendar.current.startOfDay(for: .now)
            let end = Calendar.current.date(byAdding: .day, value: 90, to: start)!
            let iso = ISO8601DateFormatter()
            let result = try await core.eventRequest("queryCalendarEvents", ["start_utc": iso.string(from: start), "end_utc": iso.string(from: end)], as: Response.self)
            guard request == revision else { return }
            events = result.events; error = nil; availability = .ready
        } catch {
            guard request == revision else { return }
            self.error = userMessage(error); events = []; availability = .failed
        }
    }
}
struct TodayView: View {
    let core: NativeApplication
    let scanner: ScanModel
    let refreshID: Int
    @State private var model = TodayModel()
    @State private var setup = false
    @State private var editor: CalendarEvent?
    @State private var create = false
    @State private var showPast = false
    @State private var visibleDays = 0
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let agenda = AgendaProjection(events: model.events, now: context.date)
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.section) {
                        if model.availability != .ready {
                            unavailable.frame(maxWidth: .infinity, minHeight: max(0, geometry.size.height - 42))
                        } else if agenda.today.isEmpty && visibleDays == 0 {
                            empty(agenda: agenda).frame(maxWidth: .infinity, minHeight: max(0, geometry.size.height - 42))
                        } else {
                            if agenda.today.isEmpty { empty(agenda: agenda).padding(.vertical, AppSpacing.generous) }
                            else {
                                Text(context.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                                    .font(.headline).accessibilityIdentifier("today-summary").accessibilityAddTraits(.isHeader)
                                eventRows(agenda.remaining, agenda: agenda, now: context.date)
                                if !agenda.past.isEmpty {
                                    VStack(spacing: AppSpacing.small) {
                                        Button { showPast.toggle() } label: {
                                            HStack(spacing: AppSpacing.medium) {
                                                Label("Bereits vorbei · \(agenda.past.count)", systemImage: "clock")
                                                Spacer()
                                                Image(systemName: showPast ? "chevron.up" : "chevron.down")
                                            }.font(.subheadline).foregroundStyle(.secondary).controlHeight().contentShape(.rect)
                                        }.buttonStyle(.plain).accessibilityIdentifier("past-events")
                                            .accessibilityValue(showPast ? "Ausgeklappt" : "Eingeklappt")
                                        if showPast { eventRows(agenda.past, agenda: agenda, now: context.date) }
                                    }
                                }
                            }
                            ForEach(Array(agenda.future.prefix(visibleDays))) { day in
                                VStack(alignment: .leading, spacing: AppSpacing.medium) {
                                    Text(day.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                                        .font(.headline).accessibilityAddTraits(.isHeader)
                                    eventRows(day.events, agenda: agenda, now: context.date)
                                }.accessibilityElement(children: .contain).accessibilityIdentifier("agenda-day-\(Int(day.date.timeIntervalSince1970))")
                            }
                            if visibleDays < agenda.future.count { moreDays }
                        }
                    }.padding(AppSpacing.section)
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
        .pageTitle("Termine")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    CaptureActions(scanner: scanner, context: "plan-menu")
                    Divider()
                    Button("Termin hinzufügen", systemImage: "calendar.badge.plus") { create = true }
                } label: { Label("Plan hinzufügen", systemImage: "plus").frame(minWidth: 44, minHeight: 44) }
                    .accessibilityIdentifier("add-plan")
            }
        }
        .refreshable { await model.refresh(core) }
        .task(id: refreshID) { await model.refresh(core) }
        .onChange(of: scenePhase) { _, phase in if phase == .active { reload() } }
        .sheet(isPresented: $setup, onDismiss: reload) { NavigationStack { CalendarPreferencesView(core: core) } }
        .sheet(item: $editor, onDismiss: reload) { event in EventEditorView(core: core, original: event, changed: reload) }
        .sheet(isPresented: $create, onDismiss: reload) { EventEditorView(core: core, changed: reload) }
    }
    private func reload() { Task { await model.refresh(core) } }
    @ViewBuilder private var unavailable: some View {
        VStack(spacing: AppSpacing.medium) {
            switch model.availability {
            case .loading: ProgressView("Kalender laden …")
            case .noAccess:
                Image(systemName: "calendar.badge.exclamationmark").font(.title2).foregroundStyle(.secondary)
                Text("Kalenderzugriff fehlt").font(.headline)
                Text("Erlaube den Zugriff, damit deine Termine hier erscheinen.").foregroundStyle(.secondary)
                if EKEventStore.authorizationStatus(for: .event) == .notDetermined {
                    Button("Kalenderzugriff erlauben") { setup = true }.buttonStyle(PrimaryActionStyle())
                } else {
                    Button("Einstellungen öffnen") { openURL(URL(string: UIApplication.openSettingsURLString)!) }.buttonStyle(PrimaryActionStyle())
                }
            case .noSelection:
                Image(systemName: "calendar").font(.title2).foregroundStyle(.secondary)
                Text("Kalender auswählen").font(.headline)
                Text("Wähle die Kalender aus, deren Termine du sehen möchtest.").foregroundStyle(.secondary)
                Button("Kalender auswählen") { setup = true }.buttonStyle(PrimaryActionStyle())
            case .failed:
                Image(systemName: "exclamationmark.circle").font(.title2)
                Text("Kalender nicht verfügbar").font(.headline)
                Text(model.error ?? "Bitte versuche es erneut.").foregroundStyle(.secondary)
                Button("Erneut versuchen", action: reload).buttonStyle(PrimaryActionStyle())
                Button("Kalender prüfen") { setup = true }.controlHeight()
            case .ready: EmptyView()
            }
        }.multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
    }
    private func empty(agenda: AgendaProjection) -> some View {
        VStack(spacing: AppSpacing.medium) {
            Image(systemName: "calendar").font(.title2).foregroundStyle(.secondary).accessibilityHidden(true)
            Text("Heute keine Termine").font(.headline).accessibilityIdentifier("today-summary")
            if agenda.future.isEmpty {
                Menu { CaptureActions(scanner: scanner, context: "empty-agenda") } label: {
                    Text("Plan hinzufügen").controlHeight()
                }.buttonStyle(PrimaryActionStyle())
            } else if visibleDays == 0 { moreDays }
        }.multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
    }
    private var moreDays: some View {
        Button { visibleDays += 3 } label: {
            Label("Weitere Tage anzeigen", systemImage: "chevron.down")
                .font(.body).frame(maxWidth: .infinity).controlHeight().contentShape(.rect)
        }.buttonStyle(.plain).accessibilityIdentifier("load-more-days")
    }
    private func eventRows(_ events: [CalendarEvent], agenda: AgendaProjection, now: Date) -> some View {
        VStack(spacing: 0) {
            ForEach(events) { event in
                Button { editor = event } label: {
                    CalendarAgendaRow(event: event, now: now, marker: agenda.marker(for: event, now: now))
                        .padding(.vertical, AppSpacing.medium).controlHeight()
                }.buttonStyle(.plain).accessibilityIdentifier("agenda-event-\(event.id)")
                Divider()
            }
        }
    }
}
struct CalendarAgendaRow: View {
    let event: CalendarEvent
    let now: Date
    var marker: String? = nil
    @ScaledMetric(relativeTo: .body) private var timeWidth = 76
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: AppSpacing.small)) : AnyLayout(HStackLayout(alignment: .top, spacing: AppSpacing.section))
        layout {
            VStack(alignment: .leading, spacing: AppSpacing.small) {
                if event.isAllDay {
                    Text("Ganztägig").font(.subheadline)
                } else {
                    Text(eventTime(event.values.start)).font(.body.weight(.semibold)).monospacedDigit()
                    Text(eventTime(event.values.end)).font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                }
            }.frame(width: timeWidth, alignment: .leading)
            VStack(alignment: .leading, spacing: AppSpacing.small) {
                if let marker { Text(marker).font(.subheadline.weight(.semibold)) }
                Text(event.values.title).font(.body.weight(.medium))
                if !event.values.location.isEmpty { Text(event.values.location).font(.body).foregroundStyle(.secondary) }
                if !Calendar.current.isDate(event.values.start, inSameDayAs: event.values.end.addingTimeInterval(-1)) {
                    Text(span).font(.subheadline).foregroundStyle(.secondary)
                }
                Text(event.source.isEmpty ? event.calendar_title : "\(event.calendar_title) · \(event.source)")
                    .font(.subheadline).foregroundStyle(.secondary)
                if event.values.end <= now { Text("Vorbei").font(.subheadline).foregroundStyle(.secondary) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.fixedSize(horizontal: false, vertical: true).foregroundStyle(.primary).contentShape(.rect).accessibilityElement(children: .combine)
    }
    private var span: String {
        let start = event.values.start.formatted(.dateTime.day().month(.abbreviated))
        let end = (event.isAllDay ? event.values.end.addingTimeInterval(-1) : event.values.end).formatted(.dateTime.day().month(.abbreviated))
        return "\(start) – \(end)"
    }
}
struct ProcessingRow: View {
    let text: String
    var body: some View {
        HStack(spacing: AppSpacing.medium) { ProgressView().accessibilityHidden(true); Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, AppSpacing.small)
            .accessibilityElement(children: .combine).accessibilityLabel(text)
    }
}
