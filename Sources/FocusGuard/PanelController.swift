import AppKit
import Combine
import SwiftUI

/// Borderless, non-activating, fully transparent panel. It can become key, so space / Esc / ⌘ shortcuts work
/// while the app stays in the background (like a menu bar popover, but with a real alpha cut-out).
final class FloatingPanel: NSPanel {
    var onShortcut: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, onShortcut?(event) == true { return }
        super.sendEvent(event)
    }

    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
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
        panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: W + 2 * PAD, height: H + 2 * PAD),
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
        model.closePanel = { [weak self] in self?.hide() }

        if let button = item.button {
            button.target = self
            button.action = #selector(toggle)
            button.imagePosition = .imageLeft
            button.setAccessibilityLabel("FocusGuard")
        }
        updateStatusItem()
        // Menu bar icon mood and countdown follow the model.
        model.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.updateStatusItem() }
        }.store(in: &bag)
        Bubble.anchorFrame = { [weak self] in self?.item.button?.window?.frame }
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

    func show() {
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
        let x = min(max(itemFrame.midX - size.width / 2, visible.minX + 4), visible.maxX - size.width - 4)
        panel.setFrameOrigin(CGPoint(x: x, y: itemFrame.minY - size.height))
    }

    /// Space, Esc, ⌘Q and ⌘, while the panel has the keyboard. Returns true when the event is used.
    private func handle(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command {
            switch event.charactersIgnoringModifiers {
            case "q": NSApp.terminate(nil); return true
            case ",": model.toggleSettings(); return true
            default: return false
            }
        }
        guard flags.isEmpty else { return false }
        switch event.keyCode {
        case 53: hide(); return true // esc
        case 49: model.spaceTapped(); return true // space
        default: return false
        }
    }
}
