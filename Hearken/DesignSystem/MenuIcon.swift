import SwiftUI
import UIKit

// Menu icons in the text color. A context menu tints its icons with the app's accent (set at
// the root), while their titles stay in the text color; every icon in a menu should match its
// title instead. These draw the symbol in the label color as an "original" image, which the
// menu doesn't re-tint (the same way Image.redTrash keeps Delete red). It adapts to Dark Mode.

extension Image {
    /// An SF Symbol for a menu row, in the text color.
    static func menuIcon(_ name: String) -> Image {
        let symbol = UIImage(systemName: name)?.withTintColor(.label, renderingMode: .alwaysOriginal)
        return symbol.map { Image(uiImage: $0) } ?? Image(systemName: name)
    }
}

extension Button where Label == SwiftUI.Label<Text, Image> {
    /// A menu button whose icon is the text color: `Button("Rename", menuIcon: "pencil") { … }`.
    init(_ title: String, menuIcon: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.init(role: role, action: action) {
            SwiftUI.Label { Text(title) } icon: { Image.menuIcon(menuIcon) }
        }
    }
}

extension Menu where Label == SwiftUI.Label<Text, Image> {
    /// A submenu whose icon is the text color.
    init(_ title: String, menuIcon: String, @ViewBuilder content: () -> Content) {
        self.init(content: content) {
            SwiftUI.Label { Text(title) } icon: { Image.menuIcon(menuIcon) }
        }
    }
}
