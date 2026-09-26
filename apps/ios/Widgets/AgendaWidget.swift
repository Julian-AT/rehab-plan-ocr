import SwiftUI
import WidgetKit

struct AgendaEntry: TimelineEntry {
  let date: Date
  let snapshot: AgendaSnapshot
}
struct AgendaProvider: TimelineProvider {
  func placeholder(in context: Context) -> AgendaEntry {
    AgendaEntry(date: .now, snapshot: .empty())
  }
  func getSnapshot(in context: Context, completion: @escaping (AgendaEntry) -> Void) {
    completion(AgendaEntry(date: .now, snapshot: read()))
  }
  func getTimeline(in context: Context, completion: @escaping (Timeline<AgendaEntry>) -> Void) {
    let snapshot = read()
    let now = Date()
    let entries = snapshot.boundaries(after: now).map { AgendaEntry(date: $0, snapshot: snapshot) }
    completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(3600))))
  }
  private func read() -> AgendaSnapshot {
    AgendaSnapshot.read(
      from: FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: AgendaSnapshot.group))
  }
}
struct AgendaWidgetView: View {
  let entry: AgendaEntry
  @Environment(\.widgetFamily) private var family
  var body: some View { AgendaWidgetContent(entry: entry, family: family) }
}
struct AgendaWidgetContent: View {
  let entry: AgendaEntry
  let family: WidgetFamily
  @Environment(\.dynamicTypeSize) private var typeSize
  var body: some View {
    let state = entry.snapshot.state(at: entry.date)
    let next = entry.snapshot.upcoming(at: entry.date).first
    Group {
      if state == "unavailable" || state == "stale" {
        AgendaEmptyView(state: state)
      } else if family == .systemMedium {
        medium
      } else if let next {
        AgendaEventCard(
          event: next, date: entry.date, compact: family == .accessoryRectangular,
          showRelative: family != .accessoryRectangular)
      } else {
        AgendaEmptyView(state: "empty")
      }
    }
    .containerBackground(.background, for: .widget)
    .widgetURL(state == "available" ? next?.url : URL(string: "reha-calendar://today"))
  }
  private var medium: some View {
    let events = entry.snapshot.today(at: entry.date)
    let count = typeSize.isAccessibilitySize ? 1 : 3
    return VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(
          entry.date.formatted(
            .dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "de_AT")))
        )
        .font(.caption.weight(.medium)).foregroundStyle(.secondary)
        Spacer(minLength: 4)
        if events.count > count {
          Text("+ \(events.count - count) weitere").font(.caption).foregroundStyle(.secondary)
        }
      }
      if events.isEmpty {
        Text("Heute ist alles erledigt.").font(.headline)
        if let next = entry.snapshot.upcoming(at: entry.date).first {
          Text(
            "Nächster Termin: \(next.startDate.formatted(.dateTime.day().month())) · \(AgendaFormat.time(next))"
          )
          .font(.caption).foregroundStyle(.secondary)
        }
      }
      ForEach(Array(events.prefix(count))) { event in
        Link(destination: event.url) {
          HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(AgendaFormat.time(event)).font(.body.weight(.semibold)).monospacedDigit()
            VStack(alignment: .leading, spacing: 0) {
              Text(event.title).font(.subheadline.weight(.medium)).lineLimit(1)
              Text(AgendaFormat.room(event)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if event.isRunning(at: entry.date) { Text("Jetzt").font(.caption) }
          }.accessibilityElement(children: .combine).privacySensitive()
        }.foregroundStyle(.primary)
      }
    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}
#if !AGENDA_TESTING
  @main
#endif
struct RehaAgendaWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: AgendaSnapshot.widgetKind, provider: AgendaProvider()) { entry in
      AgendaWidgetView(entry: entry)
    }
    .configurationDisplayName("Deine Termine")
    .description("Die nächsten Behandlungen mit Uhrzeit und Raum.")
    .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    .disfavoredLocations([.iPhoneWidgetsOnMac], for: [.systemSmall, .systemMedium])
  }
}
