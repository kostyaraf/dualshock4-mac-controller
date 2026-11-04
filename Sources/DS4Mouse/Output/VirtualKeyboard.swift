import CoreGraphics

/// Posts synthetic key presses. Needs Accessibility permission.
final class VirtualKeyboard {
    private let source = CGEventSource(stateID: .hidSystemState)

    func key(_ combo: KeyCombo, down: Bool) {
        guard let e = CGEvent(keyboardEventSource: source, virtualKey: combo.keyCode, keyDown: down) else { return }
        e.flags = combo.flags
        e.post(tap: .cghidEventTap)
    }
}
