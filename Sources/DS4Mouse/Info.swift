import Foundation
import GameController
import IOKit.hid

/// `ds4mouse info`: what each connected controller can do and how good its connection is.
/// Don't touch the controllers while it runs: it also measures stick drift at rest.
final class ControllerInfo {
    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private var reports: [String: [TimeInterval]] = [:]
    private var buffers: [UnsafeMutablePointer<UInt8>] = []
    private var drift: [ObjectIdentifier: Double] = [:]
    private let seconds: Double

    init(seconds: Double) {
        self.seconds = seconds
        GCController.shouldMonitorBackgroundEvents = true
        GCController.startWirelessControllerDiscovery {}

        let matches: [[String: Int]] = [
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_GamePad],
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Joystick],
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        for d in (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? [] { attach(d) }
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    }

    private func attach(_ d: IOHIDDevice) {
        let name = Self.name(d)
        reports[name] = []
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024)
        buffers.append(buf)
        let ctx = Unmanaged.passRetained(Box(owner: self, name: name)).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(d, buf, 1024, { ctx, _, _, _, _, _, _ in
            let box = Unmanaged<Box>.fromOpaque(ctx!).takeUnretainedValue()
            box.owner?.reports[box.name, default: []].append(ProcessInfo.processInfo.systemUptime)
        }, ctx)
    }

    private final class Box {
        weak var owner: ControllerInfo?
        let name: String
        init(owner: ControllerInfo, name: String) { self.owner = owner; self.name = name }
    }

    func run() {
        print("Измеряю \(Int(seconds)) с. Не трогайте геймпады.\n")
        let start = ProcessInfo.processInfo.systemUptime
        Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [self] t in
            for c in GCController.controllers() {
                guard let pad = c.extendedGamepad else { continue }
                let s = GameControllerInput.state(of: pad)
                let m = max(s.leftStick.length, s.rightStick.length)
                drift[ObjectIdentifier(c), default: 0] = max(drift[ObjectIdentifier(c)] ?? 0, m)
            }
            if ProcessInfo.processInfo.systemUptime - start > seconds { t.invalidate(); report(); exit(0) }
        }
    }

    private func report() {
        let controllers = GCController.controllers()
        if controllers.isEmpty { print("Геймпадов не найдено.") }
        for c in controllers {
            print("■ \(c.vendorName ?? "без названия") — \(c.productCategory)")
            let pad = c.extendedGamepad
            print("  полный набор кнопок и стиков: \(pad != nil ? "да" : "нет")")
            print("  тачпад: \(pad is GCDualShockGamepad || pad is GCDualSenseGamepad ? "да" : "нет")")
            print("  гироскоп: \(c.motion?.hasRotationRate == true ? "да" : "нет")")
            print("  вибрация: \(c.haptics != nil ? "да" : "нет"), подсветка: \(c.light != nil ? "да" : "нет")")
            print("  батарея: \(c.battery.map { "\(Int($0.batteryLevel * 100))%" } ?? "не сообщает")")
            print("  кнопка PS/Home: \(pad?.buttonHome != nil ? "есть" : "нет")")
            print(String(format: "  дрейф стиков в покое: %.3f (меньше 0.05 — хорошо)", drift[ObjectIdentifier(c)] ?? 0))
        }
        print("\nСвязь (сырые пакеты):")
        for (name, times) in reports.sorted(by: { $0.key < $1.key }) {
            guard times.count > 2 else { print("  \(name): пакетов нет (шлёт только при изменениях или не отвечает)"); continue }
            let gaps = zip(times.dropFirst(), times).map { $0 - $1 }.sorted()
            let rate = Double(times.count) / seconds
            let median = gaps[gaps.count / 2] * 1000
            let worst = gaps.last! * 1000
            print(String(format: "  %@: %.0f пакетов/с, обычный интервал %.1f мс, худшая пауза %.0f мс", name, rate, median, worst))
        }
    }

    private static func name(_ d: IOHIDDevice) -> String {
        let product = IOHIDDeviceGetProperty(d, kIOHIDProductKey as CFString) as? String ?? "?"
        let transport = IOHIDDeviceGetProperty(d, kIOHIDTransportKey as CFString) as? String ?? "?"
        return "\(product) [\(transport)]"
    }
}
