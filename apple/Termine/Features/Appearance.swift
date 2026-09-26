import SwiftUI

enum AppPalette {
    static let tint = Color("AccentColor")
    static let primaryFill = Color(red: 0.15, green: 0.43, blue: 0.48)
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
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.body.weight(.medium))
            .padding(.horizontal, 16).frame(minHeight: height)
            .foregroundStyle(.white)
            .background(AppPalette.primaryFill.opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.35), in: .rect(cornerRadius: 14))
            .contentShape(.rect(cornerRadius: 14))
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
            .font(.footnote).foregroundStyle(.secondary)
    }
}

struct MoreRow: View {
    @Environment(\.actionHeight) private var height
    let title: String
    let icon: String
    var chevron = false
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.body).foregroundStyle(.tint).frame(width: 24)
            Text(title).foregroundStyle(.primary)
            if chevron { Spacer(); Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary) }
        }.frame(minHeight: max(24, height - 12)).contentShape(.rect)
    }
}
