import Foundation
import IOKit.hid

/// Reads DualShock 4 reports directly over HID to get touchpad fingers.
/// GameController gives touchpad coordinates but not whether a finger is actually down,
/// so for trackpad-like behaviour we parse the raw report ourselves.
final class DS4RawReader {
    private let manager: IOHIDManager
    private var buffers: [UnsafeMutablePointer<UInt8>] = []
    private(set) var touches: [Touch] = []
    /// PS button. macOS often swallows it before GameController apps see it, so read it raw.
    private(set) var psPressed = false
    private var lastReport = Date.distantPast

    var isActive: Bool { Date().timeIntervalSince(lastReport) < 0.5 }

    init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        // Sony vendor ID. Most clones report it as well.
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: 0x054C] as CFDictionary)

        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { ctx, _, _, device in
            Unmanaged<DS4RawReader>.fromOpaque(ctx!).takeUnretainedValue().attach(device)
        }, ctx)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    private func attach(_ device: IOHIDDevice) {
        let size = 600
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        buffers.append(buffer)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, buffer, size, { ctx, _, _, _, id, report, length in
            Unmanaged<DS4RawReader>.fromOpaque(ctx!).takeUnretainedValue().handle(id: id, report: report, length: length)
        }, ctx)
    }

    private func handle(id: UInt32, report r: UnsafeMutablePointer<UInt8>, length: CFIndex) {
        // Bluetooth extended report 0x11 has the same layout as USB report 0x01, shifted by 2 bytes.
        let base: Int
        if id == 0x11 && length >= 45 { base = 2 }
        else if id == 0x01 && length >= 43 { base = 0 }
        else { return }   // basic Bluetooth report: no touchpad data

        psPressed = r[base + 7] & 0x01 != 0

        var found: [Touch] = []
        for offset in [35, 39] {
            let p = base + offset
            guard r[p] & 0x80 == 0 else { continue }   // high bit set = finger not touching
            let x = Int(r[p + 1]) | (Int(r[p + 2] & 0x0F) << 8)
            let y = (Int(r[p + 2]) >> 4) | (Int(r[p + 3]) << 4)
            found.append(Touch(id: Int(r[p] & 0x7F), x: Double(x), y: Double(y)))
        }
        touches = found
        lastReport = Date()
    }
}
