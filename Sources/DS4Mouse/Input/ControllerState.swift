import Foundation

struct Vec2 {
    var x: Double = 0
    var y: Double = 0
    var length: Double { (x * x + y * y).squareRoot() }
}

/// Physical controls, named after the DualShock layout.
/// Other controllers (Xbox, DualSense) map onto the same names by position.
enum Button: String, CaseIterable, Codable {
    case cross, circle, square, triangle
    case l1, r1, l2, r2, l3, r3
    case share, options, ps, touchpad
    case dpadUp, dpadDown, dpadLeft, dpadRight
}

/// One finger on the touchpad, in raw pad units (x 0...1919, y 0...942, origin top-left).
struct Touch {
    var id: Int
    var x: Double
    var y: Double
}

/// Snapshot of everything the controller reports at one moment.
struct ControllerState {
    var buttons: Set<Button> = []
    var leftStick = Vec2()   // -1...1, y up
    var rightStick = Vec2()
    var l2: Double = 0       // 0...1
    var r2: Double = 0
    var touches: [Touch] = []
}
