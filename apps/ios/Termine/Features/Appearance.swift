import SwiftUI

enum AppPalette {
  static let tint = Color("AccentColor")
  static let text = Color.primary
  static let secondaryText = Color(
    uiColor: UIColor { traits in
      UIColor(white: traits.userInterfaceStyle == .dark ? 0.70 : 0.36, alpha: 1)
    })
  static let background = Color(uiColor: .systemBackground)
  static let card = Color(uiColor: .secondarySystemGroupedBackground)
  static let separator = Color(uiColor: .separator).opacity(0.4)
  static let warning = Color.orange
  static let destructive = Color.red
  static let action = tint
  // Fixed dark ink retains contrast on the logo green in either appearance.
  static let onAction = Color(red: 0.02, green: 0.06, blue: 0.03)

  @MainActor static func configureNavigation() {
    let appearance = UITabBarAppearance()
    for item in [
      appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance,
      appearance.compactInlineLayoutAppearance,
    ] {
      item.normal.titleTextAttributes = [.foregroundColor: UIColor.label]
      item.selected.titleTextAttributes = [.foregroundColor: UIColor.label]
      item.selected.iconColor = UIColor(tint)
    }
    UITabBar.appearance().standardAppearance = appearance
    UITabBar.appearance().scrollEdgeAppearance = appearance
  }
}

struct AppAppearance: ViewModifier {
  func body(content: Content) -> some View {
    content.tint(AppPalette.tint).foregroundStyle(AppPalette.text)
  }
}

/// Keep navigation text neutral while giving its symbol the shared accent.
struct AppControlLabelStyle: LabelStyle {
  func makeBody(configuration: Configuration) -> some View {
    Label {
      configuration.title.foregroundStyle(AppPalette.text)
    } icon: {
      configuration.icon.foregroundStyle(AppPalette.tint)
    }
  }
}

/// SwiftUI's native slider keeps a 31-point UIKit hit frame even inside a
/// larger SwiftUI frame. Size the control itself to the 44-point touch target.
struct AppSlider: UIViewRepresentable {
  @Binding var value: Double
  let range: ClosedRange<Double>
  let step: Double
  let label: String

  func makeCoordinator() -> Coordinator { Coordinator(self) }
  func makeUIView(context: Context) -> UISlider {
    let slider = UISlider()
    slider.addTarget(
      context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
    return slider
  }
  func updateUIView(_ slider: UISlider, context: Context) {
    context.coordinator.parent = self
    slider.minimumValue = Float(range.lowerBound)
    slider.maximumValue = Float(range.upperBound)
    slider.value = Float(value)
    slider.minimumTrackTintColor = UIColor(AppPalette.tint)
    slider.accessibilityLabel = label
    slider.accessibilityValue = value.formatted(.number.precision(.fractionLength(2)))
  }
  func sizeThatFits(_ proposal: ProposedViewSize, uiView: UISlider, context: Context) -> CGSize? {
    CGSize(width: proposal.width ?? 320, height: 44)
  }
  final class Coordinator: NSObject {
    var parent: AppSlider
    init(_ parent: AppSlider) { self.parent = parent }
    @objc func changed(_ slider: UISlider) {
      let steps = ((Double(slider.value) - parent.range.lowerBound) / parent.step).rounded()
      let value = min(
        parent.range.upperBound,
        max(parent.range.lowerBound, parent.range.lowerBound + steps * parent.step))
      slider.value = Float(value)
      parent.value = value
    }
  }
}

extension View {
  func controlHeight() -> some View { frame(minHeight: 44) }
  func pageTitle(_ title: String) -> some View {
    navigationTitle(title).navigationBarTitleDisplayMode(.inline)
  }
}

enum AppSpacing {
  static let small: CGFloat = 8
  static let medium: CGFloat = 12
  static let section: CGFloat = 20
  static let generous: CGFloat = 32
}

/// Explicit foreground/background pairing keeps filled actions legible in both
/// appearances. Padding belongs to the label so its complete area is tappable.
struct AppPrimaryButtonStyle: ButtonStyle {
  var capsule = false
  @Environment(\.isEnabled) private var enabled
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .padding(.horizontal, 16).padding(.vertical, 10).frame(minHeight: 44)
      .foregroundStyle(AppPalette.onAction)
      .background(
        configuration.role == .destructive ? AppPalette.destructive : AppPalette.action,
        in: .rect(cornerRadius: capsule ? 100 : 14)
      )
      .contentShape(.rect)
      .opacity(enabled ? (configuration.isPressed ? 0.72 : 1) : 0.4)
  }
}
