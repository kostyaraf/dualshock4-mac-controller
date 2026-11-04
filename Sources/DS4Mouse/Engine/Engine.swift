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
        input.onDisconnect = { [weak self] in
            log("Геймпад отключён")
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
        if raw.isActive { s.touches = raw.touches }

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
                guard enabled || a == .toggleEnabled else { continue }
                held[b] = a
                perform(a, button: b, down: true)
                if case .key = a { repeatAt[b] = now + config.keyRepeatDelay }
            } else if !isDown && wasDown {
                if let a = held.removeValue(forKey: b) { perform(a, button: b, down: false) }
                repeatAt[b] = nil
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

    private func handleSticks(_ s: ControllerState, dt: Double) {
        var speedFactor = 1.0
        speedFactor *= 1 + (config.precisionMultiplier - 1) * s.l2
        speedFactor *= 1 + (config.boostMultiplier - 1) * s.r2

        let c = shape(stick(config.cursorStick, s), config.cursor)
        let k = config.cursor.speed * dt * speedFactor
        if !dryRun { mouse.move(dx: c.x * k, dy: -c.y * k) }

        let sc = shape(stick(config.scrollStick, s), config.scroll)
        let ks = config.scroll.speed * dt * speedFactor * (config.invertScroll ? -1 : 1)
        if !dryRun { mouse.scroll(dx: -sc.x * ks, dy: sc.y * ks) }
    }

    private func handleTouchpad(_ s: ControllerState) {
        guard config.touchpad.enabled else { return }
        let now = s.touches, before = prev.touches
        guard !now.isEmpty, now.count == before.count, now[0].id == before[0].id else { return }

        let dx = now.indices.map { now[$0].x - before[$0].x }.reduce(0, +) / Double(now.count)
        let dy = now.indices.map { now[$0].y - before[$0].y }.reduce(0, +) / Double(now.count)
        if dryRun { return }
        if now.count == 1 {
            mouse.move(dx: dx * config.touchpad.cursorSpeed, dy: dy * config.touchpad.cursorSpeed)
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
        if enabled { input.setLight(red: 0, green: 0.3, blue: 1) }
        else { input.setLight(red: 1, green: 0.25, blue: 0) }
    }
}

func log(_ text: String) {
    let t = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
    print("[\(t)] \(text)")
    fflush(stdout)
}
