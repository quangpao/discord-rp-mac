import AppKit
import DiscordRP
import SwiftUI
import UniformTypeIdentifiers

/// The editor lives in a plain AppKit window: an agent app with a `Window` scene can pop it
/// open on launch, and this way the window is created only when asked for.
@MainActor
final class EditorWindowController: NSWindowController {
    init(model: AppModel) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "CustomRP — Preset"
        window.minSize = NSSize(width: 480, height: 600)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ActivityEditorView(model: model))
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

/// Layout follows the Open Design handoff spec (`docs/ui/customrp-editor-window-spec.html`):
/// two-tier rows — inline rows with a fixed 132 pt label column, stacked groups for fields that
/// need the full card width — one section-header treatment, and a pinned footer. No control ever
/// shares a line with a full-length URL.
struct ActivityEditorView: View {
    @ObservedObject var model: AppModel
    @State private var draft = Activity()
    @State private var presetName: String = ""
    @State private var appIDField: String = ""
    @State private var pipeIndex: Int = 0
    @State private var assetNames: [String] = []
    @State private var assetError: String?
    @State private var giphyStatus: String?
    @State private var giphyUploading = false
    @State private var giphyHidden = false

    /// Spec: 132 pt label column, sized by the longest label ("Shown as (Discord app name)").
    private let labelColumn: CGFloat = 132
    private let inlineSpacing: CGFloat = 8

