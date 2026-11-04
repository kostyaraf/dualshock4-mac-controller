import Foundation

/// Polls the controller ~125 times a second and turns its state into mouse and keyboard events.
final class Engine {
    private let config: Config
    private let actions: [Button: Action]
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
    private var lastTick = ProcessInfo.processInfo.systemUptime
    private var timer: Timer?

    /// dryRun: only print what is pressed, don't move the cursor or press anything.
    init(config: Config, dryRun: Bool) throws {
        self.config = config
        self.actions = try config.resolvedButtons()
        self.dryRun = dryRun

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
            if raw.psPressed { s.buttons.insert(.ps) }
        }

        handleButtons(s, now: now)
        if enabled {
            let f = speedFactor(s)
            handleSticks(s, dt: dt, speedFactor: f)
            handleTouchpad(s, speedFactor: f)
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
                if !dryRun { keyboard.key(k, down: true) }
                repeatAt[b] = now + config.keyRepeatInterval
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
        case .key(let k): keyboard.key(k, down: down)
        case .toggleEnabled:
            guard down else { return }
            releaseAll()
            enabled.toggle()
            log(enabled ? "Управление включено" : "Управление на паузе")
            updateLight()
        }
    }

    /// L2 slows down, R2 speeds up, both proportionally to how far the trigger is pressed.
    private func speedFactor(_ s: ControllerState) -> Double {
        (1 + (config.precisionMultiplier - 1) * s.l2) * (1 + (config.boostMultiplier - 1) * s.r2)
    }

    private func handleSticks(_ s: ControllerState, dt: Double, speedFactor: Double) {
        let c = shape(stick(config.cursorStick, s), config.cursor)
        let k = config.cursor.speed * dt * speedFactor
        if !dryRun { mouse.move(dx: c.x * k, dy: -c.y * k) }

        let sc = shape(stick(config.scrollStick, s), config.scroll)
        let ks = config.scroll.speed * dt * speedFactor * (config.invertScroll ? -1 : 1)
        if !dryRun { mouse.scroll(dx: -sc.x * ks, dy: sc.y * ks) }
    }

    /// Finger position filter: `anchor` ignores small wobble (deadband), `smooth` removes jerks.
    private var touchAnchor = Vec2()
    private var touchSmooth = Vec2()

    private func handleTouchpad(_ s: ControllerState, speedFactor: Double) {
        guard config.touchpad.enabled else { return }
        let now = s.touches, before = prev.touches
        guard !now.isEmpty else { return }
        let raw = Vec2(x: now.map(\.x).reduce(0, +) / Double(now.count),
                       y: now.map(\.y).reduce(0, +) / Double(now.count))

        // New touch or finger count changed: start fresh, don't jump.
        guard now.count == before.count, now[0].id == before[0].id else {
            touchAnchor = raw
            touchSmooth = raw
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
            let k = config.touchpad.cursorSpeed * speedFactor
            mouse.move(dx: dx * k, dy: dy * k)
        } else {
            // Content follows the fingers, like on a Mac trackpad.
            let k = config.touchpad.scrollSpeed * (config.invertScroll ? -1 : 1)
            mouse.scroll(dx: dx * k, dy: dy * k)
        }
    }

    // MARK: - Helpers

    private func stick(_ name: String, _ s: ControllerState) -> Vec2 {
        switch name {
        case "left": s.leftStick
        case "right": s.rightStick
        default: Vec2()
        }
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

func log(_ text: String) {
    let t = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
    print("[\(t)] \(text)")
    fflush(stdout)
}
