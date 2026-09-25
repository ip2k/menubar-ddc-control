import AppKit
import SwiftUI

@main
struct MenubarDDCControlApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        MenuBarExtra("Menubar DDC Control", systemImage: "sun.max") {
            MenuContent(app: delegate.app, updates: delegate.updates)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(app: delegate.app, updates: delegate.updates)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let app = AppModel()
    let updates = UpdateChecker()
    private var debugPanel: NSPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        updates.start()
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--debug-tab"), index + 1 < arguments.count, let tab = Int(arguments[index + 1]) {
            UserDefaults.standard.set(tab, forKey: "settingsTab")
        }
        // Developer aids for inspecting the UI without Accessibility or Screen Recording access:
        //   --debug-show-ui          popover content in a panel, plus Settings
        //   --debug-open-menu        clicks the app's own menu bar item to open the real popover
        //   --debug-only <name>      only show displays whose name contains <name>
        //   --debug-gpu-on           tick "Adjust colors using GPU" (values stay at their defaults)
        //   --debug-tab <n>          open Settings on tab n (0 Displays, 1 Snapshots, 2 General)
        //   --debug-height <pt>      height to enlarge Settings to before snapshotting (default 1900)
        //   --debug-snapshot <dir>   (with --debug-show-ui, first runs Read All DDC Values) writes each window to <dir>/<n>.png, then again as
        //                            <n>-expanded.png with GPU adjustments expanded
        if arguments.contains("--debug-show-ui") {
            let panel = NSPanel(contentRect: NSRect(x: 200, y: 200, width: 340, height: 480),
                                styleMask: [.titled, .utilityWindow], backing: .buffered, defer: false)
            panel.title = "Quick Controls (debug)"
            panel.contentView = NSHostingView(rootView: MenuContent(app: app, updates: updates).overlay(DebugOpenSettings()))
            panel.hidesOnDeactivate = false
            panel.makeKeyAndOrderFront(nil)
            debugPanel = panel
            NSApp.activate()
        }
        let directory = arguments.firstIndex(of: "--debug-snapshot").flatMap { index in
            index + 1 < arguments.count ? URL(fileURLWithPath: arguments[index + 1]) : nil
        }
        guard arguments.contains("--debug-open-menu") || directory != nil else { return }
        Task {
            try? await Task.sleep(for: .seconds(8))
            if arguments.contains("--debug-open-menu") {
                UserDefaults.standard.set(false, forKey: "showsGPUAdjustments")
                let button = Self.statusItemButton()
                Self.log("windows: \(NSApp.windows.map { "\(type(of: $0)) \(Int($0.frame.height))" }), status button: \(button != nil)")
                Self.open(button)
                try? await Task.sleep(for: .seconds(1.5))
                Self.log("after open: \(NSApp.windows.map { "\(type(of: $0)) \(Int($0.frame.height)) visible \($0.isVisible)" })")
            }
            guard let directory else { return }
            if arguments.contains("--debug-gpu-on") { app.selected?.gpuEnabled = true }
            if arguments.contains("--debug-show-ui") {
                app.selected?.readAllValues()
                try? await Task.sleep(for: .seconds(8))
            }
            Self.snapshotWindows(to: directory, suffix: "")
            UserDefaults.standard.set(true, forKey: "showsGPUAdjustments")
            try? await Task.sleep(for: .seconds(1.5))
            Self.snapshotWindows(to: directory, suffix: "-expanded")
        }
    }

    /// MenuBarExtra opens on mouse-down in its status button, not on the button's action. The
    /// button's mouse-down runs a tracking loop until mouse-up, so the mouse-up is queued first.
    private static func open(_ button: NSStatusBarButton?) {
        guard let button, let window = button.window else { return }
        let point = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
        func event(_ type: NSEvent.EventType) -> NSEvent? {
            NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
        }
        guard let down = event(.leftMouseDown), let up = event(.leftMouseUp) else { return }
        window.postEvent(up, atStart: false)
        button.mouseDown(with: down)
    }

    private static func log(_ line: String) {
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }

    private static func statusItemButton() -> NSStatusBarButton? {
        func find(in view: NSView) -> NSStatusBarButton? {
            if let button = view as? NSStatusBarButton { return button }
            return view.subviews.lazy.compactMap(find).first
        }
        return NSApp.windows.lazy.compactMap { $0.contentView.flatMap(find) }.first
    }

    private static func snapshotWindows(to directory: URL, suffix: String) {
        for (n, window) in NSApp.windows.enumerated() where window.isVisible && window.frame.height > 60 {
            // Show a whole settings form rather than its first screen.
            if window.styleMask.contains(.titled), !(window is NSPanel) {
                let arguments = CommandLine.arguments
                let height = arguments.firstIndex(of: "--debug-height").flatMap { $0 + 1 < arguments.count ? Double(arguments[$0 + 1]) : nil } ?? 1900
                window.setContentSize(NSSize(width: 900, height: height))
                window.displayIfNeeded()
            }
            guard let view = window.contentView?.superview, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: directory.appending(path: "\(n)\(suffix).png"))
            log("snapshot \(n)\(suffix): \(type(of: window)) \(Int(window.frame.width))x\(Int(window.frame.height)) at y \(Int(window.frame.minY))")
        }
    }
}

private struct DebugOpenSettings: View {
    @Environment(\.openSettings) private var openSettings
    var body: some View {
        Color.clear.allowsHitTesting(false).task { openSettings() }
    }
}
