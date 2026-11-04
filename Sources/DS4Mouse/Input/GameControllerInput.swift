import Foundation
import GameController

/// Buttons, sticks, triggers, light and rumble through Apple's GameController framework.
/// Works with any controller macOS supports, not only DualShock.
final class GameControllerInput {
    private(set) var controller: GCController?
    var onConnect: ((GCController) -> Void)?
    var onDisconnect: (() -> Void)?

    init() {
        // We run in the background, so ask for input even when we're not the focused app.
        GCController.shouldMonitorBackgroundEvents = true

        NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] note in
            guard let self, self.controller == nil,
                  let c = note.object as? GCController, c.extendedGamepad != nil else { return }
            self.controller = c
            self.onConnect?(c)
        }
        NotificationCenter.default.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] note in
            guard let self, let c = note.object as? GCController, c === self.controller else { return }
            self.controller = nil
            self.onDisconnect?()
            if let next = GCController.controllers().first(where: { $0.extendedGamepad != nil }) {
                self.controller = next
                self.onConnect?(next)
            }
        }
        GCController.startWirelessControllerDiscovery {}
    }

    func read(into s: inout ControllerState) {
        guard let pad = controller?.extendedGamepad else { return }

        s.leftStick = Vec2(x: Double(pad.leftThumbstick.xAxis.value), y: Double(pad.leftThumbstick.yAxis.value))
        s.rightStick = Vec2(x: Double(pad.rightThumbstick.xAxis.value), y: Double(pad.rightThumbstick.yAxis.value))
        s.l2 = Double(pad.leftTrigger.value)
        s.r2 = Double(pad.rightTrigger.value)

        var b = Set<Button>()
        func add(_ input: GCControllerButtonInput?, _ button: Button) {
            if input?.isPressed == true { b.insert(button) }
        }
        add(pad.buttonA, .cross)
        add(pad.buttonB, .circle)
        add(pad.buttonX, .square)
        add(pad.buttonY, .triangle)
        add(pad.leftShoulder, .l1)
        add(pad.rightShoulder, .r1)
        add(pad.leftTrigger, .l2)
        add(pad.rightTrigger, .r2)
        add(pad.leftThumbstickButton, .l3)
        add(pad.rightThumbstickButton, .r3)
        add(pad.buttonOptions, .share)   // GameController calls Share "Options"
        add(pad.buttonMenu, .options)    // ...and Options "Menu"
        add(pad.buttonHome, .ps)
        add(pad.dpad.up, .dpadUp)
        add(pad.dpad.down, .dpadDown)
        add(pad.dpad.left, .dpadLeft)
        add(pad.dpad.right, .dpadRight)
        if let ds = pad as? GCDualShockGamepad { add(ds.touchpadButton, .touchpad) }
        if let dsense = pad as? GCDualSenseGamepad { add(dsense.touchpadButton, .touchpad) }
        s.buttons = b
    }

    func setLight(red: Float, green: Float, blue: Float) {
        controller?.light?.color = GCColor(red: red, green: green, blue: blue)
    }
}
