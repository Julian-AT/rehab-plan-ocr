import SwiftUI

struct AgendaEventCard: View {
  let event: AgendaEvent
  let date: Date
  var compact = false
  var showRelative = true
  @ScaledMetric(relativeTo: .largeTitle) private var clockSize = 40
  var body: some View {
    VStack(alignment: .leading, spacing: compact ? 4 : 12) {
      HStack(alignment: .firstTextBaseline) {
        Text(AgendaFormat.time(event))
          .font(.system(size: compact ? 22 : clockSize, weight: .semibold, design: .rounded))
          .monospacedDigit().minimumScaleFactor(0.75)
        Spacer(minLength: 4)
        if event.isRunning(at: date) {
          Text("Jetzt").font(.caption.weight(.semibold))
        }
      }
      Text(event.title).font(compact ? .subheadline.weight(.semibold) : .headline)
        .lineLimit(compact ? 1 : 2).fixedSize(horizontal: false, vertical: true)
      Text(AgendaFormat.room(event)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
      if showRelative && event.startDate > date {
        HStack(spacing: 4) {
          Text("In")
          Text(event.startDate, style: .relative)
        }.font(.caption).foregroundStyle(.secondary).lineLimit(1)
      }
    }.frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityElement(children: .combine)
      .privacySensitive()
  }
}

struct AgendaEmptyView: View {
  let state: String
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Image(systemName: state == "unavailable" ? "calendar.badge.exclamationmark" : "calendar")
        .font(.title2).accessibilityHidden(true)
      Text(
        state == "unavailable"
          ? "App öffnen" : state == "stale" ? "Bitte aktualisieren" : "Zeit zum Erholen"
      )
      .font(.headline)
      Text(
        state == "unavailable"
          ? "Kalenderzugriff prüfen."
          : state == "stale" ? "Termine in der App abgleichen." : "Keine kommenden Termine."
      )
      .font(.caption).foregroundStyle(.secondary)
    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
  }
}
