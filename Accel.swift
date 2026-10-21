import Foundation
import IOKit
import IOKit.hid

/// Reads the undocumented Apple Silicon accelerometer (AppleSPUHIDDevice, usage page 0xFF00 / usage 3)
/// and reports slaps: sudden spikes in acceleration magnitude above the gravity baseline.
final class Accelerometer {
    var onSample: ((Double, Double, Double) -> Void)?
    var onSlap: ((Double) -> Void)?           // strength in g above baseline
    var threshold: Double = 0.35              // g
    var cooldown: TimeInterval = 0.35

    private var manager: IOHIDManager?
    private var reportBuffer = [UInt8](repeating: 0, count: 64)
    private var baseline: Double = 1.0
    private var lastSlap = Date.distantPast

    static func isAvailable() -> Bool {
        let match = IOServiceMatching("AppleSPUHIDDevice")
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, match, &iter) == KERN_SUCCESS else { return false }
        defer { IOObjectRelease(iter) }
        while case let s = IOIteratorNext(iter), s != 0 {
            defer { IOObjectRelease(s) }
            if let u = IORegistryEntryCreateCFProperty(s, "PrimaryUsage" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? Int, u == 3 { return true }
        }
        return false
    }

    /// The SPU driver keeps sensors asleep until reporting is switched on.
    private func wakeSensors() {
        let match = IOServiceMatching("AppleSPUHIDDriver")
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, match, &iter) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iter) }
        while case let s = IOIteratorNext(iter), s != 0 {
            IORegistryEntrySetCFProperty(s, "SensorPropertyReportingState" as CFString, 1 as CFNumber)
            IORegistryEntrySetCFProperty(s, "SensorPropertyPowerState" as CFString, 1 as CFNumber)
            IORegistryEntrySetCFProperty(s, "ReportInterval" as CFString, 10000 as CFNumber) // µs → 100 Hz
            IOObjectRelease(s)
        }
    }

    func start() -> Bool {
        wakeSensors()
        let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(m, [kIOHIDPrimaryUsagePageKey: 0xFF00, kIOHIDPrimaryUsageKey: 3] as CFDictionary)
        IOHIDManagerScheduleWithRunLoop(m, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        guard IOHIDManagerOpen(m, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess,
              let devices = IOHIDManagerCopyDevices(m) as? Set<IOHIDDevice>, let dev = devices.first else { return false }
        manager = m
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        reportBuffer.withUnsafeMutableBufferPointer { buf in
            IOHIDDeviceRegisterInputReportCallback(dev, buf.baseAddress!, buf.count, { ctx, _, _, _, _, report, len in
                guard let ctx, len >= 18 else { return }
                Unmanaged<Accelerometer>.fromOpaque(ctx).takeUnretainedValue().handle(report, len)
            }, ctx)
        }
        return true
    }

    private func handle(_ r: UnsafeMutablePointer<UInt8>, _ len: Int) {
        func i32(_ o: Int) -> Double {
            Double(Int32(bitPattern: UInt32(r[o]) | UInt32(r[o+1]) << 8 | UInt32(r[o+2]) << 16 | UInt32(r[o+3]) << 24)) / 65536.0
        }
        let x = i32(6), y = i32(10), z = i32(14)
        onSample?(x, y, z)
        let mag = (x*x + y*y + z*z).squareRoot()
        let delta = abs(mag - baseline)
        baseline += (mag - baseline) * 0.02   // slow-moving gravity estimate
        if delta > threshold, Date().timeIntervalSince(lastSlap) > cooldown {
            lastSlap = Date()
            onSlap?(delta)
        }
    }
}
