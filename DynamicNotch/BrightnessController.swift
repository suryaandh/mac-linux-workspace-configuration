import Foundation
import CoreGraphics
import IOKit
import IOKit.graphics

class BrightnessController {

    // MARK: - Internal Display (IOKit)

    static func getInternalBrightness() -> Float {
        var brightness: Float = 0
        let port: mach_port_t = kIOMainPortDefault
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(port, IOServiceMatching("IODisplayConnect"), &iter) == kIOReturnSuccess else {
            return brightness
        }
        var service: io_object_t = IOIteratorNext(iter)
        while service != 0 {
            var val: Float = 0
            if IODisplayGetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, &val) == kIOReturnSuccess {
                brightness = val
                IOObjectRelease(service)
                break
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iter)
        }
        IOObjectRelease(iter)
        return brightness
    }

    static func setInternalBrightness(_ value: Float) {
        let clamped = max(0.0, min(1.0, value))
        let port: mach_port_t = kIOMainPortDefault
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(port, IOServiceMatching("IODisplayConnect"), &iter) == kIOReturnSuccess else { return }
        var service: io_object_t = IOIteratorNext(iter)
        while service != 0 {
            IODisplaySetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, clamped)
            IOObjectRelease(service)
            service = IOIteratorNext(iter)
        }
        IOObjectRelease(iter)
    }

    // MARK: - External Display (DisplayServices via dlopen)

    private static let displayServicesHandle: UnsafeMutableRawPointer? = {
        dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
    }()

    static func getExternalBrightness(displayID: CGDirectDisplayID) -> Float {
        guard let handle = displayServicesHandle,
              let sym = dlsym(handle, "DisplayServicesGetBrightness") else { return 0 }
        typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
        let fn = unsafeBitCast(sym, to: GetFn.self)
        var value: Float = 0
        _ = fn(displayID, &value)
        return value
    }

    static func setExternalBrightness(displayID: CGDirectDisplayID, value: Float) {
        guard let handle = displayServicesHandle,
              let sym = dlsym(handle, "DisplayServicesSetBrightness") else { return }
        typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Void
        let fn = unsafeBitCast(sym, to: SetFn.self)
        fn(displayID, max(0.0, min(1.0, value)))
    }

    // MARK: - Display Enumeration

    static func externalDisplayIDs() -> [CGDirectDisplayID] {
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetActiveDisplayList(16, &displayIDs, &count)
        return (0..<Int(count))
            .map { displayIDs[$0] }
            .filter { CGDisplayIsBuiltin($0) == 0 }
    }
}
