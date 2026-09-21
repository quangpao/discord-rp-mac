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

    private var statusText: String { model.status.shortText }

    var body: some View {
        // 0 — status line (not interactive)
        Label(statusText, systemImage: model.status.dotSymbolName)

        // E1 — error state only
        if model.status.needsAttention {
            Button {
                model.openEditor()
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
            Button {
                model.openEditor()
            } label: {
                Label("Manage presets…", systemImage: "list.bullet.rectangle")
            }
        } label: {
            Label("Presets", systemImage: "square.stack")
        }

        // 2 — editor
        Button {
            model.openEditor()
        } label: {
            Label("Edit This Preset…", systemImage: "slider.horizontal.3")
        }
        .keyboardShortcut(",", modifiers: .command)
        .disabled(model.presets.isEmpty)

        // 3 — re-send
        Button {
            model.reapply()
        } label: {
            Label("Reapply Now", systemImage: "arrow.clockwise")
        }
        .keyboardShortcut("r", modifiers: .command)
        .disabled(!model.status.isConnected || model.settings.appID.isEmpty)

        // 4 — clear
        Button {
            model.engine.clear()
        } label: {
            Label("Clear Presence", systemImage: "xmark.circle")
        }
        .disabled(!model.status.isConnected)

        Divider()

        // 5 — login item. The icon is NOT a checkmark: a menu `Toggle` draws that itself (a
        // `checkmark` symbol here produced two ticks). But the label does need *an* icon, because
        // every other row has one — without it this row's text slid into the icon gutter and sat
        // ~19 pt left of everything else.
        Toggle(isOn: Binding(
            get: { model.launchAtLogin },
            set: { model.setLaunchAtLogin($0) }
        )) {
            Label("Launch at Login", systemImage: "desktopcomputer")
        }

        // 6 — only when Discord is not running
        if !model.status.isConnected {
            Button {
                model.openDiscord()
            } label: {
                Label("Open Discord", systemImage: "arrow.up.forward.app")
            }
        }

        // 8 — update check. Manual on purpose: nothing polls on a timer, so the app only makes the
        // network calls the user asks for (see SECURITY.md).
        Button {
            Task { await model.checkForUpdates() }
        } label: {
            Label("Check for Updates…", systemImage: "arrow.triangle.2.circlepath")
        }
        .disabled(model.updateStatus == .checking)

        if case .checking = model.updateStatus {
            Text("Checking for updates…")
        }
        if case .upToDate(let current) = model.updateStatus {
            Text("Up to date (\(current))")
        }
        if case .available(let version, let url) = model.updateStatus {
            Button {
                model.openURL(url)
            } label: {
                Label("Download \(version)", systemImage: "arrow.down.circle")
            }
        }
        if case .failed = model.updateStatus {
            Button {
                model.openURL(UpdateCheck.releasesPage)
            } label: {
                Label("Update check failed — open Releases", systemImage: "exclamationmark.triangle")
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
