import AppKit
import DiscordRP
import SwiftUI

/// The menu bar glyph: the designed mark when it is bundled, else the SF Symbol fallback.
///
/// The PNG pair shipped in `Contents/Resources` (`MenuBarIcon.png` 22 pt, `MenuBarIcon@2x.png`
/// 44 px) is a **template image** — pure alpha — so macOS recolours it for a light bar, a dark
/// bar and the selected state. `isTemplate` must be set on a copy: mutating the cached image
/// would affect every other user of it.
enum MenuBarIcon {
    static let template: NSImage? = {
        guard let image = Bundle.main.image(forResource: NSImage.Name("MenuBarIcon")),
              let copy = image.copy() as? NSImage
        else { return nil }
        copy.isTemplate = true
        copy.size = NSSize(width: 22, height: 22)
        return copy
    }()
}

struct MenuBarGlyph: View {
    let status: MultiPresenceStatus

    var body: some View {
        ZStack {
            if let icon = MenuBarIcon.template {
                Image(nsImage: icon)
                    .opacity(status.isConnected ? 1 : 0.55)
            } else {
                Image(systemName: status.symbolName)
                    .symbolRenderingMode(.hierarchical)
                    .opacity(status.isConnected ? 1 : 0.55)
            }
            if status.needsAttention {
                Circle()
                    .fill(Color.red)
                    .frame(width: 6, height: 6)
                    .offset(x: 5, y: 5)
            }
        }
    }
}
