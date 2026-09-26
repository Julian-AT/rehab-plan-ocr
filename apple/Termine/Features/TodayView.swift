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
    func refresh(_ core: NativeApplication, week: AgendaWeek) async {
        revision += 1; let request = revision
        availability = .loading; events = []; error = nil
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            availability = .noAccess; return
        }
        struct Response: Decodable { let events: [CalendarEvent] }
        do {
            let history = try await core.history(); let preferences = try await core.preferences()
            guard request == revision, !Task.isCancelled else { return }
            guard !preferences.displayCalendarIds.isEmpty || !history.imports.isEmpty else {
                availability = .noSelection; return
            }
            _ = try await NativeBridge.request("agenda", ["records": history.imports.map(NativeBridge.record), "preferences": NativeBridge.preferences(preferences)])
            let iso = ISO8601DateFormatter()
            let result = try await core.eventRequest("queryCalendarEvents", ["start_utc": iso.string(from: week.start), "end_utc": iso.string(from: week.end)], as: Response.self)
            guard request == revision, !Task.isCancelled else { return }
            events = result.events; availability = .ready
        } catch {
            guard request == revision, !Task.isCancelled else { return }
            self.error = userMessage(error); availability = .failed
        }
    }
}

struct TodayView: View {
    let core: NativeApplication
    let scanner: ScanModel
    let refreshID: Int
    @State private var model = TodayModel()
    @State private var selectedDate = Calendar.current.startOfDay(for: .now)
    @State private var observedToday = Calendar.current.startOfDay(for: .now)
    @State private var setup = false
    @State private var editor: CalendarEvent?
    @State private var create = false
    @State private var showPast = false
    @State private var reloadID = 0
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var typeSize
    private var week: AgendaWeek { AgendaWeek(containing: selectedDate) }
    private var requestID: String { "\(week.start.timeIntervalSince1970)-\(refreshID)-\(reloadID)" }

    var body: some View {
        VStack(spacing: 0) {
            WeekSelector(selection: $selectedDate)
            Divider()
            TimelineView(.periodic(from: .now, by: 15)) { context in
                let agenda = DayAgenda(events: model.events, date: selectedDate, now: context.date)
                Group {
                    if model.availability != .ready { unavailable }
                    else if agenda.events.isEmpty {
                        ContentUnavailableView {
                            Label(Calendar.current.isDateInToday(selectedDate) ? "Heute keine Termine" : "Keine Termine", systemImage: "calendar")
                        } description: { Text("Für diesen Tag sind keine Termine eingetragen.") }
                    } else if agenda.isComplete && !showPast {
                        ContentUnavailableView {
                            Label("Zeit zum Erholen", systemImage: "leaf")
                        } description: { Text("Für heute stehen keine weiteren Termine an.") }
                        actions: { Button("Vergangene Termine anzeigen") { showPast = true }.accessibilityIdentifier("past-events") }
                    } else if typeSize.isAccessibilitySize {
                        List {
                            ForEach(agenda.events) { event in
                                Button { editor = event } label: { CalendarAgendaRow(event: event, now: context.date) }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("agenda-event-\(event.id)")
                            }
                        }.accessibilityIdentifier("agenda-accessible-list")
                    } else {
                        DayTimeline(agenda: agenda, now: context.date) { editor = $0 }
                            .id(selectedDate)
                    }
                }
                .onChange(of: Calendar.current.startOfDay(for: context.date)) { _, today in followToday(today) }
            }
        }
        .background(Color(uiColor: .systemBackground))
        .pageTitle("Termine")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Heute") { selectedDate = Calendar.current.startOfDay(for: .now); showPast = false; reload() }
                    .accessibilityIdentifier("agenda-today")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    CaptureActions(scanner: scanner, context: "plan-menu")
                    Divider()
                    Button("Termin hinzufügen", systemImage: "calendar.badge.plus") { create = true }
                } label: { Label("Plan hinzufügen", systemImage: "plus") }
                    .accessibilityIdentifier("add-plan")
            }
        }
        .refreshable { await model.refresh(core, week: week) }
        .task(id: requestID) { await model.refresh(core, week: week) }
        .onChange(of: selectedDate) { showPast = false }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { followToday(Calendar.current.startOfDay(for: .now)); reload() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            followToday(Calendar.current.startOfDay(for: .now)); reload()
        }
        .navigationDestination(isPresented: $setup) { CalendarPreferencesView(core: core) }
        .sheet(item: $editor, onDismiss: reload) { event in EventEditorView(core: core, original: event, changed: reload) }
        .sheet(isPresented: $create, onDismiss: reload) { EventEditorView(core: core, changed: reload) }
    }
    private func reload() { reloadID += 1 }
    private func followToday(_ today: Date) {
        if selectedDate == observedToday { selectedDate = today }
        observedToday = today
    }
    @ViewBuilder private var unavailable: some View {
        switch model.availability {
        case .loading: ProgressView("Kalender laden …").frame(maxWidth: .infinity, maxHeight: .infinity)
        case .noAccess:
            ContentUnavailableView {
                Label("Kalenderzugriff fehlt", systemImage: "calendar.badge.exclamationmark")
            } description: { Text("Erlaube den Zugriff, damit deine Termine hier erscheinen.") } actions: {
                if EKEventStore.authorizationStatus(for: .event) == .notDetermined {
                    Button("Kalenderzugriff erlauben") { setup = true }
                } else {
                    Button("Einstellungen öffnen") { openURL(URL(string: UIApplication.openSettingsURLString)!) }
                }
            }
        case .noSelection:
            ContentUnavailableView {
                Label("Kalender auswählen", systemImage: "calendar")
            } description: { Text("Wähle die Kalender aus, deren Termine du sehen möchtest.") }
            actions: { Button("Kalender auswählen") { setup = true } }
        case .failed:
            ContentUnavailableView {
                Label("Kalender nicht verfügbar", systemImage: "exclamationmark.circle")
            } description: { Text(model.error ?? "Bitte versuche es erneut.") }
            actions: { Button("Erneut versuchen", action: reload); Button("Kalender prüfen") { setup = true } }
        case .ready: EmptyView()
        }
    }
}

