import SwiftUI
import RehaCore
import AppleServices
import EventKit

/// Cache keys are civil Mondays. A new refresh epoch rejects all older loads.
@MainActor @Observable final class TodayModel {
    enum Availability { case loading, ready, noAccess, noSelection, failed }
    private var cache: [Date: [CalendarEvent]] = [:]
    var availability: Availability = .loading
    var error: String?
    private var epoch = UUID()
    private var refreshKey = ""
    func events(on date: Date) -> [CalendarEvent]? { cache[AgendaWeek(containing: date).start] }
    func refresh(_ core: NativeApplication, week: AgendaWeek, visibleWeek: Date, key: String) async {
        if key != refreshKey { refreshKey = key; epoch = UUID(); cache = [:] }
        let request = epoch
        let weeks = [week.start, visibleWeek].flatMap { center in
            [-7, 0, 7].map { AgendaWeek(containing: Calendar.current.date(byAdding: .day, value: $0, to: center)!) }
        }
        let keep = Set(weeks.map(\.start))
        cache = cache.filter { keep.contains($0.key) }
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            cache = [:]; availability = .noAccess; return
        }
        struct Response: Decodable { let events: [CalendarEvent] }
        do {
            struct Ownership: Decodable { struct Record: Decodable { let id: String }; let records: [Record] }
            let owned = try await core.eventRequest("ownedEventRecords", [:], as: Ownership.self)
            let preferences = try await core.preferences()
            guard request == epoch, !Task.isCancelled else { return }
            guard !preferences.displayCalendarIds.isEmpty || !owned.records.isEmpty else {
                cache = [:]; availability = .noSelection; return
            }
            _ = try await core.calendarRequest(command: "refreshAgenda", arguments: "{}")
            let iso = ISO8601DateFormatter()
            // Selected week first; a cancelled prefetch never publishes stale data.
            for item in [week] + weeks where cache[item.start] == nil {
                try Task.checkCancellation()
                let result = try await core.eventRequest("queryCalendarEvents", ["start_utc": iso.string(from: item.start), "end_utc": iso.string(from: item.end)], as: Response.self)
                guard request == epoch, !Task.isCancelled else { return }
                cache[item.start] = result.events; availability = .ready; error = nil
            }
        } catch {
            guard request == epoch, !Task.isCancelled else { return }
            self.error = userMessage(error); availability = .failed
        }
    }
}

/// Native paging tracks the finger, exposes neighbours and cancels naturally.
/// Dates retain identity when the bounded window is extended at rest.
private struct CalendarPager<Content: View>: View {
    @Binding var selection: Date
    let step: Int
    @ViewBuilder let content: (Date) -> Content
    @State private var center: Date
    @State private var position: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    init(selection: Binding<Date>, step: Int, @ViewBuilder content: @escaping (Date) -> Content) {
        _selection = selection; self.step = step; self.content = content
        _center = State(initialValue: selection.wrappedValue)
        _position = State(initialValue: selection.wrappedValue)
    }
    private var dates: [Date] { (-14...14).map { Calendar.current.date(byAdding: .day, value: $0 * step, to: center)! } }
    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(dates, id: \.self) { date in
                    content(date).containerRelativeFrame(.horizontal).id(date)
                }
            }.scrollTargetLayout()
        }
        .scrollIndicators(.hidden).scrollTargetBehavior(.paging)
        .scrollPosition(id: $position)
        .onChange(of: position) { _, date in if let date, selection != date { selection = date } }
        .onChange(of: selection) { _, date in
            guard position != date else { return }
            if !dates.contains(date) { center = date }
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) { position = date }
        }
        .onScrollPhaseChange { _, phase in
            if phase == .idle, abs(selection.timeIntervalSince(center)) > Double(step * 7) * 86400 {
                var transaction = Transaction(); transaction.disablesAnimations = true
                withTransaction(transaction) { center = selection; position = selection }
            }
        }
    }
}

struct TodayView: View {
    let core: NativeApplication
    let scanner: ScanModel
    let refreshID: Int
    @SwiftUI.AppStorage("agenda.density") private var density = AgendaDensity.overview.rawValue
    @SwiftUI.AppStorage("agenda.list") private var listView = false
    @State private var model = TodayModel()
    @State private var visibleWeek = AgendaWeek(containing: .now).start
    @State private var measuredHeights: [String: Double] = [:]
    @State private var scrollMinute: Double?
    @State private var scrollReset = 0
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
    init(core: NativeApplication, scanner: ScanModel, refreshID: Int) {
        self.core = core; self.scanner = scanner; self.refreshID = refreshID
    }
    private var week: AgendaWeek { AgendaWeek(containing: selectedDate) }
    private var requestID: String { "\(week.start)-\(visibleWeek)-\(refreshID)-\(reloadID)" }