    var body: some View {
        Form {
            connectionSection
            presenceSection
            timeSection
            imageSection
            buttonSection
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .frame(minWidth: 480, minHeight: 600)
        .onAppear(perform: load)
    }

    // MARK: - row primitives

    private func inlineRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: inlineSpacing) {
            Text(label)
                .frame(width: labelColumn, alignment: .leading)
            content()
        }
        .frame(minHeight: 28)
    }

    /// Action rows line up with the control column, not the label column.
    private func actionRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: inlineSpacing) {
            Color.clear.frame(width: labelColumn, height: 1)
            content()
            Spacer(minLength: 0)
        }
    }

    private func stackedGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .padding(.vertical, 2)
    }

    private func field(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.roundedBorder)
    }

    private var statusRow: some View {
        HStack(spacing: 6) {
            Circle()
                .frame(width: 7, height: 7)
                .foregroundStyle(model.status.isConnected ? Color.green
                                 : model.status.needsAttention ? Color.red
                                 : Color.orange)
            Text(model.status.shortText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - sections

    private var connectionSection: some View {
        Section("Connection") {
            inlineRow("Discord Application ID") {
                TextField("e.g. 1041550572223995925", text: $appIDField)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.updateConnection(appID: appIDField, pipeIndex: pipeIndex) }
            }
            inlineRow("Pipe index") {
                HStack(spacing: 8) {
                    Stepper(value: $pipeIndex, in: 0...9) {
                        Text("\(pipeIndex)").monospacedDigit()
                    }
                    .frame(width: 110, alignment: .leading)
                    Text("0 = Discord · 1 = PTB · 2 = Canary")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            actionRow {
                Button("Apply") { model.updateConnection(appID: appIDField, pipeIndex: pipeIndex) }
            }
            statusRow
        }
    }

    private var presenceSection: some View {
        Section("Presence") {
            inlineRow("Preset name (this app only)") {
                TextField("Default", text: $presetName).textFieldStyle(.roundedBorder)
            }
            inlineRow("Shown as (Discord app name)") {
                TextField("CustomRP by quangpao", text: $draft.name).textFieldStyle(.roundedBorder)
            }
            inlineRow("Type") {
                Picker("", selection: $draft.kind) {
                    ForEach(ActivityKind.allCases) { kind in Text(kind.label).tag(kind) }
                }
                .labelsHidden()
                .frame(minWidth: 150, alignment: .leading)
            }
            inlineRow("Show as") {
                Picker("", selection: $draft.display) {
                    ForEach(DisplayType.allCases) { type in Text(type.label).tag(type) }
                }
                .labelsHidden()
                .frame(minWidth: 150, alignment: .leading)
            }
            inlineRow("Details") {
                TextField("Đang code", text: $draft.details).textFieldStyle(.roundedBorder)
            }
            stackedGroup("Details link (optional)") {
                field("https://…", text: $draft.detailsURL)
            }
            inlineRow("State") {
                TextField("customrp-mac", text: $draft.state).textFieldStyle(.roundedBorder)
            }
            stackedGroup("State link (optional)") {
                field("https://…", text: $draft.stateURL)
            }
            if draft.kind.allowsParty {
                inlineRow("Party") {
                    HStack(spacing: 6) {
                        TextField("", value: $draft.partySize, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 46)
                            .monospacedDigit()
                        Text("current").font(.system(size: 11)).foregroundStyle(.secondary)
                        TextField("", value: $draft.partyMax, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 46)
                            .monospacedDigit()
                        Text("max").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var timeSection: some View {
        Section("Time") {
            inlineRow("Mode") {
                Picker("", selection: $draft.timestampMode) {
                    ForEach(TimestampMode.allCases) { mode in Text(mode.label).tag(mode) }
                }
                .labelsHidden()
                .frame(minWidth: 196, alignment: .leading)
                .disabled(!draft.kind.allowsTimestamps)
            }
            Text(draft.kind.allowsTimestamps
                 ? draft.timestampMode.explanation
                 : "The “Competing” type cannot show timestamps.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if draft.timestampMode == .custom {
                stackedGroup("Start") {
                    DatePicker("", selection: $draft.customStart,
                               in: ActivityRules.earliestTimestamp...ActivityRules.latestTimestamp)
                        .labelsHidden()
                        .datePickerStyle(.field)
                }
                inlineRow("Show end") {
                    Toggle("", isOn: $draft.customEndEnabled).labelsHidden()
                }
                stackedGroup("End") {
                    DatePicker("", selection: $draft.customEnd,
                               in: ActivityRules.earliestTimestamp...ActivityRules.latestTimestamp)
                        .labelsHidden()
                        .datePickerStyle(.field)
                        .disabled(!draft.customEndEnabled)
                }
            }
        }
    }

    private var imageSection: some View {
        Section("Images") {
            Text("A key is either an asset name you uploaded to your Discord app, or an https URL. Animation only renders through an external URL.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            imageSlot(title: "Large", key: $draft.largeKey, text: $draft.largeText, link: $draft.largeURL)
            imageSlot(title: "Small", key: $draft.smallKey, text: $draft.smallText, link: $draft.smallURL)

            inlineRow("Private on Giphy") {
                Toggle("", isOn: $giphyHidden).labelsHidden()
            }
            actionRow {
                Button("Load asset names") { Task { await loadAssets() } }
                if let assetError {
                    Text(assetError).font(.system(size: 11)).foregroundStyle(.red)
                } else if !assetNames.isEmpty {
                    Text("\(assetNames.count) assets").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            if let giphyStatus {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: giphyStatus.hasPrefix("✓") ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(giphyStatus.hasPrefix("✓") ? Color.green : Color.red)
                    Text(giphyStatus)
                        .font(.system(size: 11))
                        .foregroundStyle(giphyStatus.hasPrefix("✓") ? Color.secondary : Color.red)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func imageSlot(title: String, key: Binding<String>, text: Binding<String>, link: Binding<String>) -> some View {
        stackedGroup(title) {
            field("key or URL", text: key)
            field("text (optional)", text: text)
            field("link (optional)", text: link)
            HStack(spacing: 8) {
                Button(giphyUploading ? "Uploading…" : "Upload…") { uploadToGiphy(into: key, slot: title) }
                    .disabled(giphyUploading)
                Menu("Assets") {
                    if assetNames.isEmpty {
                        Text("Load asset names first")
                    } else {
                        ForEach(assetNames, id: \.self) { name in
                            Button(name) { key.wrappedValue = name }
                        }
                    }
                }
                .frame(width: 100)
                Spacer(minLength: 0)
            }
        }
    }

    private var buttonSection: some View {
        Section("Buttons") {
            ForEach(Array(draft.buttons.prefix(ActivityRules.maxButtons).indices), id: \.self) { index in
                stackedGroup("Button \(index + 1)") {
                    field("label", text: $draft.buttons[index].label)
                    field("URL", text: $draft.buttons[index].url)
                    HStack {
                        Button("Remove", role: .destructive) { draft.buttons.remove(at: index) }
                            .buttonStyle(.borderless)
                        Spacer(minLength: 0)
                    }
                }
            }
            actionRow {
                Button("Add button") { draft.buttons.append(Button()) }
                    .disabled(draft.buttons.count >= ActivityRules.maxButtons)
                if draft.buttons.count >= ActivityRules.maxButtons {
                    Text("2/2 — Discord shows at most two")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - pinned footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(model.issues.filter(\.isError).enumerated()), id: \.offset) { _, issue in
                Text(issue.message)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                Button("Save as New") {
                    saveCurrent()
                    model.addPreset(from: draft, name: presetName.isEmpty ? "Preset" : presetName)
                }
                .buttonStyle(.borderless)
                Button("Save") { saveCurrent() }
                    .keyboardShortcut("s", modifiers: .command)
                Button("Apply") { model.engine.apply(draft) }
                    .keyboardShortcut("r", modifiers: .command)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    // MARK: actions

    private func load() {
        appIDField = model.settings.appID
        pipeIndex = model.settings.pipeIndex
        if let preset = model.activePreset {
            draft = preset.activity
            presetName = preset.name
        }
    }

    private func saveCurrent() {
        guard var preset = model.activePreset else { return }
        preset.activity = draft
        if !presetName.isEmpty { preset.name = presetName }
        model.upsert(preset)
        model.select(preset)
    }

    private func loadAssets() async {
        guard !appIDField.isEmpty else {
            assetError = "Set the Application ID first."
            return
        }
        do {
            assetNames = try await AssetCatalog.assetNames(appID: appIDField)
            assetError = assetNames.isEmpty ? "No art assets uploaded for this app yet." : nil
        } catch {
            assetError = "Could not load assets: \(error.localizedDescription)"
        }
    }

    /// Pick a file, push it to Giphy, and drop the CDN URL into the given image slot.
    private func uploadToGiphy(into slot: Binding<String>, slot slotName: String) {
        guard let key = GiphyUploader.apiKey() else {
            giphyStatus = "✗ No API key. Save one at \(GiphyUploader.defaultKeyPath()) (chmod 600)."
            return
        }

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose an animated GIF (or MP4/WebM) to upload to Giphy for the \(slotName) image"
        if let gif = UTType(filenameExtension: "gif"), let mp4 = UTType(filenameExtension: "mp4") {
            panel.allowedContentTypes = [gif, mp4]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }

        giphyUploading = true
        giphyStatus = "Uploading \(url.lastPathComponent) for \(slotName)…"
        Task {
            do {
                let result = try await GiphyUploader.upload(
                    file: url, apiKey: key, hidden: giphyHidden, tags: "customrp,quangpao"
                )
                await MainActor.run {
                    slot.wrappedValue = result.mediaURL
                    giphyStatus = "✓ Uploaded → \(result.mediaURL) (\(slotName))"
                    giphyUploading = false
                }
            } catch let error as GiphyError {
                await MainActor.run {
                    giphyStatus = "✗ \(slotName): \(error.message)"
                    giphyUploading = false
                }
            } catch {
                await MainActor.run {
                    giphyStatus = "✗ \(slotName): \(error.localizedDescription)"
                    giphyUploading = false
                }
            }
        }
    }
}