private struct WeekSelector: View {
    @Binding var selection: Date
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button("Vorherige Woche", systemImage: "chevron.left") { move(-7) }
                    .labelStyle(.iconOnly).controlHeight().accessibilityIdentifier("previous-week")
                Spacer()
                Text(selection.formatted(.dateTime.month(.wide).year())).font(.headline)
                Spacer()
                Button("Nächste Woche", systemImage: "chevron.right") { move(7) }
                    .labelStyle(.iconOnly).controlHeight().accessibilityIdentifier("next-week")
            }
            if typeSize.isAccessibilitySize {
                DatePicker("Tag", selection: $selection, displayedComponents: .date)
                    .labelsHidden().accessibilityLabel("Tag")
                    .accessibilityIdentifier("agenda-date")
            } else {
                HStack(spacing: 0) {
                    ForEach(AgendaWeek(containing: selection).days, id: \.self) { date in
                        let selected = Calendar.current.isDate(date, inSameDayAs: selection)
                        Button { selection = date } label: {
                            VStack(spacing: 6) {
                                Text(date.formatted(.dateTime.weekday(.abbreviated))).font(.caption).foregroundStyle(.secondary)
                                Text(date.formatted(.dateTime.day())).font(.body)
                                    .frame(width: 40, height: 40)
                                    .foregroundStyle(selected ? .white : .primary)
                                    .background(selected ? AppPalette.tint : .clear, in: .circle)
                            }.frame(maxWidth: .infinity).padding(.vertical, 4).contentShape(.rect)
                        }.buttonStyle(.plain)
                            .accessibilityLabel(date.formatted(.dateTime.weekday(.wide).day().month().year()))
                            .accessibilityAddTraits(selected ? .isSelected : [])
                            .accessibilityIdentifier("weekday-\(Calendar.current.component(.weekday, from: date))")
                    }
                }
            }
        }.padding(.horizontal).padding(.vertical, 8)
    }
    private func move(_ days: Int) { selection = Calendar.current.date(byAdding: .day, value: days, to: selection)! }
}

