import AppKit
import DiscordRP
import SwiftUI

/// The menu bar dropdown.
///
/// Structure is taken from the Open Design spec (`docs/ui/discord-rp-menu-spec.html`,
/// section 5 “Handoff”): one status line, no preset management rows, at most one submenu,
/// maximum 11 rows. Row order, labels, SF Symbols and shortcuts match the handoff table.
struct MenuContentView: View {
    @ObservedObject var model: AppModel

    private var statusText: String { model.multiStatus.shortText }

    var body: some View {
        // 0 — status line (not interactive)
        Label(statusText, systemImage: model.multiStatus.dotSymbolName)

        // E1 — error state only
        if model.multiStatus.needsAttention {
            Button {
                model.openSettings()
            } label: {
                Label("Fix in Settings…", systemImage: "gearshape")
            }
        }

        // 1 — settings
        Button {
            model.openSettings()
        } label: {
            Label("Settings…", systemImage: "gearshape")
        }
        .keyboardShortcut(",", modifiers: .command)

        // 2 — re-send
        Button {
            model.reapply()
        } label: {
            Label("Reapply Now", systemImage: "arrow.clockwise")
        }
        .keyboardShortcut("r", modifiers: .command)
        .disabled(!model.multiStatus.isConnected || !model.hasRunnableCard)

        // 3 — clear
        Button {
            model.clearPresence()
        } label: {
            Label(model.enabledCards.count > 1 ? "Clear All Presences" : "Clear Presence",
                  systemImage: "xmark.circle")
        }
        .disabled(!model.multiStatus.isConnected)

        Divider()

        // 4 — quit
        Button {
            NSApp.terminate(nil)
        } label: {
            Label("Quit Discord RP", systemImage: "power")
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}
