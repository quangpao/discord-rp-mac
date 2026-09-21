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
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Discord RP — Preset"
        window.minSize = NSSize(width: 560, height: 600)
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

/// Layout contract — and why this is hand-built instead of a `Form`:
///
/// SwiftUI's grouped `Form` does *row extraction*: a `TextField` placed in a row is pulled into the
/// form's control column (x ≈ 452 in a 720 pt window) while a `Picker`, `Button` or `Stepper` in the
/// same row is left where it is and ends up pinned to the row's trailing edge (x ≈ 718–890). Every
/// attempt to align them through the form — custom label column, `LabeledContent`, `fixedSize`,
/// `frame(alignment:)` — was measured on a rendered PNG and failed. Three or four x positions in one
/// card is the "chaotic" look.
///
/// So the window owns its grid: one `label | control` row primitive, a fixed trailing-aligned label
/// column, and **every** control is a plain child of the same `HStack`, so all controls start at the
/// same x by construction, whatever their type. Cards are drawn with the system's
/// `controlBackgroundColor` + rounded corners, which is what the grouped form looked like anyway.
struct ActivityEditorView: View {
    @ObservedObject var model: AppModel
    @State private var draft = Activity()
    @State private var presetName: String = ""
    @State private var appIDField: String = ""
    @State private var pipeIndex: Int = 0
    @State private var assets: [DiscordAsset] = []
    @State private var assetError: String?
    @State private var giphyStatus: String?
    @State private var giphyUploading = false
    @State private var giphyHidden = false
    /// Local history of Giphy uploads — an upload is done once and can be re-picked afterwards.
    @State private var uploads: [GiphyUpload] = []
    /// BYOK: the user's own Giphy key. Held only while typing; never read back from the store.
    @State private var keyDraft: String = ""
    @State private var keyStatus: String?
    @State private var keySource: GiphyKeySource = .none