    var body: some View {
        VStack(spacing: 0) {
            WeekSelector(selection: $selectedDate, visibleWeek: $visibleWeek)
            Divider()
            TimelineView(.periodic(from: .now, by: 15)) { context in
                let agenda = DayAgenda(events: model.events(on: selectedDate) ?? [], date: selectedDate, now: context.date)
                if typeSize.isAccessibilitySize || listView || usesList(agenda) {
                    CalendarPager(selection: $selectedDate, step: 1) { date in
                        day(DayAgenda(events: model.events(on: date) ?? [], date: date, now: context.date), now: context.date)
                    }.accessibilityIdentifier("agenda-days")
                } else {
                    sharedTimeline(now: context.date)
                }
            }.onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
                followToday(Calendar.current.startOfDay(for: .now))
            }

        }
        .contentShape(.rect)
        .accessibilityAction(named: "Nächster Tag") { selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate)! }
        .accessibilityAction(named: "Vorheriger Tag") { selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate)! }
        .background(Color(uiColor: .systemBackground))
        .pageTitle("Termine")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Heute") { selectedDate = Calendar.current.startOfDay(for: .now); visibleWeek = week.start; showPast = false; scrollMinute = nil; scrollReset += 1; reload() }
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
        .refreshable { reload() }
        .task(id: requestID) { await load() }
        .onChange(of: selectedDate) { showPast = false; visibleWeek = week.start }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { followToday(Calendar.current.startOfDay(for: .now)); reload() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged).debounce(for: .milliseconds(500), scheduler: RunLoop.main)) { _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            followToday(Calendar.current.startOfDay(for: .now)); reload()
        }
        .navigationDestination(isPresented: $setup) { CalendarPreferencesView(core: core) }
        .sheet(item: $editor, onDismiss: reload) { event in EventEditorView(core: core, original: event, changed: reload) }
        .sheet(isPresented: $create, onDismiss: reload) { EventEditorView(core: core, changed: reload) }
    }
    private func usesList(_ agenda: DayAgenda) -> Bool {
        let crowded = AgendaLayout.place(agenda.timed, minimumHeight: 0).contains { $0.columns > 2 }
        return typeSize.isAccessibilitySize || listView || crowded
    }
    @ViewBuilder private func day(_ agenda: DayAgenda, now: Date) -> some View {
        Group {
            if model.events(on: agenda.date) == nil {
                if model.availability == .ready { ProgressView("Kalender laden …") } else { unavailable }
            }
            else if agenda.events.isEmpty {
                ContentUnavailableView {
                    Label(Calendar.current.isDateInToday(agenda.date) ? "Heute keine Termine" : "Keine Termine", systemImage: "calendar")
                } description: { Text("Für diesen Tag sind keine Termine eingetragen.") }
            } else if agenda.isComplete && !showPast {
                ContentUnavailableView {
                    Label("Zeit zum Erholen", systemImage: "leaf")
                } description: { Text("Für heute stehen keine weiteren Termine an.") }
                actions: { Button("Vergangene Termine anzeigen") { showPast = true }.accessibilityIdentifier("past-events") }
            } else if usesList(agenda) {
                List {
                    ForEach(agenda.events) { event in
                        Button { editor = event } label: { CalendarAgendaRow(event: event, now: now) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("agenda-event-\(event.id)")
                    }
                }.accessibilityIdentifier("agenda-accessible-list")
            } else {
                DayTimeline(agenda: agenda, now: now, density: AgendaDensity(rawValue: density) ?? .overview, selected: agenda.date == selectedDate, scrollMinute: $scrollMinute, reset: scrollReset) { editor = $0 }
            }
        }
    }
    private func sharedTimeline(now: Date) -> some View {
        let dates = (-1...1).map { Calendar.current.date(byAdding: .day, value: $0, to: selectedDate)! }
        let agendas = dates.map { DayAgenda(events: model.events(on: $0) ?? [], date: $0, now: now) }
        let windows = agendas.map { AgendaWindow(agenda: $0, now: now) }
        let density = AgendaDensity(rawValue: density) ?? .overview
        let projection = ReadableAgendaLayout(windows.flatMap(\.timed), pointsPerHour: density.pointsPerHour, heights: measuredHeights)
        let selected = agendas[1]
        let visible = !selected.events.isEmpty && !(selected.isComplete && !showPast) && model.events(on: selectedDate) != nil
        return VStack(spacing: 0) {
            if !selected.allDay.isEmpty {
                DisclosureGroup("Ganztägig · \(selected.allDay.count)") {
                    ForEach(selected.allDay) { event in
                        Button { editor = event } label: { CalendarAgendaRow(event: event, now: now) }.buttonStyle(.plain)
                    }
                }.padding(.horizontal)
            }
            AgendaScrollView(date: selectedDate, projection: projection, pages: { viewport, offset in
                zip(agendas, windows).map { agenda, window in
                    let layout = ReadableAgendaLayout(segments: window.timed, projection: projection, pointsPerHour: density.pointsPerHour)
                    if agenda.events.isEmpty || (agenda.isComplete && !showPast) || model.events(on: agenda.date) == nil {
                        return AnyView(day(agenda, now: now).frame(height: viewport).offset(y: offset))
                    }
                    return AnyView(TimelineCanvas(window: window, layout: layout, now: now, select: { editor = $0 }) { id, height in
                        if abs((measuredHeights[id] ?? 0) - height) > 1 { measuredHeights[id] = height }
                    })
                }
            }, gutter: AnyView(TimelineGutter(start: windows[1].start, layout: projection)),
               showsTimeline: visible, dataReady: model.events(on: selectedDate) != nil, initialMinute: windows[1].scrollMinute, reset: scrollReset,
               minute: $scrollMinute, selectDate: { selectedDate = $0 })
            if !windows[1].outside.isEmpty {
                DisclosureGroup("Außerhalb von 06:00–18:00") {
                    ScrollView {
                        ForEach(windows[1].outside) { event in
                            Button { editor = event } label: { CalendarAgendaRow(event: event, now: now) }.buttonStyle(.plain)
                        }
                    }.frame(maxHeight: 200)
                }.padding().accessibilityIdentifier("agenda-outside-hours")
            }
        }
    }
    private func load() async {
        await model.refresh(core, week: week, visibleWeek: visibleWeek, key: "\(refreshID)-\(reloadID)-\(Calendar.current.timeZone.identifier)")
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
    @Binding var visibleWeek: Date
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button { move(-7) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44).contentShape(.rect) }
                    .accessibilityLabel("Vorherige Woche").accessibilityIdentifier("previous-week")
                Spacer()
                Text(visibleWeek.formatted(.dateTime.month(.wide).year())).font(.headline)
                Spacer()
                Button { move(7) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44).contentShape(.rect) }
                    .accessibilityLabel("Nächste Woche").accessibilityIdentifier("next-week")
            }
            if typeSize.isAccessibilitySize {
                DatePicker("Tag", selection: $selection, displayedComponents: .date)
                    .labelsHidden().accessibilityLabel("Tag")
                    .accessibilityIdentifier("agenda-date")
            } else {
                CalendarPager(selection: $visibleWeek, step: 7) { monday in
                  HStack(spacing: 0) {
                    ForEach(AgendaWeek(containing: monday).days, id: \.self) { date in
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
                }.frame(height: 78)
            }
        }.padding(.horizontal).padding(.vertical, 6)
            .contentShape(.rect)
            .accessibilityElement(children: .contain).accessibilityIdentifier("agenda-week")
    }
    private func move(_ days: Int) { visibleWeek = Calendar.current.date(byAdding: .day, value: days, to: visibleWeek)! }
}

