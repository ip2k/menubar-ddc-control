import AppKit
import SwiftUI

@main
struct XeneonControlApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        MenuBarExtra("Xeneon Control", systemImage: "sun.max") {
            MenuContent(app: delegate.app)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(app: delegate.app)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let app = AppModel()
    private var debugPanel: NSPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Developer aid: `--debug-show-ui` shows the popover's content in a panel and opens
        // Settings, so the UI can be inspected and screenshotted without clicking the menu bar.
        guard CommandLine.arguments.contains("--debug-show-ui") else { return }
        let panel = NSPanel(contentRect: NSRect(x: 200, y: 200, width: 340, height: 480),
                            styleMask: [.titled, .utilityWindow], backing: .buffered, defer: false)
        panel.title = "Quick Controls (debug)"
        panel.contentView = NSHostingView(rootView: MenuContent(app: app).overlay(DebugOpenSettings()))
        panel.setContentSize(panel.contentView!.fittingSize)
        panel.hidesOnDeactivate = false
        panel.makeKeyAndOrderFront(nil)
        debugPanel = panel
        NSApp.activate()

        // `--debug-snapshot <dir>` also writes each window to <dir>/<n>.png once the displays have answered.
        if let index = CommandLine.arguments.firstIndex(of: "--debug-snapshot"), index + 1 < CommandLine.arguments.count {
            let directory = URL(fileURLWithPath: CommandLine.arguments[index + 1])
            Task {
                try? await Task.sleep(for: .seconds(8))
                for (n, window) in NSApp.windows.enumerated() where window.isVisible {
                    if window.title.contains("Settings") || window.identifier?.rawValue.contains("Settings") == true {
                        window.setContentSize(NSSize(width: 900, height: 1900))
                        try? await Task.sleep(for: .milliseconds(500))
                    }
                    guard let view = window.contentView?.superview, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                    view.cacheDisplay(in: view.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: directory.appending(path: "\(n).png"))
                }
            }
        }
    }
}

private struct DebugOpenSettings: View {
    @Environment(\.openSettings) private var openSettings
    var body: some View {
        Color.clear.allowsHitTesting(false).task { openSettings() }
    }
}
