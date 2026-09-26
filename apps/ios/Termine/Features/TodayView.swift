import AppleServices
import EventKit
import RehaCore
import SwiftUI

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
    _selection = selection
    self.step = step
    self.content = content
    _center = State(initialValue: selection.wrappedValue)
    _position = State(initialValue: selection.wrappedValue)
  }
  private var dates: [Date] {
    (-14...14).map { Calendar.current.date(byAdding: .day, value: $0 * step, to: center)! }
  }
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
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
          center = selection
          position = selection
        }
      }
    }
  }
}

struct TodayView: View {
  let core: NativeApplication
  let scanner: ScanModel
  let refreshID: Int
  @SwiftUI.AppStorage("agenda.density") private var density = AgendaDensity.standard.rawValue
  @SwiftUI.AppStorage("agenda.list") private var listView = false
  @State private var model = TodayModel(describe: userMessage)
  @State private var visibleWeek = AgendaWeek(containing: .now).start
  @State private var scrollMinute: Double?
  @State private var scrollReset = 0
  @State private var selectedDate = Calendar.current.startOfDay(for: .now)
  @State private var observedToday = Calendar.current.startOfDay(for: .now)
  @State private var setup = false
  @State private var calendarStatus = false
  @State private var editor: CalendarEvent?
  @State private var create = false
  @State private var showPast = false
  @State private var reloadID = 0
  @Environment(PreferencesStore.self) private var preferences
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.openURL) private var openURL
  @Environment(\.dynamicTypeSize) private var typeSize
  init(core: NativeApplication, scanner: ScanModel, refreshID: Int) {
    self.core = core
    self.scanner = scanner
    self.refreshID = refreshID
  }
  private var week: AgendaWeek { AgendaWeek(containing: selectedDate) }
  private var requestID: String {
    "\(week.start)-\(visibleWeek)-\(refreshID)-\(reloadID)-\(scanner.isReady)"
  }

  var body: some View {
    VStack(spacing: 0) {
      WeekSelector(selection: $selectedDate, visibleWeek: $visibleWeek)
      Divider()
      if !model.unavailableCalendars.isEmpty {
        HStack {
          Text("Kalenderdaten unvollständig").font(.footnote)
          Spacer()
          Button {
            calendarStatus = true
          } label: {
            Text("Status prüfen").controlHeight()
          }
        }.padding(.horizontal).foregroundStyle(AppPalette.text)
      }
      if model.error != nil && model.events(on: selectedDate) != nil {
        HStack {
          Text("Aktualisierung fehlgeschlagen").font(.footnote)
          Spacer()
          Button(action: reload) {
            Image(systemName: "arrow.clockwise").controlHeight()
          }.accessibilityLabel("Kalender erneut aktualisieren")
        }.padding(.horizontal).foregroundStyle(AppPalette.secondaryText)
      }
      TimelineView(.periodic(from: .now, by: 15)) { context in
        sharedTimeline(now: AgendaPreviewClock.now(context.date))
      }.onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
        followToday(Calendar.current.startOfDay(for: .now))
      }

    }
    .contentShape(.rect)
    .accessibilityAction(named: "Nächster Tag") {
      selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate)!
    }
    .accessibilityAction(named: "Vorheriger Tag") {
      selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate)!
    }
    .background(Color(uiColor: .systemBackground))
    .pageTitle("Termine")
    .toolbar {
      ToolbarItem(placement: .topBarLeading) {
        Button("Heute") {
          selectedDate = Calendar.current.startOfDay(for: .now)
          visibleWeek = week.start
          showPast = false
          scrollMinute = nil
          scrollReset += 1
          reload()
        }
        .accessibilityIdentifier("agenda-today")
        #if DEBUG && targetEnvironment(simulator)
          .accessibilityValue(
            ProcessInfo.processInfo.arguments.contains("--preview-agenda-delay")
              ? (model.isRefreshing ? "refreshing" : "settled") : "")
        #endif
      }
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          CaptureActions(scanner: scanner, context: "plan-menu")
          Divider()
          Button("Termin hinzufügen", systemImage: "calendar.badge.plus") { create = true }
        } label: {
          Label("Plan hinzufügen", systemImage: "plus")
        }
        .accessibilityIdentifier("add-plan")
      }
    }
    .refreshable { reload() }
    .task(id: requestID) { await load() }
    .onChange(of: preferences.value.map { Set($0.displayCalendarIds) }) { _, _ in
      model.invalidate()
      reload()
    }
    .onChange(of: scanner.isErasing) { _, erasing in
      if erasing { model.invalidate() }
    }
    .onChange(of: scanner.erasedID) { _, _ in
      model.invalidate()
      reload()
    }
    .onChange(of: selectedDate) {
      showPast = false
      visibleWeek = week.start
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active {
        followToday(Calendar.current.startOfDay(for: .now))
        reload()
      }
    }
    .onReceive(
      NotificationCenter.default.publisher(for: .EKEventStoreChanged).debounce(
        for: .milliseconds(500), scheduler: RunLoop.main)
    ) { _ in reload() }
    .onReceive(
      NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)
    ) { _ in
      followToday(Calendar.current.startOfDay(for: .now))
      reload()
    }
    .navigationDestination(isPresented: $setup) { CalendarPreferencesView(core: core) }
    .navigationDestination(isPresented: $calendarStatus) {
      CalendarStatusView(core: core, changed: reload)
    }
    .sheet(item: $editor, onDismiss: reload) { event in
      EventEditorView(core: core, original: event, changed: reload)
    }
    .sheet(isPresented: $create, onDismiss: reload) { EventEditorView(core: core, changed: reload) }
  }
  private func usesList(_ agenda: DayAgenda, layout: AgendaTimelineLayout) -> Bool {
    let crowded = layout.requiresList
    let onlyOutside = !agenda.events.isEmpty && layout.items.isEmpty
    return typeSize.isAccessibilitySize || listView || crowded || onlyOutside
  }
  @ViewBuilder private func day(_ agenda: DayAgenda, now: Date) -> some View {
    Group {
      if model.events(on: agenda.date) == nil {
        if model.availability == .ready { loading } else { unavailable }
      } else if agenda.events.isEmpty {
        ContentUnavailableView {
          Label(
            !model.unavailableCalendars.isEmpty
              ? "Keine lesbaren Termine"
              : Calendar.current.isDateInToday(agenda.date)
                ? "Heute keine Termine" : "Keine Termine",
            systemImage: "calendar")
        } description: {
          Text(
            model.unavailableCalendars.isEmpty
              ? "Für diesen Tag sind keine Termine eingetragen."
              : "Ein Teil der Kalenderdaten ist nicht verfügbar. Kalenderstatus prüfen."
          )
          .foregroundStyle(AppPalette.secondaryText)
        }
      } else if agenda.isComplete && !showPast {
        ContentUnavailableView {
          Label("Zeit zum Erholen", systemImage: "leaf")
        } description: {
          Text("Für heute stehen keine weiteren Termine an.").foregroundStyle(
            AppPalette.secondaryText)
        } actions: {
          Button("Vergangene Termine anzeigen") { showPast = true }.accessibilityIdentifier(
            "past-events")
        }
      } else {
        List {
          ForEach(agenda.events) { event in
            Button {
              editor = event
            } label: {
              CalendarAgendaRow(event: event, now: now)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("agenda-event-\(event.id)")
          }
        }.accessibilityIdentifier("agenda-accessible-list")

      }
    }
  }
  private func sharedTimeline(now: Date) -> some View {
    let dates = (-1...1).map { Calendar.current.date(byAdding: .day, value: $0, to: selectedDate)! }
    let agendas = dates.map { DayAgenda(events: model.events(on: $0) ?? [], date: $0, now: now) }
    let windows = agendas.map { AgendaWindow(agenda: $0, now: now) }
    let density = AgendaDensity(rawValue: density) ?? .standard
    let projection = AgendaTimeScale(pointsPerHour: density.pointsPerHour)
    let layouts = windows.map { AgendaTimelineLayout($0.timed, scale: projection) }
    let selected = agendas[1]
    let visible =
      !usesList(selected, layout: layouts[1]) && !windows[1].timed.isEmpty
      && !(selected.isComplete && !showPast)
      && model.events(on: selectedDate) != nil
    return VStack(spacing: 0) {
      if !usesList(selected, layout: layouts[1]) && !selected.allDay.isEmpty {
        DisclosureGroup("Ganztägig · \(selected.allDay.count)") {
          ForEach(selected.allDay) { event in
            Button {
              editor = event
            } label: {
              CalendarAgendaRow(event: event, now: now)
            }.buttonStyle(.plain).accessibilityIdentifier("agenda-event-\(event.id)")
          }
        }.padding(.horizontal)
      }
      AgendaScrollView(
        date: selectedDate, projection: projection,
        pages: { viewport, offset in
          zip(zip(agendas, windows), layouts).map { pair, layout in
            let (agenda, window) = pair
            if usesList(agenda, layout: layout) || agenda.events.isEmpty
              || (agenda.isComplete && !showPast)
              || model.events(on: agenda.date) == nil
            {
              return AnyView(day(agenda, now: now).frame(height: viewport).offset(y: offset))
            }
            return AnyView(
              HStack(alignment: .top, spacing: 0) {
                TimelineGutter(start: window.start, scale: projection).frame(width: 56)
                TimelineCanvas(
                  window: window, scale: projection, layout: layout, now: now,
                  select: { editor = $0 })
              })
          }
        },
        showsTimeline: visible, dataReady: model.events(on: selectedDate) != nil,
        initialMinute: windows[1].scrollMinute, reset: scrollReset,
        minute: $scrollMinute, selectDate: { selectedDate = $0 })
      if !usesList(selected, layout: layouts[1]) && !windows[1].outside.isEmpty {
        DisclosureGroup("Außerhalb von 06:00–18:00") {
          ScrollView {
            ForEach(windows[1].outside) { event in
              Button {
                editor = event
              } label: {
                CalendarAgendaRow(event: event, now: now)
              }.buttonStyle(.plain).accessibilityIdentifier("agenda-event-\(event.id)")
            }
          }.frame(maxHeight: 200)
        }.padding().accessibilityIdentifier("agenda-outside-hours")
      }
    }
  }
  private func load() async {
    guard scanner.isReady else { return }
    _ = await preferences.flush()
    guard scanner.isReady, !Task.isCancelled else { return }
    await model.refresh(
      using: NativeAgendaSource(core: core), week: week, visibleWeek: visibleWeek,
      key: "\(refreshID)-\(reloadID)-\(Calendar.current.timeZone.identifier)")
  }
  private func reload() { reloadID += 1 }
  private func followToday(_ today: Date) {
    if selectedDate == observedToday { selectedDate = today }
    observedToday = today
  }
  private var loading: some View {
    ProgressView("Kalender laden …")
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .accessibilityIdentifier("agenda-loading")
  }
  @ViewBuilder private var unavailable: some View {
    switch model.availability {
    case .loading: loading
    case .noAccess:
      ContentUnavailableView {
        Label("Kalenderzugriff fehlt", systemImage: "calendar.badge.exclamationmark")
      } description: {
        Text("Kalenderzugriff erlauben, um Termine anzuzeigen.").foregroundStyle(
          AppPalette.secondaryText)
      } actions: {
        if EKEventStore.authorizationStatus(for: .event) == .notDetermined {
          Button("Kalenderzugriff erlauben") { setup = true }
        } else {
          Button("Einstellungen öffnen") {
            openURL(URL(string: UIApplication.openSettingsURLString)!)
          }
        }
      }
    case .noSelection:
      ContentUnavailableView {
        Label("Kalender auswählen", systemImage: "calendar")
      } description: {
        Text("Kalender für die Terminansicht auswählen.").foregroundStyle(AppPalette.secondaryText)
      } actions: {
        Button("Kalender auswählen") { setup = true }
      }
    case .failed:
      ContentUnavailableView {
        Label("Kalender nicht verfügbar", systemImage: "exclamationmark.circle")
      } description: {
        Text(model.error ?? "Bitte erneut versuchen.").foregroundStyle(AppPalette.secondaryText)
      } actions: {
        Button("Erneut versuchen", action: reload)
        Button("Kalender prüfen") { setup = true }
      }
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
        Button {
          move(-7)
        } label: {
          Image(systemName: "chevron.left").foregroundStyle(AppPalette.tint)
            .frame(width: 44, height: 44).contentShape(.rect)
        }
        .accessibilityLabel("Vorherige Woche").accessibilityIdentifier("previous-week")
        Spacer()
        Text(visibleWeek.formatted(.dateTime.month(.wide).year())).font(.headline)
        Spacer()
        Button {
          move(7)
        } label: {
          Image(systemName: "chevron.right").foregroundStyle(AppPalette.tint)
            .frame(width: 44, height: 44).contentShape(.rect)
        }
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
              Button {
                selection = date
              } label: {
                VStack(spacing: 6) {
                  Text(date.formatted(.dateTime.weekday(.abbreviated))).font(.caption)
                    .foregroundStyle(AppPalette.secondaryText)
                  Text(date.formatted(.dateTime.day())).font(.body)
                    .frame(width: 40, height: 40)
                    .foregroundStyle(selected ? .white : AppPalette.text)
                    .background(selected ? AppPalette.tint : .clear, in: .circle)
                }.frame(maxWidth: .infinity).padding(.vertical, 4).contentShape(.rect)
              }.buttonStyle(.plain)
                .accessibilityLabel(date.formatted(.dateTime.weekday(.wide).day().month().year()))
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier(
                  "weekday-\(Calendar.current.component(.weekday, from: date))")
            }
          }
        }.frame(height: 78)
      }
    }.padding(.horizontal).padding(.vertical, 6)
      .contentShape(.rect)
      .accessibilityElement(children: .contain).accessibilityIdentifier("agenda-week")
  }
  private func move(_ days: Int) {
    visibleWeek = Calendar.current.date(byAdding: .day, value: days, to: visibleWeek)!
  }
}

