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
    static let action = Color(uiColor: .label)
    static let onAction = Color(uiColor: .systemBackground)
}

struct AppAppearance: ViewModifier {
    func body(content: Content) -> some View { content.tint(AppPalette.action) }
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