private struct DayTimeline: View {
    let agenda: DayAgenda
    let now: Date
    let density: AgendaDensity
    let selected: Bool
    @Binding var scrollMinute: Double?
    let reset: Int
    let select: (CalendarEvent) -> Void
    @State private var heights: [String: Double] = [:]
    private var hourHeight: Double { density.pointsPerHour }
    @State private var position = ScrollPosition()
    @State private var positioned = false
    var body: some View {
        let window = AgendaWindow(agenda: agenda, now: now)
        let layout = ReadableAgendaLayout(window.timed, pointsPerHour: hourHeight, heights: heights)
        VStack(spacing: 0) {
                    if !agenda.allDay.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Ganztägig").font(.subheadline).foregroundStyle(.secondary)
                            ForEach(agenda.allDay) { event in
                                Button { select(event) } label: {
                                    CalendarAgendaRow(event: event, now: now)
                                }.buttonStyle(.bordered).controlHeight()
                                    .accessibilityLabel(event.spoken + " " + event.placeDescription)
                                    .accessibilityIdentifier("agenda-event-\(event.id)")
                            }
                        }.padding(.horizontal)
                    }
            ScrollView {
                TimelineCanvas(window: window, layout: layout, now: now, select: select) { id, height in
                    if abs((heights[id] ?? 0) - height) > 1 { heights[id] = height }
                }.frame(height: layout.height + 52)
                    .padding(.vertical, 12)
            }.accessibilityIdentifier("day-timeline")
                .scrollPosition($position)
                .onScrollGeometryChange(for: Bool.self) { $0.containerSize.height > 0 && $0.contentSize.height > 0 } action: { _, ready in
                    if ready && !positioned {
                        positioned = true
                        if selected && scrollMinute == nil { scrollMinute = window.scrollMinute }
                        position.scrollTo(y: layout.y(scrollMinute ?? window.scrollMinute))
                    }
                }
                .onScrollGeometryChange(for: Double.self) { max(0, Double($0.contentOffset.y + $0.contentInsets.top)) } action: { _, y in
                    if selected && positioned && position.isPositionedByUser { scrollMinute = layout.minute(at: y) }
                }
                .onChange(of: selected) { _, active in
                    if active { position.scrollTo(y: layout.y(scrollMinute ?? window.scrollMinute)) }
                }
                .onChange(of: reset) { position.scrollTo(y: layout.y(window.scrollMinute)) }
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
}