private struct TimelineCanvas: View {
  let window: AgendaWindow
  let scale: AgendaTimeScale
  let layout: AgendaTimelineLayout
  let now: Date
  let select: (CalendarEvent) -> Void
  var body: some View {
    GeometryReader { geometry in
      let width = max(0, geometry.size.width - 8)
      ZStack(alignment: .topLeading) {
        ForEach(0...Int(window.minutes / 60), id: \.self) { hour in
          Rectangle().fill(AppPalette.separator).frame(height: 0.5).offset(
            y: scale.y(Double(hour) * 60) + 8)
        }
        ForEach(layout.items) { item in
          let columnWidth = width / Double(item.placement.columns)
          TimelineAppointment(
            event: item.placement.segment.event, now: now, width: columnWidth - 4,
            height: item.height,
            select: select
          )
          .offset(x: Double(item.placement.column) * columnWidth, y: item.top + 8)
        }
      }
    }
  }
}
private struct TimelineGutter: View {
  let start: Date
  let scale: AgendaTimeScale
  var body: some View {
    ZStack(alignment: .topTrailing) {
      ForEach(0...12, id: \.self) { hour in
        Text(eventTime(start.addingTimeInterval(Double(hour) * 3600)))
          .font(.caption).monospacedDigit().foregroundStyle(AppPalette.secondaryText)
          .frame(width: 48, height: 16, alignment: .trailing)
          .offset(y: scale.y(Double(hour) * 60))
          .accessibilityIdentifier("timeline-hour-\(hour + 6)")
      }
    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(
      .trailing, 8)
  }
}

private struct TimelineAppointment: View {
  let event: CalendarEvent
  let now: Date
  let width: Double
  let height: Double
  let select: (CalendarEvent) -> Void
  private var room: String? {
    let location = event.values.location.trimmingCharacters(in: .whitespacesAndNewlines)
    return location.isEmpty ? event.note(["Raum"]) : location
  }
  var body: some View {
    Button {
      select(event)
    } label: {
      ViewThatFits(in: .vertical) {
        appointmentLabel(details: 2, titleLines: 2)
        appointmentLabel(details: 1, titleLines: 2)
        appointmentLabel(details: 0, titleLines: 2)
        appointmentLabel(details: 0, titleLines: 1)
        // Large standard text can outgrow a 44-point short card: keep both
        // title and time on one line. Accessibility sizes use the day list.
        HStack(spacing: 4) {
          Text(event.values.title).font(.subheadline.weight(.semibold)).lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
          time.font(.caption2).fixedSize()
        }
      }
      .foregroundStyle(.primary)
      .padding(.horizontal, 8).padding(.vertical, 4)
      .frame(width: max(0, width), height: height, alignment: .topLeading)
      .clipped()
      .background(EventCategory.classify(event.values.title).surface, in: .rect(cornerRadius: 10))
      .overlay(alignment: .leading) {
        RoundedRectangle(cornerRadius: 2).fill(EventCategory.classify(event.values.title).color)
          .frame(width: 3).padding(.vertical, 8)
      }
      .contentShape(.rect)
    }.buttonStyle(.plain)
      .accessibilityLabel(
        event.spoken + " " + event.placeDescription + (event.values.end <= now ? " Vorbei." : "")
      )
      .accessibilityHint("Öffnet alle Terminangaben.")
      .accessibilityIdentifier("agenda-event-\(event.id)")
  }
  private var time: some View {
    Text("\(eventTime(event.values.start))–\(eventTime(event.values.end))")
      .monospacedDigit().foregroundStyle(AppPalette.secondaryText).lineLimit(1)
  }
  private func appointmentLabel(details: Int, titleLines: Int) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(event.values.title).font(.subheadline.weight(.semibold)).lineLimit(titleLines)
      time.font(.caption)
      if let room, details > 0 {
        Text(room).font(.caption).foregroundStyle(AppPalette.secondaryText).lineLimit(1)
      }
      if let therapist = event.therapist, details > (room == nil ? 0 : 1) {
        Text(therapist).font(.caption).foregroundStyle(AppPalette.secondaryText).lineLimit(1)
      }
    }
    .frame(width: max(0, width - 16), alignment: .leading)
    .fixedSize(horizontal: false, vertical: true)
  }

}

