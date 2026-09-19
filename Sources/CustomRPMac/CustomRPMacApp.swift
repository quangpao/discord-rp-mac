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
            // Spec: the glyph stays a template image; state is carried by the shape, and the
            // only added colour is the 6 px red badge on an error.
            ZStack {
                Image(systemName: model.status.symbolName)
                if model.status.needsAttention {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 6, height: 6)
                        .offset(x: 5, y: 5)
                }
            }
        }
        .menuBarExtraStyle(.menu)
    }
}
