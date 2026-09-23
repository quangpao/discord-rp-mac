import AppKit
import DiscordRP
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let model: AppModel
    var onClose: (@MainActor () -> Void)?

    init(model: AppModel, initialPane: SettingsPane = .cards, selectedPresetID: UUID? = nil) {
        self.model = model
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Discord RP — Settings"
        window.minSize = NSSize(width: 620, height: 420)
        window.isReleasedWhenClosed = false
        window.contentView = Self.contentView(model: model, initialPane: initialPane,
                                              selectedPresetID: selectedPresetID)
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    private static func contentView(model: AppModel, initialPane: SettingsPane,
                                    selectedPresetID: UUID?) -> NSView {
        NSHostingView(rootView: SettingsView(model: model, initialPane: initialPane,
                                             selectedPresetID: selectedPresetID))
    }

    func show(pane: SettingsPane, selectedPresetID: UUID?) {
        window?.contentView = Self.contentView(model: model, initialPane: pane,
                                               selectedPresetID: selectedPresetID)
        show()
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
        onClose = nil
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

    init(model: AppModel, initialPane: SettingsPane = .cards, selectedPresetID: UUID? = nil) {
        self.model = model
        _pane = State(initialValue: initialPane)
        _selectedPresetID = State(initialValue: selectedPresetID)
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

            Group {
                if pane == .presets {
                    presetsPane
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            switch pane {
                            case .cards: cardsPane
                            case .presets: EmptyView()
                            case .general: generalPane
                            case .giphy: giphyPane
                            }
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .frame(minWidth: 620, maxWidth: .infinity, minHeight: 420, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear(perform: load)
        .onChange(of: model.presets) { keepPresetSelectionValid() }
    }

    private func load() {
        keepPresetSelectionValid()
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
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                presetList
                Divider()
                presetActionBar
            }
            .frame(width: 210)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                if let selectedPreset {
                    Text(usageSummary(for: selectedPreset.id))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                    Divider()
                    ActivityEditorView(model: model, presetID: selectedPreset.id)
                        .id(selectedPreset.id)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No presets yet")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Add or import a preset to edit its activity.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var presetList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(model.presets) { preset in
                    Button {
                        selectedPresetID = preset.id
                        renameDraft = preset.name
                        presetStatus = nil
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preset.name)
                                .font(.system(size: 12, weight: selectedPresetID == preset.id ? .semibold : .regular))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            let usage = cardUsage(for: preset.id)
                            if !usage.isEmpty {
                                Text("Used by \(usage.joined(separator: ", "))")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(selectedPresetID == preset.id ? Color.accentColor.opacity(0.16) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(presetAccessibilityLabel(for: preset))
                }
            }
            .padding(8)
        }
    }

    private var presetActionBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Button { addPreset() } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("+ Add")
                .help("+ Add")

                Button { duplicateSelectedPreset() } label: {
                    Image(systemName: "doc.on.doc")
                }
                    .disabled(selectedPreset == nil)
                .accessibilityLabel("Duplicate")
                .help("Duplicate")

                Button(role: .destructive) { deleteSelectedPreset() } label: {
                    Image(systemName: "trash")
                }
                    .disabled(selectedPreset == nil)
                    .accessibilityLabel("Delete")
                    .help("Delete")

                Button { importPresets() } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .accessibilityLabel("Import…")
                .help("Import…")

                Button { exportPreset() } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                    .disabled(selectedPreset == nil)
                    .accessibilityLabel("Export…")
                    .help("Export…")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)

            if let presetStatus {
                Text(presetStatus)
                    .font(.system(size: 10))
                    .foregroundStyle(presetStatus.hasPrefix("✓") ? Color.secondary : Color.red)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(8)
    }

    private var selectedPreset: Preset? {
        guard let selectedPresetID else { return model.presets.first }
        return model.presets.first { $0.id == selectedPresetID }
    }

    private func keepPresetSelectionValid() {
        if let selectedPresetID, model.presets.contains(where: { $0.id == selectedPresetID }) {
            return
        }
        selectedPresetID = model.settings.activePresetID.flatMap { id in
            model.presets.first { $0.id == id }?.id
        } ?? model.presets.first?.id
    }

    private func cardUsage(for presetID: UUID) -> [String] {
        model.settings.cards.enumerated().compactMap { index, card in
            guard card.presetID == presetID else { return nil }
            return cardTitle(for: card, index: index)
        }
    }

    private func usageSummary(for presetID: UUID) -> String {
        let usage = cardUsage(for: presetID)
        return usage.isEmpty ? "Not used by any card" : "Used by \(usage.joined(separator: ", "))"
    }

    private func presetAccessibilityLabel(for preset: Preset) -> String {
        let usage = cardUsage(for: preset.id)
        return usage.isEmpty ? preset.name : "\(preset.name), used by \(usage.joined(separator: ", "))"
    }

    private func addPreset() {
        let preset = model.addPreset(from: Activity.sample(), name: "New preset")
        selectedPresetID = preset.id
        renameDraft = preset.name
        presetStatus = "✓ Added."
    }

    private func duplicateSelectedPreset() {
        guard let selectedPreset else { return }
        let preset = model.addPreset(from: selectedPreset.activity, name: selectedPreset.name + " copy")
        selectedPresetID = preset.id
        renameDraft = preset.name
        presetStatus = "✓ Duplicated."
    }

    private func deleteSelectedPreset() {
        guard let preset = selectedPreset else { return }
        model.deletePreset(preset)
        keepPresetSelectionValid()
        renameDraft = selectedPreset?.name ?? ""
        presetStatus = "✓ Deleted."
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
