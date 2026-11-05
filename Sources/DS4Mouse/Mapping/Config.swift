import Foundation

struct StickConfig: Codable {
    var speed: Double      // pixels per second at full tilt
    var deadzone: Double   // 0...1, ignore tilt below this
    var fineSpeed: Double  // fraction of `speed` at the edge of the slow center (see StickFeelConfig)
}

/// How both sticks respond — one shared setup, so cursor and scroll feel the same. See SPEC.md, Р-22.
/// Speed is a fraction of the stick's full speed against tilt (0 at the deadzone, 1 at full tilt):
/// inside `fineZone` it rises gently to the stick's `fineSpeed`, outside it rises steeply to 1.
struct StickFeelConfig: Codable {
    var fineZone: Double     // 0...1 tilt: the slow center. Change this to widen/narrow it for both sticks
    var fineCurve: Double    // >1: even gentler at the very start
    var outerCurve: Double   // >1: the outer part stays slow longer and shoots up at the rim
    var rimEnter: Double     // tilt that counts as "pushed to the rim"
    var rimExit: Double      // tilt below which the rim boost resets
    var rimHold: Double      // seconds at the rim before the boost starts
    var rimRamp: Double      // seconds to reach the full boost after that
    var rimMax: Double       // speed multiplier at the end of the ramp
}

/// Cursor only: the user keeps nudging the stick gently — aiming at something — so slow down a bit more.
/// Short pauses between nudges don't reset it, a long pause or a fast move does. See SPEC.md, Р-26.
struct AimConfig: Codable {
    var zone: Double         // 0...1 tilt that counts as aiming (inside the slow center)
    var resetTilt: Double    // tilting further than this ends aiming at once
    var hold: Double         // seconds of aiming (pauses not counted) before slowing down
    var ramp: Double         // seconds to reach the full slowdown
    var minFactor: Double    // speed multiplier at full slowdown
    var maxPause: Double     // a pause longer than this ends aiming
}

/// Holding a key that deletes text: after a while delete whole words, like on iPhone. See Р-14.
struct DeleteConfig: Codable {
    var wordsAfter: Double       // seconds of holding Backspace before switching to words
    var wordInterval: Double     // seconds between word deletions
}

struct TouchpadConfig: Codable {
    var enabled: Bool
    var cursorSpeed: Double          // screen pixels per touchpad unit
    var scrollSpeed: Double
    var deadband: Double             // touchpad units of finger wobble to ignore
    var smoothing: Double            // 0...1, lower = smoother but laggier
    // Pressing the pad down (it is a physical button). Fires at once on press.
    var click: String                // each press
    var doubleClick: String          // second quick press: undoes the first press's text with Backspace, then this
    var twoFingerClick: String       // press with two fingers on the pad
    var longPress: String            // holding the pad down: undoes the press's text, then this
    var longPressSeconds: Double
    var doubleClickSeconds: Double   // max time between presses to count as double
    var oneFingerMode: String        // "swipe" (gestures below) | "cursor"
    var twoFingerMode: String        // "swipe" (gestures below) | "scroll"
    var swipeDistance: Double        // touchpad units (pad is 1920 wide) a swipe must travel
    var swipes: [String: String]     // "up" | "down" | "left" | "right" -> action string
}

struct Config: Codable {
    var cursorStick: String          // "left" | "right" | "none"
    var scrollStick: String
    var cursor: StickConfig
    var scroll: StickConfig
    var invertScroll: Bool
    var stickFeel: StickFeelConfig
    var aim: AimConfig
    var delete: DeleteConfig
    var boostMultiplier: Double      // cursor speed with the scroll stick fully tilted while the cursor moves
    var touchpad: TouchpadConfig
    var keyRepeatDelay: Double
    var toggleHoldSeconds: Double    // how long to hold the pause button
    var keyRepeatInterval: Double
    var buttons: [String: String]    // Button name -> action string
    var layerButton: String          // the button that acts as Cmd (Р-30)
    var layer: [String: String]      // while layerButton is held these replace `buttons` (its Cmd is still added)
    var terminalApps: [String]       // bundle IDs where newLine is Option+Return