struct CalendarAgendaRow: View {
  let event: CalendarEvent
  let now: Date
  var marker: String? = nil
  @ScaledMetric(relativeTo: .body) private var timeWidth = 76
  @Environment(\.dynamicTypeSize) private var typeSize
  var body: some View {
    let layout =
      typeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: AppSpacing.small))
      : AnyLayout(HStackLayout(alignment: .top, spacing: AppSpacing.section))
    layout {
      VStack(alignment: .leading, spacing: AppSpacing.small) {
        if event.isAllDay {
          Text("Ganztägig").font(.subheadline)
        } else {
          Text(eventTime(event.values.start)).font(.body.weight(.semibold)).monospacedDigit()
          Text(eventTime(event.values.end)).font(.subheadline).monospacedDigit().foregroundStyle(
            .secondary)
        }
      }.frame(width: timeWidth, alignment: .leading)
      VStack(alignment: .leading, spacing: AppSpacing.small) {
        if let marker { Text(marker).font(.subheadline.weight(.semibold)) }
        Text(event.values.title).font(.body.weight(.medium))
        Text(event.placeDescription).font(.subheadline)
        Text(event.therapistDescription).font(.subheadline).foregroundStyle(
          AppPalette.secondaryText)
        if !Calendar.current.isDate(
          event.values.start, inSameDayAs: event.values.end.addingTimeInterval(-1))
        {
          Text(span).font(.subheadline).foregroundStyle(AppPalette.secondaryText)
        }
        Text(
          event.source.isEmpty ? event.calendar_title : "\(event.calendar_title) · \(event.source)"
        )
        .font(.subheadline).foregroundStyle(AppPalette.secondaryText)
        if event.values.end <= now {
          Text("Vorbei").font(.subheadline).foregroundStyle(AppPalette.secondaryText)
        }
      }.frame(maxWidth: .infinity, alignment: .leading)
    }.padding(8).background(
      EventCategory.classify(event.values.title).surface, in: .rect(cornerRadius: 8)
    )
    .overlay(alignment: .leading) {
      Capsule().fill(EventCategory.classify(event.values.title).color).frame(width: 3).padding(
        .vertical, 6)
    }
    .fixedSize(horizontal: false, vertical: true).foregroundStyle(.primary).contentShape(.rect)
    .accessibilityElement(children: .combine)
  }
  private var span: String {
    let start = event.values.start.formatted(.dateTime.day().month(.abbreviated))
    let end = (event.isAllDay ? event.values.end.addingTimeInterval(-1) : event.values.end)
      .formatted(.dateTime.day().month(.abbreviated))
    return "\(start) – \(end)"
  }
}
struct ProcessingRow: View {
  let text: String
  var body: some View {
    HStack(spacing: AppSpacing.medium) {
      ProgressView().accessibilityHidden(true)
      Text(text).foregroundStyle(AppPalette.secondaryText).fixedSize(
        horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, AppSpacing.small)
    .accessibilityElement(children: .combine).accessibilityLabel(text)
  }
}
