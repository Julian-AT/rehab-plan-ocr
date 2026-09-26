import SwiftUI

/// A separate 44-point control; never placed inside a Toggle's label.
struct ContextHelp: View {
  let title: String
  let explanation: String
  @State private var presented = false
  @Environment(\.dynamicTypeSize) private var typeSize
  init(_ title: String, _ explanation: String) {
    self.title = title
    self.explanation = explanation
  }
  var body: some View {
    Button {
      presented = true
    } label: {
      Image(systemName: "info.circle").foregroundStyle(AppPalette.tint)
        .frame(width: 44, height: 44).contentShape(.rect)
    }.buttonStyle(.plain).accessibilityLabel("Info: " + title)
      .popover(isPresented: $presented) {
        ScrollView {
          VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.headline)
            Text(explanation).font(.body).fontWeight(.regular)
              .fixedSize(horizontal: false, vertical: true)
            Button("Fertig") { presented = false }.font(.body).fontWeight(.regular)
              .frame(minHeight: 44)
          }.foregroundStyle(.primary).padding(24)
        }
        .frame(idealWidth: 320, idealHeight: 260)
        .presentationCompactAdaptation(typeSize.isAccessibilitySize ? .sheet : .popover)
        .presentationDetents([.medium, .large])
      }
  }
}

struct AppLabelStyle: LabelStyle {
  func makeBody(configuration: Configuration) -> some View {
    Label {
      configuration.title.foregroundStyle(.primary)
    } icon: {
      configuration.icon.foregroundStyle(AppPalette.tint)
    }
  }
}
