import SwiftUI

enum AppPalette {
  static let tint = Color("AccentColor")
  static let text = Color.primary
  static let secondaryText = Color.secondary
  static let background = Color(uiColor: .systemBackground)
  static let card = Color(uiColor: .secondarySystemGroupedBackground)
  static let separator = Color(uiColor: .separator).opacity(0.4)
  static let warning = Color.orange
  static let destructive = Color.red
  static let action = tint
  static let onAction = Color.black
  @MainActor static func configureControls() {
    let tabs = UITabBarAppearance()
    for item in [
      tabs.stackedLayoutAppearance, tabs.inlineLayoutAppearance, tabs.compactInlineLayoutAppearance,
    ] {
      item.normal.titleTextAttributes = [.foregroundColor: UIColor.label]
      item.selected.titleTextAttributes = [.foregroundColor: UIColor.label]
      item.selected.iconColor = UIColor(red: 0, green: 150.0 / 255, blue: 64.0 / 255, alpha: 1)
    }
    UITabBar.appearance().standardAppearance = tabs
    UITabBar.appearance().scrollEdgeAppearance = tabs
    UIBarButtonItem.appearance().setTitleTextAttributes(
      [.foregroundColor: UIColor.label], for: .normal)
    UIBarButtonItem.appearance().setTitleTextAttributes(
      [.foregroundColor: UIColor.label], for: .highlighted)
  }
}

struct AppAppearance: ViewModifier {
  func body(content: Content) -> some View {
    content.tint(AppPalette.tint).foregroundStyle(.primary).labelStyle(AppLabelStyle())
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
      .background(AppPalette.action, in: .rect(cornerRadius: capsule ? 100 : 14))
      .contentShape(.rect)
      .opacity(enabled ? (configuration.isPressed ? 0.72 : 1) : 0.4)
  }
}