    /// One grid for the whole window.
    private let labelColumn: CGFloat = 140
    private let columnGap: CGFloat = 10
    private let cardPadding: CGFloat = 14
    private let cardSpacing: CGFloat = 8

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                connectionCard
                presenceCard
                timeCard
                imageCard
                giphyCard
                buttonCard
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .frame(minWidth: 560, minHeight: 600)
        .onAppear(perform: load)
    }

    // MARK: - grid primitives

    /// The single row primitive: label in the fixed column, control in the control column.
    ///
    /// Alignment is `.top`, **not** `.firstTextBaseline`: a tall child without a text baseline
    /// (the image preview box) gets its top edge dropped onto the label's baseline under baseline
    /// alignment, which pushed the whole preview ~100 pt below its label and left a blank block
    /// where the content should have been.
    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: columnGap) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: labelColumn, alignment: .trailing)
                .padding(.top, 3)
            content()
            Spacer(minLength: 0)
        }
        .frame(minHeight: 24)
    }

    /// Helper text sits under its control, in the control column — one x for every hint.
    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, labelColumn + columnGap)
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        TextField("", text: text)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity)
            .accessibilityLabel(label)
    }

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: cardSpacing) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(cardPadding)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
        }
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
        .padding(.leading, labelColumn + columnGap)
    }

    // MARK: - cards

    private var connectionCard: some View {
        card("Connection") {
            row("Application ID") {
                field("Application ID", text: $appIDField)
                    .onSubmit { model.updateConnection(appID: appIDField, pipeIndex: pipeIndex) }
            }
            hint("From the Discord Developer Portal — discord.com/developers/applications")
            row("Pipe index") {
                Picker("", selection: $pipeIndex) {
                    ForEach(0...9, id: \.self) { index in Text("\(index)").tag(index) }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            hint("0 = Discord · 1 = PTB · 2 = Canary")
            row("Connection") {
                Button("Reconnect") { model.updateConnection(appID: appIDField, pipeIndex: pipeIndex) }
            }
            hint("Reconnect re-applies the connection and the active preset.")
            statusRow
        }
    }

    private var presenceCard: some View {
        card("Presence") {
            row("Preset name") {
                field("Preset name (this app only)", text: $presetName)
            }
            hint("This app only — never sent to Discord.")
            row("Shown as") {
                field("Shown as (Discord app name)", text: $draft.name)
            }
            hint("The app name Discord prints on your profile.")
            row("Type") {
                Picker("", selection: $draft.kind) {
                    ForEach(ActivityKind.selectable) { kind in Text(kind.label).tag(kind) }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            row("Show as") {
                Picker("", selection: $draft.display) {
                    ForEach(DisplayType.allCases) { type in Text(type.label).tag(type) }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            row("Details") {
                field("Details", text: $draft.details)
            }
            row("Details link") {
                field("Details link (optional)", text: $draft.detailsURL)
            }
            row("State") {
                field("State", text: $draft.state)
            }
            row("State link") {
                field("State link (optional)", text: $draft.stateURL)
            }
            if draft.kind.allowsParty {
                row("Party") {
                    HStack(spacing: 8) {
                        TextField("", value: $draft.partySize, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .monospacedDigit()
                            .frame(width: 64)
                            .accessibilityLabel("Party current")
                        Text("/").foregroundStyle(.secondary)
                        TextField("", value: $draft.partyMax, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .monospacedDigit()
                            .frame(width: 64)
                            .accessibilityLabel("Party max")
                        Text("current / max").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                hint("Discord renders this as “3 of 5” on the card.")
            }
        }
    }

    private var timeCard: some View {
        card("Time") {
            row("Mode") {
                Picker("", selection: $draft.timestampMode) {
                    ForEach(TimestampMode.allCases) { mode in Text(mode.label).tag(mode) }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                .disabled(!draft.kind.allowsTimestamps)
            }
            hint(draft.kind.allowsTimestamps
                 ? draft.timestampMode.explanation
                 : "The “Competing” type cannot show timestamps.")
            if draft.timestampMode == .custom {
                row("Start") {
                    DatePicker("", selection: $draft.customStart,
                               in: ActivityRules.earliestTimestamp...ActivityRules.latestTimestamp)
                        .labelsHidden()
                        .datePickerStyle(.field)
                }
                row("Show end") {
                    Toggle("", isOn: $draft.customEndEnabled).labelsHidden()
                }
                row("End") {
                    DatePicker("", selection: $draft.customEnd,
                               in: ActivityRules.earliestTimestamp...ActivityRules.latestTimestamp)
                        .labelsHidden()
                        .datePickerStyle(.field)
                        .disabled(!draft.customEndEnabled)
                }
            }
        }
    }

    private var imageCard: some View {
        card("Images") {
            hint("A key is either an asset name you uploaded to your Discord app, or an https URL. Animation only renders through an external URL.")
            row("Large key") {
                field("Large key or URL", text: $draft.largeKey)
            }
            row("Large preview") {
                ImagePreview(key: draft.largeKey, appID: appIDField, assetID: assetID(for: draft.largeKey))
            }
            row("Large text") {
                field("Large text (optional)", text: $draft.largeText)
            }
            row("Large link") {
                field("Large link (optional)", text: $draft.largeURL)
            }
            row("Large image") {
                Button(giphyUploading ? "Uploading…" : "Upload to Giphy…") {
                    uploadToGiphy(into: $draft.largeKey, slot: "Large")
                }
                .disabled(giphyUploading || keySource == .none)
                Menu("From uploaded assets") { assetButtons(into: $draft.largeKey) }
            }
            row("Large GIFs") {
                Menu("From my uploads") { libraryButtons(into: $draft.largeKey) }
                Button("Copy key") { copyKey(draft.largeKey) }
                    .disabled(draft.largeKey.isEmpty)
            }
            row("Small key") {
                field("Small key or URL", text: $draft.smallKey)
            }
            row("Small preview") {
                ImagePreview(key: draft.smallKey, appID: appIDField, assetID: assetID(for: draft.smallKey),
                             side: 64,
                             note: "Discord draws this as a ~20 px circle in the corner of the large image.")
            }
            row("Small text") {
                field("Small text (optional)", text: $draft.smallText)
            }
            row("Small link") {
                field("Small link (optional)", text: $draft.smallURL)
            }
            row("Small image") {
                Button(giphyUploading ? "Uploading…" : "Upload to Giphy…") {
                    uploadToGiphy(into: $draft.smallKey, slot: "Small")
                }
                .disabled(giphyUploading || keySource == .none)
                Menu("From uploaded assets") { assetButtons(into: $draft.smallKey) }
            }
            row("Small GIFs") {
                Menu("From my uploads") { libraryButtons(into: $draft.smallKey) }
                Button("Copy key") { copyKey(draft.smallKey) }
                    .disabled(draft.smallKey.isEmpty)
            }
            if keySource == .none {
                hint("Uploads are disabled until you add your own Giphy API key in the “Giphy — bring your own key” card below.")
                    .foregroundStyle(.orange)
            }
            row("Giphy") {
                Toggle("Private", isOn: $giphyHidden)
                    // Only meaningful for an upload, so it is disabled with the upload buttons.
                    .disabled(keySource == .none)
            }
            row("Asset names") {
                Button("Load from Discord") { Task { await loadAssets() } }
            }
            if let assetError {
                hint(assetError).foregroundStyle(.red)
            } else if !assets.isEmpty {
                hint("\(assets.count) assets available in the menus above.")
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
                .padding(.leading, labelColumn + columnGap)
            }
        }
    }

    @ViewBuilder
    private func assetButtons(into key: Binding<String>) -> some View {
        if assets.isEmpty {
            Text("Load asset names first")
        } else {
            ForEach(assets) { asset in
                Button(asset.name) { key.wrappedValue = asset.name }
            }
        }
    }

    /// The numeric id behind an asset name, for the preview URL (the CDN keys images by id).
    private func assetID(for key: String) -> String? {
        assets.first { $0.name == key.trimmingCharacters(in: .whitespacesAndNewlines) }?.id
    }

    /// Every GIF this app has uploaded, newest first: pick one instead of uploading it again
    /// (an upload costs one of the 10/day the dashboard key allows, and a hidden upload is not
    /// findable on giphy.com either).
    @ViewBuilder
    private func libraryButtons(into key: Binding<String>) -> some View {
        if uploads.isEmpty {
            Text("Nothing uploaded yet")
        } else {
            ForEach(uploads) { upload in
                Button("\(upload.filename) — \(upload.uploadedAt.formatted(date: .abbreviated, time: .shortened))\(upload.hidden ? " · private" : "")") {
                    key.wrappedValue = upload.mediaURL
                }
            }
        }
    }

    private func copyKey(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    /// BYOK: the app ships no Giphy key. The user's own key is stored in the Keychain, and this card
    /// is the only place it is ever entered. The key itself is never displayed or logged — only the
    /// source it came from.
    private var giphyCard: some View {
        card("Giphy — bring your own key") {
            hint("Uploads use your own Giphy account. This app ships no key, and the key is sent only to Giphy.")
            row("Key source") {
                HStack(spacing: 6) {
                    Circle()
                        .frame(width: 7, height: 7)
                        .foregroundStyle(keySource == .none ? Color.orange : Color.green)
                    Text(keySource.description)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            row("API key") {
                SecureField("paste your Giphy API key", text: $keyDraft)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                    .onSubmit(saveKey)
            }
            row("Key") {
                Button("Save to Keychain") { saveKey() }
                    .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Remove saved key") { removeKey() }
                Button("Get a key…") { openGiphyDashboard() }
            }
            if let keyStatus {
                hint(keyStatus).foregroundStyle(keyStatus.hasPrefix("✓") ? Color.secondary : Color.red)
            }
            hint("Create one at developers.giphy.com — a dashboard key allows 10 uploads per day, and uploads are public unless “Private” is ticked in the Images card.")
        }
    }

    private func saveKey() {
        do {
            try GiphyKeyStore.save(keyDraft)
            keyDraft = ""
            keySource = GiphyKeyStore.source()
            keyStatus = "✓ Key saved to the Keychain — uploads are enabled."
        } catch let error as GiphyKeyError {
            keyStatus = "✗ \(error.description)"
        } catch {
            keyStatus = "✗ \(error.localizedDescription)"
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

    private var buttonCard: some View {
        card("Buttons") {
            ForEach(Array(draft.buttons.prefix(ActivityRules.maxButtons).indices), id: \.self) { index in
                row("Button \(index + 1) label") {
                    field("Button \(index + 1) label", text: $draft.buttons[index].label)
                }
                row("Button \(index + 1) URL") {
                    field("Button \(index + 1) URL", text: $draft.buttons[index].url)
                }
                row("Button \(index + 1)") {
                    Button("Remove", role: .destructive) { draft.buttons.remove(at: index) }
                        .foregroundStyle(.red)
                }
            }
            row("Buttons") {
                Button("Add button") { draft.buttons.append(Button()) }
                    .disabled(draft.buttons.count >= ActivityRules.maxButtons)
            }
            hint(draft.buttons.count >= ActivityRules.maxButtons
                 ? "2/2 — Discord shows at most two buttons"
                 : "Discord shows at most two buttons.")
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
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    // MARK: actions

    private func load() {
        appIDField = model.settings.appID
        pipeIndex = model.settings.pipeIndex
        uploads = GiphyLibrary.shared.load()
        keySource = GiphyKeyStore.source()
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
            assets = try await AssetCatalog.assets(appID: appIDField)
            assetError = assets.isEmpty ? "No art assets uploaded for this app yet." : nil
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
                    uploads = GiphyLibrary.shared.load()
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
