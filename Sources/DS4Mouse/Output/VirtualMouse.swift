import AppKit
import CoreGraphics

enum MouseButton {
    case left, right, middle

    var cg: CGMouseButton {
        switch self {
        case .left: .left
        case .right: .right
        case .middle: .center
        }
    }

    func eventType(down: Bool) -> CGEventType {
        switch self {
        case .left: down ? .leftMouseDown : .leftMouseUp
        case .right: down ? .rightMouseDown : .rightMouseUp
        case .middle: down ? .otherMouseDown : .otherMouseUp
        }
    }
}

/// Posts synthetic mouse events. Needs Accessibility permission.
final class VirtualMouse {
    private let source = CGEventSource(stateID: .hidSystemState)
    private var pressed: Set<MouseButton> = []
    private var lastClick: (button: MouseButton, time: TimeInterval, pos: CGPoint, count: Int)?
    private var moveRest = Vec2()
    private var scrollRest = Vec2()

    var location: CGPoint { CGEvent(source: nil)?.location ?? .zero }

    func move(dx: Double, dy: Double) {
        moveRest.x += dx
        moveRest.y += dy
        let ix = moveRest.x.rounded(.towardZero), iy = moveRest.y.rounded(.towardZero)
        guard ix != 0 || iy != 0 else { return }
        moveRest.x -= ix
        moveRest.y -= iy

        let from = location
        let to = clampToScreens(CGPoint(x: from.x + ix, y: from.y + iy), current: from)
        let (type, button): (CGEventType, CGMouseButton) =
            pressed.contains(.left) ? (.leftMouseDragged, .left) :
            pressed.contains(.right) ? (.rightMouseDragged, .right) :
            pressed.contains(.middle) ? (.otherMouseDragged, .center) : (.mouseMoved, .left)
        guard let e = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: to, mouseButton: button) else { return }
        e.setIntegerValueField(.mouseEventDeltaX, value: Int64(ix))
        e.setIntegerValueField(.mouseEventDeltaY, value: Int64(iy))
        e.post(tap: .cghidEventTap)
    }

    func button(_ b: MouseButton, down: Bool) {
        guard down != pressed.contains(b) else { return }
        let pos = location
        if down {
            let now = ProcessInfo.processInfo.systemUptime
            var count = 1
            if let l = lastClick, l.button == b, now - l.time < NSEvent.doubleClickInterval,
               hypot(l.pos.x - pos.x, l.pos.y - pos.y) < 6 {
                count = l.count + 1
            }
            lastClick = (b, now, pos, count)
            pressed.insert(b)
        } else {
            pressed.remove(b)
        }
        guard let e = CGEvent(mouseEventSource: source, mouseType: b.eventType(down: down), mouseCursorPosition: pos, mouseButton: b.cg) else { return }
        e.setIntegerValueField(.mouseEventClickState, value: Int64(lastClick?.count ?? 1))
        e.post(tap: .cghidEventTap)
    }

    /// Positive dy scrolls the view up, positive dx scrolls it left (same as wheel events).
    func scroll(dx: Double, dy: Double) {
        scrollRest.x += dx
        scrollRest.y += dy
        let ix = scrollRest.x.rounded(.towardZero), iy = scrollRest.y.rounded(.towardZero)
        guard ix != 0 || iy != 0 else { return }
        scrollRest.x -= ix
        scrollRest.y -= iy
        CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
                wheel1: Int32(iy), wheel2: Int32(ix), wheel3: 0)?.post(tap: .cghidEventTap)
    }

    func releaseAll() {
        for b in pressed { button(b, down: false) }
    }

    private func clampToScreens(_ p: CGPoint, current: CGPoint) -> CGPoint {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetActiveDisplayList(16, &ids, &count)
        let rects = ids.prefix(Int(count)).map(CGDisplayBounds)
        if rects.contains(where: { $0.contains(p) }) { return p }
        guard let r = rects.first(where: { $0.contains(current) }) ?? rects.first else { return p }
        return CGPoint(x: min(max(p.x, r.minX), r.maxX - 1), y: min(max(p.y, r.minY), r.maxY - 1))
    }
}
