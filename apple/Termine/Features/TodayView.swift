import SwiftUI
import RehaCore
import AppleServices
import EventKit

@MainActor @Observable final class TodayModel {
    var events: [CalendarEvent] = []
    var loaded = false
    var error: String?
    private var revision = 0
    func refresh(_ core: NativeApplication) async {
        revision += 1; let request = revision
        struct Response: Decodable { let events: [CalendarEvent] }
        do {
            let history = try await core.history(); let preferences = try await core.preferences()
            _ = try await NativeBridge.request("agenda", ["records": history.imports.map(NativeBridge.record), "preferences": NativeBridge.preferences(preferences)])
            let start = Calendar.current.startOfDay(for: .now)
            let end = Calendar.current.date(byAdding: .day, value: 90, to: start)!
            let iso = ISO8601DateFormatter()
            let result = try await core.eventRequest("queryCalendarEvents", ["start_utc": iso.string(from: start), "end_utc": iso.string(from: end)], as: Response.self)
            guard request == revision else { return }
            events = result.events.sorted { $0.values.start < $1.values.start }; error = nil; loaded = true
        } catch { guard request == revision else { return }; self.error = userMessage(error); events = []; loaded = true }
    }
}
struct TodayView: View {
    let core: NativeApplication
    let scanner: ScanModel
    let refreshID: Int
    @State private var model = TodayModel()
    @State private var setup = false
    @State private var voice = false
    @State private var editor: CalendarEvent?
    @State private var create = false
    @State private var showPast = false
    @State private var visibleDays = 0
    @Environment(\.scenePhase) private var scenePhase
    private var futureDays: [Date] {
        Array(Set(model.events.filter { !Calendar.current.isDateInToday($0.values.start) }.map { Calendar.current.startOfDay(for: $0.values.start) })).sorted()
    }
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    if let error = model.error {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Kalender nicht verfügbar", systemImage: "exclamationmark.circle").font(.headline)
                            Text(error).foregroundStyle(.secondary)
                            Button("Kalender prüfen") { setup = true }
                            Button("Erneut versuchen") { Task { await model.refresh(core) } }
                        }.agendaCard()
                    } else if !model.loaded { ProcessingRow(text: "Kalender laden …") }
                    else { agenda(now: context.date) }
                }.padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 24)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Termine")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    CaptureActions(scanner: scanner, context: "plan-menu")
                    Divider()
                    Button("Termin hinzufügen", systemImage: "calendar.badge.plus") { create = true }
                } label: { Image(systemName: "plus").accessibilityLabel("Plan hinzufügen") }
                    .accessibilityIdentifier("add-plan")
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button { voice = true } label: { Label("Sprechen", systemImage: "waveform").font(.body.weight(.medium)).padding(.horizontal, 18).controlHeight() }
                    .buttonStyle(PrimaryActionStyle()).buttonBorderShape(.capsule).accessibilityIdentifier("speak")
                Spacer()
                Button { setup = true } label: { Image(systemName: "calendar.badge.checkmark").frame(width: 44, height: 44) }
                    .accessibilityLabel("Kalender auswählen").buttonStyle(.plain).foregroundStyle(.secondary)
            }.padding(.horizontal, 20).padding(.vertical, 8).background(.bar)
        }
        .refreshable { await model.refresh(core) }
        .task(id: refreshID) { await model.refresh(core) }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await model.refresh(core) } } else { SpeechOutput.shared.stop() } }
        .sheet(isPresented: $setup, onDismiss: reload) { NavigationStack { CalendarPreferencesView(core: core) } }
        .sheet(item: $editor, onDismiss: reload) { event in EventEditorView(core: core, original: event, changed: reload) }
        .sheet(isPresented: $create, onDismiss: reload) { EventEditorView(core: core, changed: reload) }
        .sheet(isPresented: $voice, onDismiss: reload) { VoiceView(core: core) }
    }
    private func reload() { Task { await model.refresh(core) } }
    @ViewBuilder private func agenda(now: Date) -> some View {
        let today = model.events.filter { Calendar.current.isDateInToday($0.values.start) }
        let next = model.events.first { $0.values.end > now }
        let upcoming = today.filter { $0.values.end > now && $0.id != next?.id }
        let past = today.filter { $0.values.end <= now }
        VStack(alignment: .leading, spacing: 5) {
            Text(now.formatted(.dateTime.weekday(.wide).day().month(.wide))).font(.subheadline).foregroundStyle(.secondary)
            Text(today.isEmpty ? "Heute keine Termine" : "\(today.count) \(today.count == 1 ? "Termin" : "Termine") heute")
                .font(.title2.weight(.semibold)).accessibilityIdentifier("today-summary")
        }
        if let next {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label(next.values.start <= now ? "Jetzt" : "Als Nächstes", systemImage: next.values.start <= now ? "circle.inset.filled" : "arrow.up.right")
                        .font(.subheadline.weight(.medium)).foregroundStyle(.tint)
                    Spacer()
                    if !Calendar.current.isDateInToday(next.values.start) { Text(next.values.start.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))).font(.footnote).foregroundStyle(.secondary) }
                }
                Button { editor = next } label: { CalendarAgendaRow(event: next, now: now, featured: true) }.buttonStyle(.plain)
                Divider()
                SpeechControls(text: next.spoken)
            }.agendaCard().accessibilityIdentifier("next-event")
        }
        if !upcoming.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Danach heute").font(.headline)
                eventRows(upcoming, now: now)
            }
        }
        if !past.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showPast.toggle() }
                } label: {
                    HStack {
                        Label("Bereits vorbei · \(past.count)", systemImage: "checkmark.circle")
                        Spacer()
                        Image(systemName: showPast ? "chevron.up" : "chevron.down").font(.footnote)
                    }.font(.subheadline.weight(.medium)).foregroundStyle(.secondary).controlHeight().contentShape(.rect)
                }.buttonStyle(.plain).accessibilityIdentifier("past-events")
                if showPast { eventRows(past, now: now) }
            }
        }
        ForEach(Array(futureDays.prefix(visibleDays)), id: \.self) { day in
            let events = model.events.filter { Calendar.current.isDate($0.values.start, inSameDayAs: day) && $0.id != next?.id }
            VStack(alignment: .leading, spacing: 12) {
                Text(day.formatted(.dateTime.weekday(.wide).day().month(.wide))).font(.headline)
                if events.isEmpty { Text("Der nächste Termin steht oben.").font(.subheadline).foregroundStyle(.secondary) }
                else { eventRows(events, now: now) }
            }.accessibilityElement(children: .contain).accessibilityIdentifier("agenda-day-\(Int(day.timeIntervalSince1970))")
        }
        if visibleDays < futureDays.count {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { visibleDays += 3 }
            } label: {
                HStack {
                    Text("Weitere Tage anzeigen")
                    Spacer()
                    Image(systemName: "chevron.down").font(.footnote)
                }.font(.subheadline.weight(.medium)).controlHeight().contentShape(.rect)
            }.buttonStyle(.plain).accessibilityIdentifier("load-more-days")
        }
        if model.events.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                Text("Füge deinen ersten Plan hinzu.").font(.headline)
                CaptureActions(scanner: scanner, context: "empty-agenda")
            }.buttonStyle(.borderless).agendaCard()
        }
    }
    private func eventRows(_ events: [CalendarEvent], now: Date) -> some View {
        VStack(spacing: 0) {
            ForEach(events) { event in
                Button { editor = event } label: { CalendarAgendaRow(event: event, now: now).padding(.vertical, 14) }.buttonStyle(.plain)
                if event.id != events.last?.id { Divider() }
            }
        }.padding(.horizontal, 16).background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 18))
    }
}
private extension View {
    func agendaCard() -> some View { padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 20)) }
}
struct CalendarAgendaRow: View {
    let event: CalendarEvent
    let now: Date
    var featured = false
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
        layout {
            VStack(alignment: .leading, spacing: 3) {
                Text(event.values.start.formatted(date: .omitted, time: .shortened)).font(featured ? .title2.weight(.semibold) : .body.weight(.semibold)).monospacedDigit()
                Text(event.values.end.formatted(date: .omitted, time: .shortened)).font(.footnote).monospacedDigit().foregroundStyle(.secondary)
            }.frame(minWidth: 54, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                Text(event.values.title).font(featured ? .title3.weight(.semibold) : .body.weight(.medium))
                if !event.values.location.isEmpty { Label(event.values.location, systemImage: "mappin").font(.subheadline).foregroundStyle(.secondary) }
                Text(event.source.isEmpty ? event.calendar_title : "\(event.calendar_title) · \(event.source)").font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if event.values.end <= now { Image(systemName: "checkmark").font(.caption).foregroundStyle(.secondary).accessibilityLabel("Vorbei") }
        }.fixedSize(horizontal: false, vertical: true).foregroundStyle(event.values.end <= now ? .secondary : .primary).contentShape(.rect).accessibilityElement(children: .combine)
    }
}
struct ProcessingRow: View {
    let text: String
    var body: some View {
        HStack(spacing: 12) { ProgressView().accessibilityHidden(true); Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
            .accessibilityElement(children: .combine).accessibilityLabel(text)
    }
}
