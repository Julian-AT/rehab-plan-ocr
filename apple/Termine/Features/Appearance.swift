import SwiftUI

enum AppPalette {
    static let tint = Color("AccentColor")
    static let primaryFill = Color.primary
}

extension EnvironmentValues {
    @Entry var actionHeight: CGFloat = 44
}

struct AppAppearance: ViewModifier {
    @AppStorage("ui.controls") private var controls = "standard"
    @AppStorage("ui.text") private var text = "system"
    @Environment(\.dynamicTypeSize) private var systemSize
    func body(content: Content) -> some View {
        content
            .tint(AppPalette.tint)
            .font(.body)
            .symbolRenderingMode(.monochrome)
            .listStyle(.plain)
            .environment(\.actionHeight, controls == "large" ? 54 : controls == "extraLarge" ? 64 : 44)
            .dynamicTypeSize(text == "large" ? max(systemSize, .xxxLarge) : text == "extraLarge" ? max(systemSize, .accessibility2) : systemSize)
    }
}
private struct ControlHeight: ViewModifier {
    @Environment(\.actionHeight) private var height
    func body(content: Content) -> some View { content.frame(minHeight: height) }
}
extension View {
    func controlHeight() -> some View { modifier(ControlHeight()) }
}

struct PrimaryActionStyle: ButtonStyle {
    @Environment(\.actionHeight) private var height
    @Environment(\.isEnabled) private var enabled
    @Environment(\.colorScheme) private var scheme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.body.weight(.medium))
            .padding(.horizontal, AppSpacing.section).padding(.vertical, AppSpacing.small).frame(minHeight: height)
            .foregroundStyle(scheme == .dark ? .black : .white)
            .background(AppPalette.primaryFill.opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.35), in: .rect(cornerRadius: 13))
            .contentShape(.rect(cornerRadius: 13))
    }
}

struct AppearanceControls: View {
    @AppStorage("ui.controls") private var controls = "standard"
    @AppStorage("ui.text") private var text = "system"
    var body: some View {
        Picker("Schaltflächen", selection: $controls) {
            Text("Standard").tag("standard")
            Text("Groß").tag("large")
            Text("Sehr groß").tag("extraLarge")
        }.accessibilityIdentifier("control-size")
        Picker("Schriftgröße", selection: $text) {
            Text("Wie auf dem iPhone").tag("system")
            Text("Groß").tag("large")
            Text("Sehr groß").tag("extraLarge")
        }.accessibilityIdentifier("text-size")
        Text("Größen werden sofort übernommen. Die Bedienungshilfen des iPhones bleiben berücksichtigt.")
            .font(.subheadline).foregroundStyle(.secondary)
    }
}

struct MoreRow: View {
    @Environment(\.actionHeight) private var height
    let title: String
    let icon: String
    var chevron = false
    var body: some View {
        HStack(spacing: AppSpacing.medium) {
            Image(systemName: icon).font(.body).foregroundStyle(.tint).frame(width: 24)
            Text(title).foregroundStyle(.primary)
            if chevron { Spacer(); Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).foregroundStyle(.tertiary) }
        }.frame(minHeight: height).contentShape(.rect)
    }
}

/// Shared scale: 17 pt body, 27.5 pt title (17 × 1.618), 15 pt secondary text.
enum AppSpacing {
    static let small: CGFloat = 8
    static let medium: CGFloat = 13
    static let section: CGFloat = 21
    static let generous: CGFloat = 34
}
private struct PageTitle: ViewModifier {
    let title: String
    @ScaledMetric(relativeTo: .title) private var size = 27.5
    func body(content: Content) -> some View {
        content.navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title).font(.system(size: size, weight: .semibold))
                        .lineLimit(1).minimumScaleFactor(0.5)
                        .accessibilityAddTraits(.isHeader)
                }
            }
    }
}
extension View {
    func pageTitle(_ title: String) -> some View { modifier(PageTitle(title: title)) }
}
