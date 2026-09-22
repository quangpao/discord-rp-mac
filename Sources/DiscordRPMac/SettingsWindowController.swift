import AppKit
import DiscordRP
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class SettingsWindowController: NSWindowController {
    init(model: AppModel) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 440),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Discord RP — Settings"
        window.minSize = NSSize(width: 560, height: 420)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView(model: model))
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

enum SettingsPane: String, CaseIterable, Identifiable {
    case cards = "Cards"
    case presets = "Presets"
    case general = "General"
    case giphy = "Giphy"

    var id: Self { self }
}

private struct VerifiedApplication: Decodable {
    let name: String
    let icon: String?
}

private enum ApplicationVerifier {
    static func verify(id rawID: String) async throws -> String {
        let id = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, id.allSatisfy(\.isNumber) else {
            throw VerificationError.notNumeric
        }
        guard let url = URL(string: "https://discord.com/api/v10/applications/\(id)/rpc") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw VerificationError.failed
        }
        let app = try JSONDecoder().decode(VerifiedApplication.self, from: data)
        return "\(app.name) · \(app.icon == nil ? "no icon" : "has icon")"
    }

    enum VerificationError: LocalizedError {
        case notNumeric
        case failed

        var errorDescription: String? {
            switch self {
            case .notNumeric: "Application ID must be numeric."
            case .failed: "Discord could not verify that application."
            }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel

    @State private var pane: SettingsPane = .cards
    @State private var selectedPresetID: UUID?
    @State private var renameDraft = ""
    @State private var presetStatus: String?
    @State private var verification: [UUID: String] = [:]
    @State private var verifying: Set<UUID> = []
    @State private var keyDraft = ""
    @State private var keySource: GiphyKeySource = .none
    @State private var keyStatus: String?

    init(model: AppModel, initialPane: SettingsPane = .cards) {
        self.model = model
        _pane = State(initialValue: initialPane)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $pane) {
                ForEach(SettingsPane.allCases) { pane in Text(pane.rawValue).tag(pane) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Settings section")
            .frame(width: 360)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch pane {
                    case .cards: cardsPane
                    case .presets: presetsPane
                    case .general: generalPane
                    case .giphy: giphyPane
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 560, maxWidth: .infinity, minHeight: 420, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear(perform: load)
    }

    private func load() {
        selectedPresetID = model.settings.activePresetID ?? model.presets.first?.id
        renameDraft = selectedPreset?.name ?? ""
        keySource = GiphyKeyStore.source()
    }

    private func textField(_ label: String, text: Binding<String>, placeholder: String = "") -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel(label)
    }

    private var cardControlWidth: CGFloat { 260 }

    private var cardsPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(model.settings.cards.enumerated()), id: \.element.id) { index, card in
                cardBlock(card, index: index)
            }
            HStack {
                Button("+ Add card") {
                    model.addCard(presetID: model.settings.activePresetID ?? model.presets.first?.id ?? UUID(),
                                  applicationID: "")
                }
            }
            .padding(.leading, rowGridControlIndent)
        }
    }

    private func cardBinding(_ card: PresenceCard) -> Binding<PresenceCard> {
        Binding {
            model.settings.cards.first { $0.id == card.id } ?? card
        } set: { model.setCard($0) }
    }

    private func cardRow(_ card: PresenceCard) -> some View {
        let binding = cardBinding(card)
        return VStack(alignment: .leading, spacing: 8) {
            row("On") {
                Toggle("", isOn: binding.isOn)
                    .labelsHidden()
                    .accessibilityLabel("Card enabled")
            }
            row("Name") {
                textField("Card name", text: binding.name, placeholder: "Card name (this app only)")
                    .frame(width: cardControlWidth)
            }
            row("Preset") {
                Picker("", selection: binding.presetID) {
                    ForEach(model.presets) { preset in Text(preset.name).tag(preset.id) }
                }
                .labelsHidden()
                .accessibilityLabel("Preset")
                .frame(width: cardControlWidth, alignment: .leading)
            }
            row("App ID",
                help: "Discord shows one card per application id, so a second card needs a second Discord application, with that card's assets uploaded there.") {
                HStack(spacing: 8) {
                    textField("Application ID", text: binding.applicationID,
                              placeholder: "required — one Discord app per card")
                        .frame(width: cardControlWidth)
                    Button(verifying.contains(card.id) ? "Verifying…" : "Verify") {
                        verify(card: binding.wrappedValue)
                    }
                    .disabled(verifying.contains(card.id))
                }
            }
            if let status = status(for: binding.wrappedValue) {
                row("Status") {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(status.text)
                            .font(.system(size: 11))
                            .foregroundStyle(status.color)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                        if status.canMakeUnique {
                            Button("Make unique") {
                                model.makeActivityNameUnique(for: card.id)
                            }
                            .font(.system(size: 11))
                        }
                    }
                }
            }
        }
    }

    private func cardBlock(_ card: PresenceCard, index: Int) -> some View {
        cardChrome {
            HStack(spacing: 8) {
                Text(cardTitle(for: card, index: index))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if model.settings.cards.count > 1 {
                    Button("Remove", role: .destructive) { model.removeCard(id: card.id) }
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .accessibilityLabel("Remove \(card.name.isEmpty ? "card \(index + 1)" : card.name)")
                }
            }
        } content: {
            cardRow(card)
        }
    }

    private func cardTitle(for card: PresenceCard, index: Int) -> String {
        let name = card.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return "Card \(index + 1) — \(name.isEmpty ? "Untitled" : name)"
    }

    private func status(for card: PresenceCard) -> (text: String, color: Color, canMakeUnique: Bool)? {
        let issues = model.cardIssues.filter { $0.cardID == card.id }
        if !issues.isEmpty {
            return (
                issues.map(\.message).joined(separator: " "),
                issues.contains { $0.kind != .invalidActivity } ? .red : .orange,
                false
            )
        }
        if model.duplicateActivityNameCards[card.id] != nil {
            return (
                "Another card uses the same activity name — Discord shows only one of them.",
                .orange,
                true
            )
        }
        guard let result = verification[card.id], !result.isEmpty else { return nil }
        return (result, .secondary, false)
    }

    private func verify(card: PresenceCard) {
        verifying.insert(card.id)
        verification[card.id] = nil
        Task {
            do {
                let result = try await ApplicationVerifier.verify(id: card.applicationID)
                verification[card.id] = "✓ \(result)"
            } catch {
                verification[card.id] = "Verify failed: \(error.localizedDescription)"
            }
            verifying.remove(card.id)
        }
    }

    private var presetsPane: some View {
        card("Presets") {
            row("Preset") {
                Picker("", selection: Binding(
                    get: { selectedPresetID ?? model.presets.first?.id },
                    set: {
                        selectedPresetID = $0
                        renameDraft = selectedPreset?.name ?? ""
                    }
                )) {
                    ForEach(model.presets) { preset in Text(preset.name).tag(Optional(preset.id)) }
                }
                .labelsHidden()
                .accessibilityLabel("Preset")
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            row("Name") {
                textField("Preset name", text: $renameDraft, placeholder: "preset name")
                Button("Rename") { renameSelectedPreset() }
                    .disabled(selectedPreset == nil || renameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            row("Actions") {
                Button("+ Add") { model.duplicateActivePreset(); load() }
                    .disabled(model.activePreset == nil)
                Button("Delete", role: .destructive) {
                    if let preset = selectedPreset {
                        model.deletePreset(preset)
                        load()
                    }
                }
                .foregroundStyle(.red)
                .disabled(selectedPreset == nil)
                Button("Import…") { importPresets() }
                Button("Export…") { exportPreset() }
                    .disabled(selectedPreset == nil)
            }
            if let presetStatus {
                hint(presetStatus, color: presetStatus.hasPrefix("✓") ? .secondary : .red)
            }
        }
    }

    private var selectedPreset: Preset? {
        guard let selectedPresetID else { return model.presets.first }
        return model.presets.first { $0.id == selectedPresetID }
    }

    private func renameSelectedPreset() {
        guard var preset = selectedPreset else { return }
        preset.name = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        model.upsert(preset)
        presetStatus = "✓ Renamed."
    }

    private func importPresets() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .millisecondsSince1970
            let imported: [Preset]
            if let one = try? decoder.decode(Preset.self, from: data) {
                imported = [one]
            } else {
                imported = try decoder.decode([Preset].self, from: data)
            }
            for preset in imported { model.upsert(preset) }
            selectedPresetID = imported.first?.id
            renameDraft = selectedPreset?.name ?? ""
            presetStatus = "✓ Imported \(imported.count) preset\(imported.count == 1 ? "" : "s")."
        } catch {
            presetStatus = "Import failed: \(error.localizedDescription)"
        }
    }

    private func exportPreset() {
        guard let preset = selectedPreset else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(preset.name).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .millisecondsSince1970
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(preset).write(to: url, options: .atomic)
            presetStatus = "✓ Exported."
        } catch {
            presetStatus = "Export failed: \(error.localizedDescription)"
        }
    }

    private var generalPane: some View {
        card("General") {
            row("Launch at Login") {
                Toggle("", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
                .labelsHidden()
                .accessibilityLabel("Launch at Login")
            }
            row("Pipe index", help: "0 = Discord · 1 = PTB · 2 = Canary") {
                Picker("", selection: Binding(
                    get: { model.settings.pipeIndex },
                    set: { model.reconnect(appID: model.settings.appID, pipeIndex: $0) }
                )) {
                    ForEach(0...9, id: \.self) { index in Text("\(index)").tag(index) }
                }
                .labelsHidden()
                .accessibilityLabel("Pipe index")
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            row("Connection") {
                Button("Reconnect") { model.reconnect(appID: model.settings.appID, pipeIndex: model.settings.pipeIndex) }
                if !model.multiStatus.isConnected {
                    Button("Open Discord") { model.openDiscord() }
                }
            }
            hint(model.multiStatus.shortText)
            Divider().padding(.vertical, 4)
            row("Updates") {
                Button("Check for Updates…") { Task { await model.checkForUpdates() } }
                    .disabled(model.updateStatus == .checking)
            }
            updateStatusLine
        }
    }

    private var giphyPane: some View {
        card("Giphy") {
            row("Source") {
                HStack(spacing: 6) {
                    Circle()
                        .frame(width: 7, height: 7)
                        .foregroundStyle(keySource == .none ? Color.orange : Color.green)
                    Text(keySource.description)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            row("API key", help: "Create one at developers.giphy.com. The key is saved only to your macOS Keychain.") {
                SecureField("paste your Giphy API key", text: $keyDraft)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Giphy API key")
                    .onSubmit(saveKey)
                    .frame(width: 260)
            }
            row("Actions") {
                Button("Save to Keychain") { saveKey() }
                    .disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Remove saved key") { removeKey() }
                Button("Get a key…") { openGiphyDashboard() }
            }
            if let keyStatus {
                hint(keyStatus, color: keyStatus.hasPrefix("✓") ? .secondary : .red)
            }
        }
    }

    @ViewBuilder
    private var updateStatusLine: some View {
        switch model.updateStatus {
        case .idle:
            EmptyView()
        case .checking:
            hint("Checking for updates…")
        case .upToDate(let current):
            hint("Up to date (\(current))")
        case .available(let version, let url):
            row("Available") {
                Button("Download \(version)") { model.openURL(url) }
            }
        case .failed(let reason):
            row("Status") {
                Button("Update check failed — open Releases") { model.openURL(UpdateCheck.releasesPage) }
                    .optionalHelp(reason)
            }
        }
    }

    private func saveKey() {
        do {
            try GiphyKeyStore.save(keyDraft)
            keyDraft = ""
            keySource = GiphyKeyStore.source()
            keyStatus = "✓ Key saved to the Keychain — uploads are enabled."
        } catch let error as GiphyKeyError {
            keyStatus = error.description
        } catch {
            keyStatus = error.localizedDescription
        }
    }

    private func removeKey() {
        GiphyKeyStore.clear()
        keySource = GiphyKeyStore.source()
        keyStatus = keySource == .none
            ? "✓ Saved key removed."
            : "Saved key removed — a key is still coming from \(keySource.description)."
    }

    private func openGiphyDashboard() {
        if let url = URL(string: "https://developers.giphy.com/dashboard/?create=true") {
            NSWorkspace.shared.open(url)
        }
    }
}
