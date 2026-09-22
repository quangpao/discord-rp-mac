import AppKit
import DiscordRP
import SwiftUI

/// The menu bar dropdown.
///
/// Structure is taken from the Open Design spec (`docs/ui/discord-rp-menu-spec.html`,
/// section 5 “Handoff”): one status line, presets in exactly one submenu, maximum 11 rows,
/// no other nesting. Row order, labels, SF Symbols and shortcuts match the handoff table, except the
/// update row (8): it was added after that handoff, and it stays one row plus at most one result row.
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

        // 1 — Presets (the only submenu)
        Menu {
            if model.presets.isEmpty {
                Text("No presets yet")
            } else {
                ForEach(model.presets) { preset in
                    Button {
                        model.select(preset)
                    } label: {
                        Text((preset.id == model.settings.activePresetID ? "✓ " : "   ") + preset.name)
                    }
                }
            }
            Divider()
            Button {
                model.duplicateActivePreset()
            } label: {
                Label("Save current as new preset…", systemImage: "plus.circle")
            }
            .disabled(model.presets.isEmpty)
            // Cards only appear once there is more than one: a single-card user's menu stays exactly
            // as it has always been.
            if model.settings.cards.count > 1 {
                Divider()
                ForEach(model.settings.cards) { card in
                    Button {
                        model.toggleCard(id: card.id, isOn: !card.isOn)
                    } label: {
                        Text((card.isOn ? "✓ " : "   ") + card.name
                             + " — " + (model.presets.first { $0.id == card.presetID }?.name ?? "no preset"))
                    }
                }
            }
            Button {
                model.openSettings(pane: .presets, presetID: model.settings.activePresetID)
            } label: {
                Label("Manage presets…", systemImage: "list.bullet.rectangle")
            }
        } label: {
            Label("Presets", systemImage: "square.stack")
        }

        // 2 — editor
        Button {
            model.openSettings(pane: .presets, presetID: model.settings.activePresetID)
        } label: {
            Label("Edit This Preset…", systemImage: "slider.horizontal.3")
        }
        .keyboardShortcut("e", modifiers: .command)
        .disabled(model.presets.isEmpty)

        // 3 — settings
        Button {
            model.openSettings()
        } label: {
            Label("Settings…", systemImage: "gearshape")
        }
        .keyboardShortcut(",", modifiers: .command)

        // 4 — re-send
        Button {
            model.reapply()
        } label: {
            Label("Reapply Now", systemImage: "arrow.clockwise")
        }
        .keyboardShortcut("r", modifiers: .command)
        .disabled(!model.multiStatus.isConnected || !model.hasRunnableCard)

        // 5 — clear
        Button {
            model.clearPresence()
        } label: {
            Label(model.enabledCards.count > 1 ? "Clear All Presences" : "Clear Presence",
                  systemImage: "xmark.circle")
        }
        .disabled(!model.multiStatus.isConnected)

        Divider()

        // 6 — only when Discord is not running
        if !model.multiStatus.isConnected {
            Button {
                model.openDiscord()
            } label: {
                Label("Open Discord", systemImage: "arrow.up.forward.app")
            }
        }

        Divider()

        // 9 — quit
        Button {
            NSApp.terminate(nil)
        } label: {
            Label("Quit Discord RP", systemImage: "power")
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}