private struct TimelineCanvas: View {
    let window: AgendaWindow
    let layout: ReadableAgendaLayout
    let now: Date
    let select: (CalendarEvent) -> Void
    let measured: (String, Double) -> Void
    var body: some View {
        GeometryReader { geometry in
            let width = max(0, geometry.size.width - 8)
            ZStack(alignment: .topLeading) {
                ForEach(0...Int(window.minutes / 60), id: \.self) { hour in
                    Rectangle().fill(AppPalette.separator).frame(height: 0.5).offset(y: layout.y(Double(hour) * 60) + 8)
                }
                ForEach(layout.items) { item in
                    let columnWidth = width / Double(item.placement.columns)
                    TimelineAppointment(event: item.placement.segment.event, now: now, width: columnWidth - 4, height: item.height,
                        select: select, measured: { measured(item.id, $0) })
                        .offset(x: Double(item.placement.column) * columnWidth, y: item.top + 8)
                }
            }
        }
    }
}
private struct TimelineGutter: View {
    let start: Date
    let layout: ReadableAgendaLayout
    var body: some View {
        ZStack(alignment: .topTrailing) {
            ForEach(0...12, id: \.self) { hour in
                Text(eventTime(start.addingTimeInterval(Double(hour) * 3600)))
                    .font(.caption).monospacedDigit().foregroundStyle(AppPalette.secondaryText)
                    .frame(width: 48, height: 16, alignment: .trailing)
                    .offset(y: layout.y(Double(hour) * 60))
                    .accessibilityIdentifier("timeline-hour-\(hour + 6)")
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(.trailing, 8)
    }
}

private struct TimelineAppointment: View {
    let event: CalendarEvent
    let now: Date
    let width: Double
    let height: Double
    let select: (CalendarEvent) -> Void
    let measured: (Double) -> Void
    var body: some View {
        Button { select(event) } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(event.values.title).font(.subheadline.weight(.semibold))
                Text("\(eventTime(event.values.start))–\(eventTime(event.values.end))")
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                Text(event.placeDescription).font(.caption)
                Text(event.therapistDescription).font(.caption)
            }.foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading)
                .padding(8).frame(width: max(0, width), alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: Double.self) { Double($0.size.height) } action: { measured($0) }
                .frame(height: height, alignment: .topLeading)
                .background(EventCategory.classify(event.values.title).color.opacity(0.12), in: .rect(cornerRadius: 10))
                .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 2).fill(EventCategory.classify(event.values.title).color).frame(width: 3).padding(.vertical, 8) }
                .contentShape(.rect)
        }.buttonStyle(.plain)
            .accessibilityLabel(event.spoken + " " + event.placeDescription + (event.values.end <= now ? " Vorbei." : ""))
            .accessibilityIdentifier("agenda-event-\(event.id)")
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
                Text(event.placeDescription).font(.subheadline)
                Text(event.therapistDescription).font(.subheadline).foregroundStyle(.secondary)
                if !Calendar.current.isDate(event.values.start, inSameDayAs: event.values.end.addingTimeInterval(-1)) {
                    Text(span).font(.subheadline).foregroundStyle(.secondary)
                }
                Text(event.source.isEmpty ? event.calendar_title : "\(event.calendar_title) · \(event.source)")
                    .font(.subheadline).foregroundStyle(.secondary)
                if event.values.end <= now { Text("Vorbei").font(.subheadline).foregroundStyle(.secondary) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(8).background(EventCategory.classify(event.values.title).color.opacity(0.10), in: .rect(cornerRadius: 8))
            .overlay(alignment: .leading) { Capsule().fill(EventCategory.classify(event.values.title).color).frame(width: 3).padding(.vertical, 6) }
            .fixedSize(horizontal: false, vertical: true).foregroundStyle(.primary).contentShape(.rect).accessibilityElement(children: .combine)
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