private struct DayTimeline: View {
    let agenda: DayAgenda
    let now: Date
    let select: (CalendarEvent) -> Void
    private let hourHeight = 96.0
    @State private var position = ScrollPosition()
    @State private var positioned = false
    var body: some View {
        let window = AgendaWindow(agenda: agenda, now: now)
        VStack(spacing: 0) {
                    if !agenda.allDay.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Ganztägig").font(.subheadline).foregroundStyle(.secondary)
                            ForEach(agenda.allDay) { event in
                                Button { select(event) } label: {
                                    Label(event.values.title, systemImage: "calendar").frame(maxWidth: .infinity, alignment: .leading)
                                }.buttonStyle(.bordered).controlHeight()
                                    .accessibilityLabel("Ganztägig, \(event.values.title)")
                                    .accessibilityIdentifier("agenda-event-\(event.id)")
                            }
                        }.padding(.horizontal)
                    }
            ScrollView {
                    GeometryReader { geometry in
                        let width = max(0, geometry.size.width - 64)
                        ZStack(alignment: .topLeading) {
                            ForEach(0...Int(window.minutes / 60), id: \.self) { hour in
                                let date = window.start.addingTimeInterval(Double(hour) * 3600)
                                HStack(spacing: 8) {
                                    Text(eventTime(date)).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                                        .frame(width: 48, alignment: .trailing).accessibilityIdentifier("timeline-hour-\(hour + 6)")
                                    Rectangle().fill(Color(uiColor: .separator).opacity(0.4)).frame(height: 0.5)
                                }.frame(height: 16).offset(y: Double(hour) * hourHeight).id(hour)
                            }
                            ForEach(AgendaLayout.place(window.timed, pointsPerHour: hourHeight)) { item in
                                let columnWidth = width / Double(item.columns)
                                Button { select(item.segment.event) } label: {
                                    block(item.segment.event, compact: item.height < 70)
                                        .padding(.horizontal, 8).padding(.vertical, 4)
                                        .frame(width: max(0, columnWidth - 4), height: item.height, alignment: .topLeading)
                                        .background(AppPalette.tint.opacity(0.2), in: .rect(cornerRadius: 10))
                                        .clipped().contentShape(.rect)
                                }.buttonStyle(.plain)
                                    .offset(x: 56 + Double(item.column) * columnWidth, y: item.segment.start / 60 * hourHeight + 8)
                                    .accessibilityLabel(item.segment.event.spoken + (item.segment.event.values.end <= now ? " Vorbei." : ""))
                                    .accessibilityIdentifier("agenda-event-\(item.id)")
                            }

                        }
                    }.frame(height: window.minutes / 60 * hourHeight + 52)
                    .padding(.vertical, 12)
            }.accessibilityIdentifier("day-timeline")
                .scrollPosition($position)
                .onScrollGeometryChange(for: Bool.self) { $0.containerSize.height > 0 && $0.contentSize.height > 0 } action: { _, ready in
                    if ready && !positioned { positioned = true; position.scrollTo(y: window.scrollMinute / 60 * hourHeight) }
                }
            if !window.outside.isEmpty {
                DisclosureGroup("Außerhalb von 06:00–18:00") {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(window.outside) { event in
                                Button { select(event) } label: { CalendarAgendaRow(event: event, now: now) }
                                    .buttonStyle(.plain).accessibilityIdentifier("agenda-event-\(event.id)")
                            }
                        }
                    }.frame(maxHeight: 200)
                }.padding().accessibilityIdentifier("agenda-outside-hours")
            }
        }
    }
    private func block(_ event: CalendarEvent, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(event.values.title).font(.subheadline.weight(.semibold)).lineLimit(compact ? 1 : 2)
            Text("\(eventTime(event.values.start))–\(eventTime(event.values.end))\(compact || event.values.location.isEmpty ? "" : " · " + event.values.location)")
                .font(.caption).foregroundStyle(.secondary).lineLimit(compact ? 1 : 2)
        }.foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading)
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
