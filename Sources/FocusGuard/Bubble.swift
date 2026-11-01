import AppKit
import SwiftUI

/// Manga speech bubble that drops down from the menu bar icon.
@MainActor
enum Bubble {
    private static var panel: NSPanel?
    /// Screen frame of our status item, set by the panel controller.
    static var anchorFrame: () -> NSRect? = { nil }

    static func show(_ text: String, cat: NSImage?) {
        panel?.orderOut(nil)
        let size = CGSize(width: 300, height: 104)
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isReleasedWhenClosed = false
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = NSHostingView(rootView: BubbleView(text: text, cat: cat) { hide(p) })
        // Enter: fade in while dropping 8 pt from under the menu bar.
        let target = origin(for: size)
        p.setFrameOrigin(CGPoint(x: target.x, y: target.y + 8))
        p.alphaValue = 0
        p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup {
            $0.duration = 0.28
            $0.timingFunction = CAMediaTimingFunction(name: .easeOut)
            p.animator().alphaValue = 1
            p.animator().setFrameOrigin(target)
        }
        panel = p
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { hide(p) }
    }

    private static func hide(_ p: NSPanel) {
        guard panel === p else { return }
        // Exit: shorter and quieter than the enter.
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.15; p.animator().alphaValue = 0 }) {
            Task { @MainActor in p.orderOut(nil); if panel === p { panel = nil } }
        }
    }

    /// Below our status item; falls back to the top-right corner of the main screen.
    private static func origin(for size: CGSize) -> CGPoint {
        let item = anchorFrame()
        let screen = NSScreen.screens.first { screen in item.map { screen.frame.contains($0.origin) } ?? false }?.visibleFrame
            ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let x = (item?.midX ?? screen.maxX - size.width / 2 - 12) - 34
        return CGPoint(x: min(max(x, screen.minX + 8), screen.maxX - size.width - 8),
                       y: (item?.minY ?? screen.maxY) - size.height - 2)
    }
}

struct BubbleView: View {
    let text: String
    let cat: NSImage?
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if let cat {
                Image(nsImage: cat).resizable().scaledToFill()
                    .frame(width: 54, height: 54).clipShape(Circle())
                    .overlay(Circle().stroke(Ink.pencil, lineWidth: 2.2))
            }
            Text(text)
                .font(Ink.hand(15))
                .foregroundStyle(Ink.pencil)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 22).padding(.bottom, 12)
        .background {
            SpeechBubble().fill(Ink.paper).shadow(color: .black.opacity(0.25), radius: 6, y: 3)
            // Manga screentone in the lower-right corner.
            Canvas { ctx, size in
                for row in 0..<7 { for col in 0..<16 {
                    let x = size.width - 14 - CGFloat(col) * 5 - (row % 2 == 0 ? 0 : 2.5), y = size.height - 12 - CGFloat(row) * 4.5
                    let r = max(0, 1.7 - CGFloat(col + row) * 0.08)
                    ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(Ink.pencil.opacity(0.28)))
                } }
            }
            .clipShape(SpeechBubble())
        }
        .overlay {
            // Ink weight: a thin line all round, a heavier second pass fading in toward the lower right.
            SpeechBubble().stroke(Ink.pencil, style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
            SpeechBubble().stroke(Ink.pencil, style: StrokeStyle(lineWidth: 4.2, lineJoin: .round))
                .mask(LinearGradient(colors: [.clear, .clear, .black], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .padding(6)
        .onTapGesture(perform: dismiss)
    }
}

/// Rounded comic bubble with a tail pointing up toward the menu bar icon, as one outline (no seam under the tail).
private struct SpeechBubble: Shape {
    func path(in rect: CGRect) -> Path {
        let b = rect.divided(atDistance: 12, from: .minYEdge).remainder
        let r: CGFloat = 22
        var path = Path()
        path.move(to: CGPoint(x: b.minX + r, y: b.minY))
        path.addLine(to: CGPoint(x: b.minX + 28, y: b.minY))
        path.addQuadCurve(to: CGPoint(x: b.minX + 38, y: rect.minY), control: CGPoint(x: b.minX + 36, y: b.minY - 4))
        path.addQuadCurve(to: CGPoint(x: b.minX + 50, y: b.minY), control: CGPoint(x: b.minX + 40, y: b.minY - 2))
        path.addArc(tangent1End: CGPoint(x: b.maxX, y: b.minY), tangent2End: CGPoint(x: b.maxX, y: b.maxY), radius: r)
        path.addArc(tangent1End: CGPoint(x: b.maxX, y: b.maxY), tangent2End: CGPoint(x: b.minX, y: b.maxY), radius: r)
        path.addArc(tangent1End: CGPoint(x: b.minX, y: b.maxY), tangent2End: CGPoint(x: b.minX, y: b.minY), radius: r)
        path.addArc(tangent1End: CGPoint(x: b.minX, y: b.minY), tangent2End: CGPoint(x: b.maxX, y: b.minY), radius: r)
        path.closeSubpath()
        return path
    }
}
