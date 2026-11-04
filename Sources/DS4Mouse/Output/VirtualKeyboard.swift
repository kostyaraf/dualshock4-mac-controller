import CoreGraphics

/// Posts synthetic key presses. Needs Accessibility permission.
final class VirtualKeyboard {
    private let source = CGEventSource(stateID: .hidSystemState)

    /// Modifiers currently held by gamepad buttons (e.g. PS as Cmd).
    /// They are added to every key and mouse event, so PS + L1 becomes Cmd+Tab.
    private(set) var heldModifiers: CGEventFlags = []

    func key(_ combo: KeyCombo, down: Bool) {
        guard let e = CGEvent(keyboardEventSource: source, virtualKey: combo.keyCode, keyDown: down) else { return }
        if let held = combo.heldFlags {
            // A modifier on its own is a "flags changed" event, not a key press.
            if down { heldModifiers.formUnion(held) } else { heldModifiers.subtract(held) }
            e.type = .flagsChanged
            e.flags = combo.flags.union(heldModifiers)
        } else {
            e.flags = combo.flags.union(heldModifiers)
        }
        e.post(tap: .cghidEventTap)
    }
}
