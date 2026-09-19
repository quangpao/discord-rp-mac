import AppKit
import DiscordRP
import SwiftUI

@main
struct CustomRPMacApp: App {
    @StateObject private var model: AppModel

    init() {
        // Never die from a peer hangup on the Unix socket.
        signal(SIGPIPE, SIG_IGN)

        if let code = SelfTest.runIfRequested() {
            exit(code)
        }
        SingleInstance.exitIfAlreadyRunning()
        _model = StateObject(wrappedValue: AppModel())
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(model: model)
        } label: {
            MenuBarGlyph(status: model.status)
        }
        .menuBarExtraStyle(.menu)
    }
}
