import AppKit
import Foundation

/// Polls the controller ~125 times a second and turns its state into mouse and keyboard events.
final class Engine {
    private let config: Config
    private let actions: [Button: Action]
    private let swipeActions: [String: Action]
    private let layer: (button: Button, actions: [Button: Action])
    private let padClicks: (click: Action, double: Action, twoFinger: Action, long: Action)
    private let input = GameControllerInput()
    private let raw = DS4RawReader()
    private let mouse = VirtualMouse()
    private let keyboard = VirtualKeyboard()
    private let osk = OnScreenKeyboard()
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
        self.layer = try config.resolvedLayer()
        self.padClicks = try config.resolvedPadClicks()
        self.dryRun = dryRun
        mouse.modifiers = { [keyboard] in keyboard.heldModifiers }
        osk.type = { [keyboard, dryRun] text in
            if dryRun { log("клавиатура: \(text)") } else { keyboard.type(text) }
        }

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
        let t = Timer(timeInterval: 1.0 / 125, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
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
        if enabled { handlePadClick(s, now: now) }
        if enabled && osk.isVisible { handleKeyboardNav(s, now: now) }
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
                if osk.isVisible, !s.buttons.contains(layer.button), let k = oskAction(b) {
                    k()
                    navRepeatAt = now + config.keyRepeatDelay
                    continue
                }
                let a = (b != layer.button && s.buttons.contains(layer.button) ? layer.actions[b] : nil) ?? actions[b] ?? .none
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
        case .newLine:
            guard down else { return }
            let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
            let mod: CGEventFlags = config.terminalApps.contains(app) ? .maskAlternate : .maskShift
            let combo = KeyCombo(keyCode: returnKey, flags: mod)
            keyboard.key(combo, down: true)
            keyboard.key(combo, down: false)
        case .screenshotScreen, .screenshotWindow:
            guard down else { return }
            // System shortcuts: Ctrl+Cmd+Shift+3 (screen) / +4 (area) copy to the clipboard instead of a file.
            let combo = KeyCombo(keyCode: a == .screenshotScreen ? 20 : 21,
                                 flags: [.maskControl, .maskCommand, .maskShift])
            keyboard.key(combo, down: true)
            keyboard.key(combo, down: false)
            if a == .screenshotWindow {
                // Space switches the area picker to "pick a window". Without Cmd: PS may still be held,
                // and Cmd+Space would be Spotlight.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [keyboard] in
                    keyboard.tapIgnoringHeld(KeyCombo(keyCode: 49, flags: []))
                }
            }
        case .toggleKeyboard:
            guard down else { return }
            osk.toggle()
            updateLight()
        case .toggleEnabled:
            guard down else { return }
            releaseAll()
            osk.hide()
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
        // While our keyboard is open the cursor stick moves the highlighted key instead.
        let cursorRaw = osk.isVisible ? Vec2() : stick(config.cursorStick, s)
        let secondRaw = stick(config.scrollStick, s)
        let secondTilt = tilt(secondRaw, deadzone: config.scroll.deadzone)

        if secondTilt == 0 { secondStickRole = .idle }
        else if secondStickRole == .idle {
            secondStickRole = tilt(cursorRaw, deadzone: config.cursor.deadzone) > 0 ? .boost : .scroll
        }

        // Boost grows smoothly with how far the second stick is tilted.
        let boost = secondStickRole == .boost ? 1 + (config.boostMultiplier - 1) * secondTilt : 1
        let c = response(cursorRaw, config.cursor, rimSince: &cursorRimSince, now: lastTick)
        let aim = aimFactor(tilt(cursorRaw, deadzone: config.cursor.deadzone), atRim: cursorRimSince != nil, dt: dt)
        let k = config.cursor.speed * dt * boost * aim
        if !dryRun { mouse.move(dx: c.x * k, dy: -c.y * k) }

        guard secondStickRole == .scroll else { scrollRimSince = nil; return }
        let sc = response(secondRaw, config.scroll, rimSince: &scrollRimSince, now: lastTick)
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

    // MARK: - On-screen keyboard

    /// Buttons that do something else while the keyboard is open (without the Cmd button). See SPEC.md, Р-25.
    private func oskAction(_ b: Button) -> (() -> Void)? {
        switch b {
        case .cross: osk.pressSelected
        case .square: osk.toggleShift
        case .triangle: osk.nextPage
        case .circle: { [self] in osk.hide(); updateLight() }
        case .dpadUp: { [osk] in osk.move(dx: 0, dy: -1) }
        case .dpadDown: { [osk] in osk.move(dx: 0, dy: 1) }
        case .dpadLeft: { [osk] in osk.move(dx: -1, dy: 0) }
        case .dpadRight: { [osk] in osk.move(dx: 1, dy: 0) }
        default: nil
        }
    }

    private var navDir: (dx: Int, dy: Int)?
    private var navRepeatAt: TimeInterval = 0

    /// Left stick moves the highlight one key per push, repeating while held. D-pad repeats too.
    private func handleKeyboardNav(_ s: ControllerState, now: TimeInterval) {
        var dir: (dx: Int, dy: Int)?
        let v = stick(config.cursorStick, s)
        if v.length > 0.5 {
            dir = abs(v.x) > abs(v.y) ? (v.x > 0 ? 1 : -1, 0) : (0, v.y > 0 ? -1 : 1)
        } else if s.buttons.contains(.dpadUp) { dir = (0, -1) }
        else if s.buttons.contains(.dpadDown) { dir = (0, 1) }
        else if s.buttons.contains(.dpadLeft) { dir = (-1, 0) }
        else if s.buttons.contains(.dpadRight) { dir = (1, 0) }

        guard let d = dir else { navDir = nil; return }
        let isDpad = v.length <= 0.5
        if let old = navDir, old == d {
            guard now >= navRepeatAt else { return }
            osk.move(dx: d.dx, dy: d.dy)
            navRepeatAt = now + 0.09
        } else {
            navDir = d
            // The D-pad press itself already moved once (in handleButtons).
            if !isDpad { osk.move(dx: d.dx, dy: d.dy) }
            navRepeatAt = now + 0.35
        }
    }

