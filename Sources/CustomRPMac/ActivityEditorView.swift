import AppKit
import DiscordRP
import SwiftUI

/// The editor lives in a plain AppKit window: an agent app with a `Window` scene can pop it
/// open on launch, and this way the window is created only when asked for.
@MainActor
final class EditorWindowController: NSWindowController {
    init(model: AppModel) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 620),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "CustomRP — Preset"
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

/// One compact form for every field Discord accepts, with the same rules enforced in the UI.
struct ActivityEditorView: View {
    @ObservedObject var model: AppModel
    @State private var draft = Activity()
    @State private var presetName: String = ""
    @State private var appIDField: String = ""
    @State private var pipeIndex: Int = 0
    @State private var assetNames: [String] = []
    @State private var assetError: String?

    var body: some View {
        Form {
            connectionSection
            if !model.issues.isEmpty { issuesSection }
            contentSection
            timeSection
            imageSection
            buttonSection
            footerSection
        }
        .formStyle(.grouped)
        .frame(minWidth: 460, minHeight: 600)
        .onAppear(perform: load)
    }

    // MARK: sections

    private var connectionSection: some View {
        Section("Connection") {
            TextField("Discord Application ID", text: $appIDField)
                .onSubmit { model.updateConnection(appID: appIDField, pipeIndex: pipeIndex) }
            HStack {
                Stepper("Pipe index \(pipeIndex)", value: $pipeIndex, in: 0...9)
                Button("Apply") { model.updateConnection(appID: appIDField, pipeIndex: pipeIndex) }
            }
            Text(model.status.shortText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var issuesSection: some View {
        Section("Checks") {
            ForEach(Array(model.issues.enumerated()), id: \.offset) { _, issue in
                Text("\(issue.isError ? "⚠︎" : "ⓘ") \(issue.message)")
                    .font(.caption)
                    .foregroundStyle(issue.isError ? Color.red : Color.secondary)
            }
        }
    }

    private var contentSection: some View {
        Section("Presence") {
            TextField("Preset name", text: $presetName)
            Picker("Type", selection: $draft.kind) {
                ForEach(ActivityKind.allCases) { kind in Text(kind.label).tag(kind) }
            }
            Picker("Show as", selection: $draft.display) {
                ForEach(DisplayType.allCases) { type in Text(type.label).tag(type) }
            }
            TextField("Details", text: $draft.details)
            TextField("Details link (optional)", text: $draft.detailsURL)
            TextField("State", text: $draft.state)
            TextField("State link (optional)", text: $draft.stateURL)
            if draft.kind.allowsParty {
                HStack {
                    TextField("Party current", value: $draft.partySize, format: .number)
                    TextField("Party max", value: $draft.partyMax, format: .number)
                }
            }
        }
    }

    private var timeSection: some View {
        Section("Time") {
            Picker("Mode", selection: $draft.timestampMode) {
                ForEach(TimestampMode.allCases) { mode in Text(mode.label).tag(mode) }
            }
            .disabled(!draft.kind.allowsTimestamps)
            if draft.timestampMode == .custom {
                DatePicker("Start", selection: $draft.customStart,
                           in: ActivityRules.earliestTimestamp...ActivityRules.latestTimestamp)
                Toggle("Show end", isOn: $draft.customEndEnabled)
                if draft.customEndEnabled {
                    DatePicker("End", selection: $draft.customEnd,
                               in: ActivityRules.earliestTimestamp...ActivityRules.latestTimestamp)
                }
            }
        }
    }

    private var imageSection: some View {
        Section("Images") {
            Text("A key is either an asset name you uploaded to your Discord app, or an https URL.")
                .font(.caption)
                .foregroundStyle(.secondary)
            imageRow(title: "Large", key: $draft.largeKey, text: $draft.largeText, url: $draft.largeURL)
            imageRow(title: "Small", key: $draft.smallKey, text: $draft.smallText, url: $draft.smallURL)
            HStack {
                Button("Load asset names") { Task { await loadAssets() } }
                if let assetError {
                    Text(assetError).font(.caption).foregroundStyle(.red)
                } else if !assetNames.isEmpty {
                    Text("\(assetNames.count) assets").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func imageRow(title: String, key: Binding<String>, text: Binding<String>, url: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField("\(title) key or URL", text: key)
                if !assetNames.isEmpty {
                    Menu("Assets") {
                        ForEach(assetNames, id: \.self) { name in
                            Button(name) { key.wrappedValue = name }
                        }
                    }
                    .frame(width: 90)
                }
            }
            TextField("\(title) text (optional)", text: text)
            TextField("\(title) link (optional)", text: url)
        }
    }

    private var buttonSection: some View {
        Section("Buttons") {
            ForEach(0..<min(draft.buttons.count, ActivityRules.maxButtons), id: \.self) { index in
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Button \(index + 1) label", text: $draft.buttons[index].label)
                    TextField("Button \(index + 1) URL", text: $draft.buttons[index].url)
                    Button("Remove") { draft.buttons.remove(at: index) }
                        .font(.caption)
                }
            }
            if draft.buttons.count < ActivityRules.maxButtons {
                Button("Add button") { draft.buttons.append(Button()) }
            }
        }
    }

    private var footerSection: some View {
        Section {
            HStack {
                Button("Apply") { model.engine.apply(draft) }
                    .keyboardShortcut("r", modifiers: .command)
                Button("Save") { saveCurrent() }
                    .keyboardShortcut("s", modifiers: .command)
                Spacer()
                Button("Save as New") {
                    saveCurrent()
                    model.addPreset(from: draft, name: presetName.isEmpty ? "Preset" : presetName)
                }
            }
        }
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
}
