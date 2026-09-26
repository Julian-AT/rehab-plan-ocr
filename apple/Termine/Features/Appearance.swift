import SwiftUI

enum AppPalette {
    static let tint = Color("AccentColor")
}

struct AppAppearance: ViewModifier {
    func body(content: Content) -> some View { content.tint(AppPalette.tint) }
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