    // MARK: - Touchpad press: space / new line

    private var lastPadPressAt: TimeInterval?
    /// Set while a one-finger press that typed the click action is held, until it becomes a long press.
    private var padLongPressAt: TimeInterval?

    /// Each press of the pad = click action (space), at once. A second quick press turns it into
    /// the double-click action, holding it turns it into the long-press action (on-screen keyboard);
    /// either way Backspace first removes the space the press already typed. See SPEC.md, Р-18, Р-20.
    private func handlePadClick(_ s: ControllerState, now: TimeInterval) {
        let down = s.buttons.contains(.touchpad), was = prev.buttons.contains(.touchpad)
        if !down { padLongPressAt = nil; return }
        if was {
            if let t = padLongPressAt, now >= t {
                padLongPressAt = nil
                lastPadPressAt = nil
                undoClick()
                fire(padClicks.long)
            }
            return
        }
        if s.touches.count >= 2 {
            lastPadPressAt = nil
            fire(padClicks.twoFinger)
            return
        }
        if let last = lastPadPressAt, now - last <= config.touchpad.doubleClickSeconds, padClicks.double != .none {
            lastPadPressAt = nil
            undoClick()
            fire(padClicks.double)
        } else {
            lastPadPressAt = now
            fire(padClicks.click)
            if padClicks.long != .none { padLongPressAt = now + config.touchpad.longPressSeconds }
        }
    }

    /// Removes what the click action typed, when it types something.
    private func undoClick() {
        if case .key = padClicks.click { fire(.key(KeyCombo(keyCode: backspaceKey, flags: []))) }
    }

    private func fire(_ a: Action) {
        guard a != .none else { return }
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

    /// Seconds spent gently moving the cursor (pauses not counted) and the length of the current pause.
    private var aimTime = 0.0
    private var aimPause = 0.0

    /// 1 normally; eases down to `aim.minFactor` once the user has been nudging the cursor gently for a while.
    /// The mirror image of the rim boost, except that short pauses keep it: aiming is stop-and-go. Р-26.
    /// The rim boost always wins: at the rim aiming ends at once, whatever the settings (Р-29).
    private func aimFactor(_ n: Double, atRim: Bool, dt: Double) -> Double {
        let a = config.aim
        if atRim {
            aimTime = 0
            aimPause = 0
        } else if n == 0 {
            aimPause += dt
            if aimPause > a.maxPause { aimTime = 0 }
        } else if n > a.resetTilt {
            aimTime = 0
            aimPause = 0
        } else {
            aimPause = 0
            if n <= a.zone { aimTime += dt }
        }
        let x = min(max((aimTime - a.hold) / a.ramp, 0), 1)
        return 1 - (1 - a.minFactor) * x * x * (3 - 2 * x)
    }

    /// When each stick reached the rim, nil while it's not there.
    private var cursorRimSince: TimeInterval?
    private var scrollRimSince: TimeInterval?

    /// Stick → velocity (fraction of full speed, can exceed 1 with the rim boost).
    /// A wide slow center for precision, a steep rise near the rim, and if the stick is held
    /// at the rim the speed keeps growing: the user clearly wants to travel far. See SPEC.md, Р-13, Р-21.
    private func response(_ v: Vec2, _ c: StickConfig, rimSince: inout TimeInterval?, now: TimeInterval) -> Vec2 {
        let f = config.stickFeel
        let n = tilt(v, deadzone: c.deadzone)
        guard n > 0 else { rimSince = nil; return Vec2() }

        // Along the rim, moving from "up" to "right" doesn't reset the boost — only easing off does.
        if n >= f.rimEnter { rimSince = rimSince ?? now }
        else if n < f.rimExit { rimSince = nil }

        var speed: Double
        let r = f.fineZone, s = c.fineSpeed
        if n <= r {
            speed = s * pow(n / r, f.fineCurve)
        } else {
            // Starts with the same slope the center ended with (no kink), then bends up to 1 at full tilt.
            let t = (n - r) / (1 - r)
            let lin = min(s * f.fineCurve * (1 - r) / (r * (1 - s)), 1)
            speed = s + (1 - s) * (lin * t + (1 - lin) * pow(t, f.outerCurve))
        }
        if let since = rimSince {
            let x = min(max((now - since - f.rimHold) / f.rimRamp, 0), 1)
            speed *= 1 + (f.rimMax - 1) * x * x * (3 - 2 * x)   // smooth start and finish
        }
        let mag = v.length
        return Vec2(x: v.x / mag * speed, y: v.y / mag * speed)
    }

    /// 0 inside the deadzone, then grows linearly to 1 at full tilt.
    private func tilt(_ v: Vec2, deadzone: Double) -> Double {
        let mag = v.length
        return mag > deadzone ? min((mag - deadzone) / (1 - deadzone), 1) : 0
    }

    private func updateLight() {
        if enabled && osk.isVisible { input.setLight(red: 0, green: 0.3, blue: 1) }
        else if enabled { input.setLight(red: 0, green: 1, blue: 0.15) }
        else { input.setLight(red: 1, green: 0.25, blue: 0) }
    }
}

private let backspaceKey: CGKeyCode = 51
private let returnKey: CGKeyCode = 36

func log(_ text: String) {
    let t = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
    print("[\(t)] \(text)")
    fflush(stdout)
}
