import Foundation

struct StickConfig: Codable {
    var speed: Double      // pixels per second at full tilt
    var deadzone: Double   // 0...1, ignore tilt below this
    var curve: Double      // 1 = linear, >1 = finer control near center
}

struct TouchpadConfig: Codable {
    var enabled: Bool
    var cursorSpeed: Double          // screen pixels per touchpad unit
    var scrollSpeed: Double
    var deadband: Double             // touchpad units of finger wobble to ignore
    var smoothing: Double            // 0...1, lower = smoother but laggier
    var twoFingerClickIsRightClick: Bool
}

struct Config: Codable {
    var cursorStick: String          // "left" | "right" | "none"
    var scrollStick: String
    var cursor: StickConfig
    var scroll: StickConfig
    var invertScroll: Bool
    var precisionMultiplier: Double  // speed when L2 is fully pressed
    var boostMultiplier: Double      // speed when R2 is fully pressed
    var touchpad: TouchpadConfig
    var keyRepeatDelay: Double
    var keyRepeatInterval: Double
    var buttons: [String: String]    // Button name -> action string

    static let `default` = Config(
        cursorStick: "left",
        scrollStick: "right",
        cursor: StickConfig(speed: 800, deadzone: 0.12, curve: 2.2),
        scroll: StickConfig(speed: 1800, deadzone: 0.15, curve: 2.0),
        invertScroll: false,
        precisionMultiplier: 0.3,
        boostMultiplier: 6,
        touchpad: TouchpadConfig(enabled: true, cursorSpeed: 0.7, scrollSpeed: 1.0, deadband: 3, smoothing: 0.35, twoFingerClickIsRightClick: true),
        keyRepeatDelay: 0.4,
        keyRepeatInterval: 0.05,
        buttons: [
            "cross": "leftClick",
            "circle": "rightClick",
            "square": "key:cmd+tab",
            "triangle": "key:ctrl+up",
            "l1": "key:cmd+[",
            "r1": "key:cmd+]",
            "l2": "none",
            "r2": "none",
            "l3": "toggleEnabled",
            "r3": "middleClick",
            "share": "key:escape",
            "options": "key:return",
            "ps": "key:ropt",
            "touchpad": "leftClick",
            "dpadUp": "key:up",
            "dpadDown": "key:down",
            "dpadLeft": "key:left",
            "dpadRight": "key:right",
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
        return config
    }

    func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try enc.encode(self).write(to: url)
    }

    func resolvedButtons() throws -> [Button: Action] {
        var result: [Button: Action] = [:]
        for (name, text) in buttons {
            guard let b = Button(rawValue: name) else {
                throw Action.ParseError(description: "неизвестная кнопка «\(name)». Доступны: \(Button.allCases.map(\.rawValue).joined(separator: " "))")
            }
            result[b] = try Action(parsing: text)
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