    static let `default` = Config(
        cursorStick: "left",
        scrollStick: "right",
        cursor: StickConfig(speed: 800, deadzone: 0.12, fineSpeed: 0.2),
        scroll: StickConfig(speed: 1800, deadzone: 0.15, fineSpeed: 0.1),
        invertScroll: false,
        stickFeel: StickFeelConfig(fineZone: 0.72, fineCurve: 1.5, outerCurve: 3,
                                   rimEnter: 0.9, rimExit: 0.8, rimHold: 0.3, rimRamp: 1.0, rimMax: 4),
        aim: AimConfig(zone: 0.54, resetTilt: 0.7, hold: 0.6, ramp: 0.8, minFactor: 0.65, maxPause: 3),
        delete: DeleteConfig(wordsAfter: 1.5, wordInterval: 0.15),
        boostMultiplier: 4.5,
        touchpad: TouchpadConfig(
            enabled: true, cursorSpeed: 0.7, scrollSpeed: 1.0, deadband: 3, smoothing: 0.35,
            click: "key:space",
            doubleClick: "newLine",
            twoFingerClick: "rightClick",
            longPress: "toggleKeyboard",
            longPressSeconds: 0.6,
            doubleClickSeconds: 0.35,
            oneFingerMode: "swipe",
            twoFingerMode: "swipe",
            swipeDistance: 300,
            // Same as four-finger swipes on a Mac trackpad ("left" = fingers move right-to-left).
            swipes: [
                "up": "key:ctrl+up",       // Mission Control
                "down": "key:ctrl+down",   // App Exposé
                "left": "key:ctrl+right",  // next Space / full-screen app
                "right": "key:ctrl+left",  // previous Space
            ]
        ),
        keyRepeatDelay: 0.4,
        toggleHoldSeconds: 1.0,
        keyRepeatInterval: 0.05,
        buttons: [
            "cross": "leftClick",
            "circle": "rightClick",
            "square": "key:return",
            "triangle": "key:escape",
            "l1": "none",
            "r1": "key:return",
            "l2": "key:tab",
            "r2": "key:backspace",
            "l3": "toggleEnabled",
            "r3": "middleClick",
            "share": "screenshotScreen",
            "options": "key:rcmd",   // held Cmd; right Cmd also starts dictation
            "ps": "none",
            "touchpad": "none",   // see touchpad.click
            "dpadUp": "key:up",
            "dpadDown": "key:down",
            "dpadLeft": "key:left",
            "dpadRight": "key:right",
        ],
        layerButton: "options",
        layer: [
            "l1": "key:grave",   // Options + L1 = Cmd+` — next window of the same app
            "share": "screenshotWindow",
            // Options is Cmd, so these become Cmd+C / Cmd+V / Cmd+X / Cmd+A.
            "square": "key:c",
            "circle": "key:v",
            "triangle": "key:x",
            "r3": "key:a",
        ],
        terminalApps: [
            "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.mitchellh.ghostty",
            "net.kovidgoyal.kitty", "io.alacritty", "org.alacritty", "com.github.wez.wezterm", "co.zeit.hyper",
        ]
    )

    static var defaultPath: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/ds4mouse/config.json")
    }

    /// Loads the user file on top of the defaults, so the file may contain only the keys you want to change.
    static func load(from url: URL) throws -> Config {
        guard FileManager.default.fileExists(atPath: url.path) else { return .default }
        let defaults = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Config.default)) as! [String: Any]
        guard let user = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] else {
            throw Action.ParseError(description: "\(url.path): ожидается JSON-объект")
        }
        let merged = deepMerge(defaults, user)
        let config = try JSONDecoder().decode(Config.self, from: JSONSerialization.data(withJSONObject: merged))
        _ = try config.resolvedButtons()   // fail early on typos
        _ = try config.resolvedSwipes()
        _ = try config.resolvedLayer()
        _ = try config.resolvedPadClicks()
        return config
    }

    func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try enc.encode(self).write(to: url)
    }

    func resolvedButtons() throws -> [Button: Action] {
        try Config.resolve(buttons)
    }

    private static func resolve(_ buttons: [String: String]) throws -> [Button: Action] {
        var result: [Button: Action] = [:]
        for (name, text) in buttons {
            guard let b = Button(rawValue: name) else {
                throw Action.ParseError(description: "неизвестная кнопка «\(name)». Доступны: \(Button.allCases.map(\.rawValue).joined(separator: " "))")
            }
            result[b] = try Action(parsing: text)
        }
        return result
    }

    func resolvedLayer() throws -> (button: Button, actions: [Button: Action]) {
        guard let b = Button(rawValue: layerButton) else {
            throw Action.ParseError(description: "неизвестная кнопка layerButton «\(layerButton)»")
        }
        return (b, try Config.resolve(layer))
    }

    func resolvedPadClicks() throws -> (click: Action, double: Action, twoFinger: Action, long: Action) {
        (try Action(parsing: touchpad.click), try Action(parsing: touchpad.doubleClick),
         try Action(parsing: touchpad.twoFingerClick), try Action(parsing: touchpad.longPress))
    }

    func resolvedSwipes() throws -> [String: Action] {
        var result: [String: Action] = [:]
        for (dir, text) in touchpad.swipes {
            guard ["up", "down", "left", "right"].contains(dir) else {
                throw Action.ParseError(description: "неизвестное направление «\(dir)». Доступны: up down left right")
            }
            result[dir] = try Action(parsing: text)
        }
        return result
    }

    private static func deepMerge(_ base: [String: Any], _ over: [String: Any]) -> [String: Any] {
        var out = base
        for (k, v) in over {
            if let b = base[k] as? [String: Any], let o = v as? [String: Any] { out[k] = deepMerge(b, o) }
            else { out[k] = v }
        }
        return out
    }
}
