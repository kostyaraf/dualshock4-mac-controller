import CoreGraphics
import Foundation

/// Polls the controller ~125 times a second and turns its state into mouse and keyboard events.
final class Engine {
    private let config: Config
    private let actions: [Button: Action]
    private let swipeActions: [String: Action]
    private let input = GameControllerInput()
    private let raw = DS4RawReader()
    private let mouse = VirtualMouse()
    private let keyboard = VirtualKeyboard()
    private let dryRun: Bool

    private var enabled = true
    private var prev = ControllerState()
    private var held: [Button: Action] = [:]
    private var repeatAt: [Button: TimeInterval] = [:]
    private var toggleAt: [Button: TimeInterval] = [:]
    private var pressedAt: [Button: TimeInterval] = [:]
    private var lastTick = ProcessInfo.processInfo.systemUptime
    private var timer: Timer?

    /// dryRun: only print what is pressed, don't move the cursor or press anything.
    init(config: Config, dryRun: Bool) throws {
        self.config = config
        self.actions = try config.resolvedButtons()
        self.swipeActions = try config.resolvedSwipes()
        self.dryRun = dryRun
        mouse.modifiers = { [keyboard] in keyboard.heldModifiers }

        input.onConnect = { [weak self] c in
            log("Геймпад подключён: \(c.vendorName ?? "без названия")")
            self?.updateLight()
        }
        input.onDisconnect = { [weak self] c in
            log("Геймпад отключён: \(c.vendorName ?? "без названия")")
            self?.releaseAll()
        }
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 125, repeats: true) { [weak self] _ in self?.tick() }
    }

    func releaseAll() {
        for (b, a) in held { perform(a, button: b, down: false) }
        held.removeAll()
        repeatAt.removeAll()
        mouse.releaseAll()
    }

    // MARK: - Tick

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = min(now - lastTick, 0.05)
        lastTick = now

        var s = ControllerState()
        input.read(into: &s)
        if raw.isActive {
            s.touches = raw.touches
            // The raw report is the source of truth for PS: through GameController the system
            // may swallow its release, leaving Cmd stuck.
            if raw.psPressed { s.buttons.insert(.ps) } else { s.buttons.remove(.ps) }
        }

        handleButtons(s, now: now)
        if enabled {
            handleSticks(s, dt: dt)
            handleTouchpad(s)
        }
        prev = s
    }

    private func handleButtons(_ s: ControllerState, now: TimeInterval) {
        for b in Button.allCases {
            let isDown = s.buttons.contains(b), wasDown = prev.buttons.contains(b)
            if isDown && !wasDown {
                var a = actions[b] ?? .none
                if b == .touchpad, config.touchpad.twoFingerClickIsRightClick, s.touches.count >= 2, a == .leftClick {
                    a = .rightClick
                }
                if a == .toggleEnabled {
                    // Pause only on a deliberate hold, so a stray stick click doesn't stop everything.
                    toggleAt[b] = now + config.toggleHoldSeconds
                    continue
                }
                guard enabled else { continue }
                held[b] = a
                pressedAt[b] = now
                perform(a, button: b, down: true)
                if case .key(let k) = a, k.heldFlags == nil { repeatAt[b] = now + config.keyRepeatDelay }
            } else if !isDown && wasDown {
                if let a = held.removeValue(forKey: b) { perform(a, button: b, down: false) }
                repeatAt[b] = nil
                toggleAt[b] = nil
            } else if isDown, let t = toggleAt[b], now >= t {
                toggleAt[b] = nil
                perform(.toggleEnabled, button: b, down: true)
            } else if isDown, let t = repeatAt[b], now >= t, case .key(let k)? = held[b] {
                let heldFor = now - (pressedAt[b] ?? now)
                if k.keyCode == backspaceKey, !k.flags.contains(.maskAlternate), heldFor >= config.delete.wordsAfter {
                    // Long hold on Backspace: delete whole words (Option+Backspace), like on iPhone.
                    let word = KeyCombo(keyCode: backspaceKey, flags: k.flags.union(.maskAlternate))
                    if !dryRun { keyboard.key(word, down: true); keyboard.key(word, down: false) }
                    repeatAt[b] = now + config.delete.wordInterval
                } else {
                    if !dryRun { keyboard.key(k, down: true) }
                    repeatAt[b] = now + config.keyRepeatInterval
                }
            }
        }
    }

    private func perform(_ a: Action, button: Button, down: Bool) {
        if dryRun && a != .toggleEnabled {
            if down { log("\(button.rawValue) → \(a)") }
            return
        }
        switch a {
        case .none: break
        case .leftClick: mouse.button(.left, down: down)
        case .rightClick: mouse.button(.right, down: down)
        case .middleClick: mouse.button(.middle, down: down)
        case .key(let k):
            keyboard.key(k, down: down)
        case .toggleEnabled:
            guard down else { return }
            releaseAll()
            enabled.toggle()
            log(enabled ? "Управление включено" : "Управление на паузе")
            updateLight()
        }
    }

    /// What the second stick does. Decided once, when it leaves the center, and kept until it returns:
    /// if the cursor stick is already moving, the second stick speeds the cursor up; otherwise it scrolls.
    private enum SecondStickRole { case idle, scroll, boost }
    private var secondStickRole = SecondStickRole.idle

    private func handleSticks(_ s: ControllerState, dt: Double) {
        let cursorRaw = stick(config.cursorStick, s)
        let secondRaw = stick(config.scrollStick, s)
        let secondTilt = tilt(secondRaw, deadzone: config.scroll.deadzone)

        if secondTilt == 0 { secondStickRole = .idle }
        else if secondStickRole == .idle {
            secondStickRole = tilt(cursorRaw, deadzone: config.cursor.deadzone) > 0 ? .boost : .scroll
        }

        // Boost grows smoothly with how far the second stick is tilted.
        let boost = secondStickRole == .boost ? 1 + (config.boostMultiplier - 1) * secondTilt : 1
        let c = cursorResponse(cursorRaw, now: lastTick)
        let k = config.cursor.speed * dt * boost
        if !dryRun { mouse.move(dx: c.x * k, dy: -c.y * k) }

        guard secondStickRole == .scroll else { return }
        let sc = shape(secondRaw, config.scroll)
        let ks = config.scroll.speed * dt * (config.invertScroll ? -1 : 1)
        if !dryRun { mouse.scroll(dx: -sc.x * ks, dy: sc.y * ks) }
    }

    /// Finger position filter: `anchor` ignores small wobble (deadband), `smooth` removes jerks.
    private var touchAnchor = Vec2()
    private var touchSmooth = Vec2()

    private func handleTouchpad(_ s: ControllerState) {
        guard config.touchpad.enabled else { return }
        let now = s.touches, before = prev.touches
        guard !now.isEmpty else { return }
        let raw = Vec2(x: now.map(\.x).reduce(0, +) / Double(now.count),
                       y: now.map(\.y).reduce(0, +) / Double(now.count))

        // New touch or finger count changed: start fresh, don't jump.
        guard now.count == before.count, now[0].id == before[0].id else {
            touchAnchor = raw
            touchSmooth = raw
            swipeStart = raw
            swipeDone = false
            return
        }

        let mode = now.count == 1 ? config.touchpad.oneFingerMode : config.touchpad.twoFingerMode
        if mode == "swipe" {
            detectSwipe(raw)
            return
        }

        // Anchor trails the finger by `deadband`: tiny wobble doesn't move it, real motion does.
        let off = Vec2(x: raw.x - touchAnchor.x, y: raw.y - touchAnchor.y)
        let band = config.touchpad.deadband
        if off.length > band {
            let k = (off.length - band) / off.length
            touchAnchor.x += off.x * k
            touchAnchor.y += off.y * k
        }
        let a = config.touchpad.smoothing
        let dx = (touchAnchor.x - touchSmooth.x) * a
        let dy = (touchAnchor.y - touchSmooth.y) * a
        touchSmooth.x += dx
        touchSmooth.y += dy

        if dryRun { return }
        if now.count == 1 {
            let k = config.touchpad.cursorSpeed
            mouse.move(dx: dx * k, dy: dy * k)
        } else {
            // Content follows the fingers, like on a Mac trackpad.
            let k = config.touchpad.scrollSpeed * (config.invertScroll ? -1 : 1)
            mouse.scroll(dx: dx * k, dy: dy * k)
        }
    }

    private var swipeStart = Vec2()
    private var swipeDone = false

    /// One action per touch, once the fingers have travelled far enough in one direction.
    private func detectSwipe(_ p: Vec2) {
        guard !swipeDone else { return }
        let dx = p.x - swipeStart.x, dy = p.y - swipeStart.y
        guard max(abs(dx), abs(dy)) >= config.touchpad.swipeDistance else { return }
        swipeDone = true
        // Pad y grows downward, so fingers moving up give negative dy.
        let dir = abs(dx) > abs(dy) ? (dx > 0 ? "right" : "left") : (dy < 0 ? "up" : "down")
        guard let a = swipeActions[dir], a != .none else { return }
        log("Жест на тачпаде: \(dir)")
        perform(a, button: .touchpad, down: true)
        perform(a, button: .touchpad, down: false)
    }

    // MARK: - Helpers

    private func stick(_ name: String, _ s: ControllerState) -> Vec2 {
        switch name {
        case "left": s.leftStick
        case "right": s.rightStick
        default: Vec2()
        }
    }

    /// When the cursor stick reached the rim, nil while it's not there.
    private var atRimSince: TimeInterval?

    /// Cursor stick → velocity (fraction of full speed, can exceed 1 with the rim boost).
    /// A wide slow center for precision, a steep rise near the rim, and if the stick is held
    /// at the rim the speed keeps growing: the user clearly wants to travel far. See SPEC.md, Р-13.
    private func cursorResponse(_ v: Vec2, now: TimeInterval) -> Vec2 {
        let f = config.cursorFeel
        let n = tilt(v, deadzone: config.cursor.deadzone)
        guard n > 0 else { atRimSince = nil; return Vec2() }

        // Along the rim, moving from "up" to "right" doesn't reset the boost — only easing off does.
        if n >= f.edgeEnter { atRimSince = atRimSince ?? now }
        else if n < f.edgeExit { atRimSince = nil }

        var speed = f.fineShare * pow(n, f.fineCurve) + (1 - f.fineShare) * pow(n, f.edgeCurve)
        if let since = atRimSince {
            let x = min(max((now - since - f.edgeHold) / f.edgeRamp, 0), 1)
            speed *= 1 + (f.edgeMax - 1) * x * x * (3 - 2 * x)   // smooth start and finish
        }
        let mag = v.length
        return Vec2(x: v.x / mag * speed, y: v.y / mag * speed)
    }

    /// 0 inside the deadzone, then grows linearly to 1 at full tilt.
    private func tilt(_ v: Vec2, deadzone: Double) -> Double {
        let mag = v.length
        return mag > deadzone ? min((mag - deadzone) / (1 - deadzone), 1) : 0
    }

    /// Radial deadzone + response curve: small tilts give fine movement, full tilt gives full speed.
    private func shape(_ v: Vec2, _ c: StickConfig) -> Vec2 {
        let mag = v.length
        guard mag > c.deadzone else { return Vec2() }
        let norm = min((mag - c.deadzone) / (1 - c.deadzone), 1)
        let scaled = pow(norm, c.curve)
        return Vec2(x: v.x / mag * scaled, y: v.y / mag * scaled)
    }

    private func updateLight() {
        if enabled { input.setLight(red: 0, green: 1, blue: 0.15) }
        else { input.setLight(red: 1, green: 0.25, blue: 0) }
    }
}

private let backspaceKey: CGKeyCode = 51

func log(_ text: String) {
    let t = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
    print("[\(t)] \(text)")
    fflush(stdout)
}
