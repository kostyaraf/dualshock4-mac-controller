import CoreGraphics

/// Posts synthetic key presses. Needs Accessibility permission.
final class VirtualKeyboard {
    private let source = CGEventSource(stateID: .hidSystemState)

    func key(_ combo: KeyCombo, down: Bool) {
        guard let e = CGEvent(keyboardEventSource: source, virtualKey: combo.keyCode, keyDown: down) else { return }
        if let held = combo.heldFlags {
            // A modifier on its own is a "flags changed" event, not a key press.
            e.type = .flagsChanged
            e.flags = down ? combo.flags.union(held) : combo.flags
        } else {
            e.flags = combo.flags
        }
        e.post(tap: .cghidEventTap)
    }
}
