import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: PanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshots"), i + 1 < args.count {
            Snapshots.render(to: args[i + 1])
            exit(0)
        }
        if args.contains("--window") { DebugWindow.show(); return }
        if args.contains("--open-panel") { controller = DebugWindow.openPanel(); return }
        #endif
        controller = PanelController(model: AppModel())
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory) // menu bar only: no Dock icon
    app.run()
}
