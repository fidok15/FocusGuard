import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

/// Borderless, non-activating, fully transparent panel. It can become key, so space / Esc / ⌘ shortcuts work
/// while the app stays in the background (like a menu bar popover, but with a real alpha cut-out).
final class FloatingPanel: NSPanel {
    var onShortcut: ((NSEvent) -> Bool)?
    var onCancel: () -> Void = {}

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, onShortcut?(event) == true { return }
        super.sendEvent(event)
    }

    override func cancelOperation(_ sender: Any?) { onCancel() }
}

/// ⌃⌥⌘F anywhere toggles the panel. Carbon hot keys need no Accessibility permission.
@MainActor private var hotKeyAction: (() -> Void)?

@MainActor
private func registerHotKey(_ action: @escaping () -> Void) {
    hotKeyAction = action
    var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
        DispatchQueue.main.async { MainActor.assumeIsolated { hotKeyAction?() } }
        return noErr
    }, 1, &spec, nil, nil)
    var ref: EventHotKeyRef?
    let registered = RegisterEventHotKey(UInt32(kVK_ANSI_F), UInt32(controlKey | optionKey | cmdKey),
                                         EventHotKeyID(signature: OSType(0x46474B59), id: 1), GetApplicationEventTarget(), 0, &ref)
    if installed != noErr || registered != noErr { NSLog("FocusGuard: hot key not available (install \(installed), register \(registered))") }
}

/// Our own status item and the panel anchored under it. Replaces MenuBarExtra, which cannot be made
/// transparent or opened for testing.
@MainActor
final class PanelController: NSObject {
    let model: AppModel
    let panel: FloatingPanel
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var clickMonitor: Any?
    private var bag = Set<AnyCancellable>()
    /// Debug captures open the panel behind other windows and without taking focus.
    private let quiet: Bool

    init(model: AppModel, quiet: Bool = false) {
        self.model = model
        self.quiet = quiet
        panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: CW + 2 * PAD, height: CH + 2 * PAD),
                              styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false // the art casts its own shadow, which follows the alpha
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.level = quiet ? .normal : .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let host = NSHostingView(rootView: PanelRoot().environmentObject(model))
        host.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = host
        panel.onShortcut = { [weak self] in self?.handle($0) ?? false }
        panel.onCancel = { [weak self] in self?.escape() }
        model.closePanel = { [weak self] in self?.hide() }

        if let button = item.button {
            button.target = self
            button.action = #selector(statusClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeft
            button.setAccessibilityLabel("FocusGuard")
        }
        updateStatusItem()
        // Menu bar icon mood and countdown follow the model.
        model.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.updateStatusItem() }
        }.store(in: &bag)
        Bubble.anchorFrame = { [weak self] in self?.item.button?.window?.frame }
        if !quiet { registerHotKey { [weak self] in self?.toggle() } }
    }

    var windowNumber: Int { panel.windowNumber }
    var isOpen: Bool { panel.isVisible }

    private func updateStatusItem() {
        guard let button = item.button else { return }
        button.image = MenuIcon.image(model.menuMood)
        let text = model.clock.phase.isRunning ? " " + model.remainingText : ""
        if button.title != text {
            button.attributedTitle = NSAttributedString(string: text, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
            ])
        }
    }

    @objc func toggle() { isOpen ? hide() : show() }

    /// Left click toggles the panel; right click (or ctrl-click) opens a small menu.
    @objc private func statusClicked() {
        guard let event = NSApp.currentEvent, event.type == .rightMouseUp || event.modifierFlags.contains(.control) else { return toggle() }
        let running = model.clock.phase.isRunning
        let menu = NSMenu()
        for (title, selector, enabled) in [
            (running ? (model.clock.isPaused ? "Resume" : "Pause") : "Start session", #selector(menuStartPause), true),
            ("Stop session", #selector(menuStop), running),
            ("Settings", #selector(menuSettings), true),
        ] {
            let entry = menu.addItem(withTitle: NSLocalizedString(title, comment: ""), action: selector, keyEquivalent: "")
            entry.target = self
            entry.isEnabled = enabled
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: NSLocalizedString("Quit FocusGuard", comment: ""), action: #selector(NSApplication.terminate), keyEquivalent: "")
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    @objc private func menuStartPause() {
        if model.clock.phase.isRunning { model.togglePause() } else {
            model.requestStart()
            if model.cardKey == "why" { show() } // the camera explanation must be seen
        }
    }

    @objc private func menuStop() { model.stop() }

    @objc private func menuSettings() {
        if !isOpen { show() }
        model.showSettings = true
    }

    func show() {
        model.panelOpened()
        position()
        if quiet {
            panel.orderBack(nil)
        } else {
            panel.makeKeyAndOrderFront(nil)
            clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
                Task { @MainActor in self?.hide() }
            }
        }
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
        model.panelClosed()
    }

    /// Centered under the status item, kept on its screen.
    private func position() {
        let itemFrame = item.button?.window?.frame ?? NSRect(x: (NSScreen.main?.frame.maxX ?? 1440) - 80, y: (NSScreen.main?.visibleFrame.maxY ?? 900), width: 30, height: 24)
        let screen = NSScreen.screens.first { $0.frame.contains(CGPoint(x: itemFrame.midX, y: itemFrame.midY)) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = panel.frame.size
        let x = max(min(itemFrame.midX - size.width / 2, visible.maxX - size.width - 4), visible.minX + 4) // narrow screen: keep the left side
        panel.setFrameOrigin(CGPoint(x: x, y: max(itemFrame.minY - size.height, visible.minY)))
    }

    /// Esc steps back one layer (note, confirm, camera card, setup) before it closes the panel.
    private func escape() {
        if model.showSettings { model.showSettings = false }
        else if model.confirmStop { model.confirmStop = false }
        else if model.showCameraWhy { model.showCameraWhy = false }
        else if model.showSetup { model.showSetup = false }
        else { hide() }
    }

    /// Space, Esc, ⌘Q and ⌘, while the panel has the keyboard. Returns true when the event is used.
    private func handle(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == 48 { model.usingKeyboard = true; return false } // tab or shift-tab: let SwiftUI move the focus
        if flags == .command {
            switch event.charactersIgnoringModifiers {
            case "q": NSApp.terminate(nil); return true
            case ",": model.toggleSettings(); return true
            default: return false
            }
        }
        guard flags.isEmpty else { return false }
        switch event.keyCode {
        case 53: escape(); return true
        case 49: // space
            if model.usingKeyboard && model.controlFocused { return false } // the focused control gets it
            if event.isARepeat { return true } // holding space must not flip pause on and off
            // Only the plain card answers space: a question or the note on top must not start or pause anything.
            if model.showSettings || model.cardKey == "confirm" || model.cardKey == "why" { return true }
            model.spaceTapped(); return true
        default: return false
        }
    }
}
