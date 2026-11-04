import CoreGraphics

struct KeyCombo: Equatable {
    var keyCode: CGKeyCode
    var flags: CGEventFlags
}

/// What a button does. Written in the config as a string:
/// "leftClick", "rightClick", "middleClick", "toggleEnabled", "none", or "key:cmd+shift+t".
enum Action: Equatable {
    case none
    case leftClick, rightClick, middleClick
    case key(KeyCombo)
    case toggleEnabled

    struct ParseError: Error, CustomStringConvertible { let description: String }

    init(parsing text: String) throws {
        switch text {
        case "none", "": self = .none
        case "leftClick": self = .leftClick
        case "rightClick": self = .rightClick
        case "middleClick": self = .middleClick
        case "toggleEnabled": self = .toggleEnabled
        default:
            guard text.hasPrefix("key:") else {
                throw ParseError(description: "неизвестное действие «\(text)». Варианты: leftClick, rightClick, middleClick, toggleEnabled, none, key:<клавиши>")
            }
            self = .key(try Self.parseKeys(String(text.dropFirst(4))))
        }
    }

    private static func parseKeys(_ text: String) throws -> KeyCombo {
        var parts = text.lowercased().split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        // "cmd++" means cmd + the "+" key is not supported; "=" is the same physical key.
        guard let keyName = parts.popLast(), let code = keyCodes[keyName] else {
            throw ParseError(description: "неизвестная клавиша в «\(text)». Доступны: \(keyCodes.keys.sorted().joined(separator: " "))")
        }
        var flags: CGEventFlags = []
        for m in parts {
            guard let f = modifiers[m] else {
                throw ParseError(description: "неизвестный модификатор «\(m)» в «\(text)». Доступны: cmd ctrl alt shift fn")
            }
            flags.insert(f)
        }
        // Real arrow keys always carry these flags; some system shortcuts (Mission Control) need them.
        if (123...126).contains(code) { flags.formUnion([.maskSecondaryFn, .maskNumericPad]) }
        return KeyCombo(keyCode: code, flags: flags)
    }

    private static let modifiers: [String: CGEventFlags] = [
        "cmd": .maskCommand, "command": .maskCommand,
        "ctrl": .maskControl, "control": .maskControl,
        "alt": .maskAlternate, "opt": .maskAlternate, "option": .maskAlternate,
        "shift": .maskShift, "fn": .maskSecondaryFn,
    ]

    // macOS virtual key codes (ANSI layout).
    private static let keyCodes: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26,
        "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35,
        "return": 36, "enter": 36, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42,
        ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, "tab": 48, "space": 49, "`": 50,
        "delete": 51, "backspace": 51, "escape": 53, "esc": 53,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100,
        "f9": 101, "f10": 109, "f11": 103, "f12": 111,
        "home": 115, "pageup": 116, "forwarddelete": 117, "end": 119, "pagedown": 121,
        "left": 123, "right": 124, "down": 125, "up": 126,
    ]
}
