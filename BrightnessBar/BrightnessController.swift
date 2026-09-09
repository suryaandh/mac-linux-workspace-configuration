import Foundation
import CoreGraphics
import IOKit
import AppKit

private let bbLogFile = "/tmp/bb.log"
private func bbLog(_ msg: String) {
    let line = "\(Date()) \(msg)\n"
    if let data = line.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: bbLogFile) {
            if let fh = FileHandle(forWritingAtPath: bbLogFile) {
                fh.seekToEndOfFile(); fh.write(data); fh.closeFile()
            }
        } else {
            try? data.write(to: URL(fileURLWithPath: bbLogFile))
        }
    }
}

// IOI2CRequest and related constants are not exposed in the public SDK headers
// when compiling with swiftc standalone, so we define them manually.
let kIOI2CNoTransactionType: UInt32     = 0
let kIOI2CSimpleTransactionType: UInt32 = 1

struct IOI2CRequest {
    var commFlags: UInt32 = 0
    var reserved0: UInt32 = 0
    var replyTimeout: UInt64 = 0
    var result: kern_return_t = 0
    var completion: UInt64 = 0
    var sendTransactionType: UInt32 = 0
    var sendAddress: UInt32 = 0
    var sendSubAddress: UInt8 = 0
    var sendSubAddressMask: UInt8 = 0
    var reserved1: UInt16 = 0
    var sendBuffer: UnsafeMutableRawPointer? = nil
    var sendBytes: UInt32 = 0
    var replyTransactionType: UInt32 = 0
    var replyAddress: UInt32 = 0
    var replySubAddress: UInt8 = 0
    var replySubAddressMask: UInt8 = 0
    var reserved2: UInt16 = 0
    var replyBuffer: UnsafeMutableRawPointer? = nil
    var replyBytes: UInt32 = 0
    var reserved3: UInt32 = 0
}

// CoreDisplay private framework — used by MonitorControl for external display brightness
private let coreDisplayHandle: UnsafeMutableRawPointer? =
    dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_LAZY)

// DisplayServicesCanChangeBrightness: returns true if display supports software brightness
private typealias CanChangeBrightnessFn = @convention(c) (CGDirectDisplayID) -> Bool
private let displayServicesCanChangeBrightness: CanChangeBrightnessFn? = {
    guard let h = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
          let s = dlsym(h, "DisplayServicesCanChangeBrightness") else { return nil }
    return unsafeBitCast(s, to: CanChangeBrightnessFn.self)
}()

// CoreDisplay_Display_SetLinearBrightness: sets brightness 0.0-1.0 on any display
private typealias CDSetBrightnessFn = @convention(c) (CGDirectDisplayID, Double) -> Int32
private let cdSetBrightness: CDSetBrightnessFn? = {
    guard let h = coreDisplayHandle,
          let s = dlsym(h, "CoreDisplay_Display_SetLinearBrightness") else { return nil }
    return unsafeBitCast(s, to: CDSetBrightnessFn.self)
}()

private typealias CDGetBrightnessFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Double>) -> Int32
private let cdGetBrightness: CDGetBrightnessFn? = {
    guard let h = coreDisplayHandle,
          let s = dlsym(h, "CoreDisplay_Display_GetLinearBrightness") else { return nil }
    return unsafeBitCast(s, to: CDGetBrightnessFn.self)
}()

class BrightnessController {

    static func bbLogPublic(_ msg: String) { bbLog(msg) }

    // MARK: - Internal Display (DisplayServices)

    private static let displayServicesHandle: UnsafeMutableRawPointer? = {
        dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
    }()

    static func getInternalBrightness() -> Float {
        guard let handle = displayServicesHandle,
              let sym = dlsym(handle, "DisplayServicesGetBrightness") else { return 0 }
        typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
        let fn = unsafeBitCast(sym, to: GetFn.self)
        var value: Float = 0
        _ = fn(CGMainDisplayID(), &value)
        return value
    }

    static func setInternalBrightness(_ value: Float) {
        guard let handle = displayServicesHandle,
              let sym = dlsym(handle, "DisplayServicesSetBrightness") else { return }
        typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32
        let fn = unsafeBitCast(sym, to: SetFn.self)
        _ = fn(CGMainDisplayID(), max(0.0, min(1.0, value)))
    }

    // MARK: - External Display

    static func getExternalBrightness(displayID: CGDirectDisplayID) -> Float {
        // Return cached value if we've written one; otherwise default to 50%
        if let cached = externalBrightnessCache[displayID] { return cached }
        return 0.5
    }

    static func setExternalBrightness(displayID: CGDirectDisplayID, value: Float) {
        let clamped = max(0.0, min(1.0, value))
        bbLog("setExternalBrightness displayID=\(displayID) value=\(clamped)")
        ddcSetBrightness(displayID: displayID, value: clamped)
        externalBrightnessCache[displayID] = clamped
    }

    static func updateExternalBrightnessCache(displayID: CGDirectDisplayID, value: Float) {
        externalBrightnessCache[displayID] = max(0.0, min(1.0, value))
    }

    // MARK: - DisplayServices helpers

    private static func displayServicesGetBrightness(displayID: CGDirectDisplayID) -> Float? {
        guard let handle = displayServicesHandle,
              let sym = dlsym(handle, "DisplayServicesGetBrightness") else { return nil }
        typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
        let fn = unsafeBitCast(sym, to: GetFn.self)
        var value: Float = 0
        let ret = fn(displayID, &value)
        return ret == 0 ? value : nil
    }

    private static func displayServicesSetBrightness(displayID: CGDirectDisplayID, value: Float) -> Bool {
        guard let handle = displayServicesHandle,
              let sym = dlsym(handle, "DisplayServicesSetBrightness") else { return false }
        typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32
        let fn = unsafeBitCast(sym, to: SetFn.self)
        return fn(displayID, value) == 0
    }

    // MARK: - DDC/CI via IOAVService (ARM64 path, same as MonitorControl)

    private static let ddcBrightnessVCP: UInt8 = 0x10
    private static let ddcI2CAddress: UInt32 = 0xB7  // MCDP29XX chip on M1 Pro HDMI port
    // In-memory brightness cache keyed by displayID (DELL P2722H doesn't respond to DDC reads)
    private static var externalBrightnessCache: [CGDirectDisplayID: Float] = [:]

    /// Find the IOAVService for the external display via DCPAVServiceProxy.
    /// IMPORTANT: m1ddc's proven-working path for unqualified commands is
    /// `IOAVServiceCreate(kCFAllocatorDefault)` — the DEFAULT service, no registry entry.
    /// The DCPAVServiceProxy lookup is only m1ddc's fallback when a display is explicitly
    /// qualified, so we try the default service FIRST (exactly like `m1ddc set luminance N`).
    private static func avService(for displayID: CGDirectDisplayID) -> Unmanaged<AnyObject>? {
        // Path 1 (m1ddc's primary path): default service, no registry entry.
        if let svc = IOAVServiceCreate(kCFAllocatorDefault) {
            bbLog("avService: using default IOAVServiceCreate for displayID=\(displayID)")
            return svc
        }
        bbLog("avService: IOAVServiceCreate returned nil, falling back to DCPAVServiceProxy lookup")
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        defer { IOObjectRelease(root) }
        var iterator = io_iterator_t()
        guard IORegistryEntryCreateIterator(root, "IOService",
                                            IOOptionBits(kIORegistryIterateRecursively),
                                            &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var entry = IOIteratorNext(iterator)
        while entry != IO_OBJECT_NULL {
            defer { IOObjectRelease(entry); entry = IOIteratorNext(iterator) }
            var nameBuf = [CChar](repeating: 0, count: 128)
            IORegistryEntryGetName(entry, &nameBuf)
            guard String(cString: nameBuf) == "DCPAVServiceProxy" else { continue }
            if let unmanagedLoc = IORegistryEntryCreateCFProperty(entry, "Location" as CFString, kCFAllocatorDefault, 0),
               let loc = unmanagedLoc.takeRetainedValue() as? String, loc == "External" {
                if let svc = IOAVServiceCreateWithService(kCFAllocatorDefault, entry) {
                    bbLog("avService: found IOAVService for displayID=\(displayID)")
                    return svc
                }
            }
        }
        bbLog("avService: no IOAVService found for displayID=\(displayID)")
        return nil
    }

    private static func ddcWrite(service: Unmanaged<AnyObject>, command: UInt8, value: UInt16) -> Bool {
        let rawSvc: CFTypeRef = service.takeUnretainedValue()
        // Packet layout matches m1ddc exactly:
        // [0]=0x84, [1]=0x03, [2]=VCP, [3]=valueHi, [4]=valueLo, [5]=checksum
        // checksum = 0x6E ^ inputAddr ^ data[0..4]
        let inputAddr: UInt8 = 0x51
        var packet: [UInt8] = [0x84, 0x03, command, UInt8(value >> 8), UInt8(value & 0xFF), 0x00]
        packet[5] = 0x6E ^ inputAddr ^ packet[0] ^ packet[1] ^ packet[2] ^ packet[3] ^ packet[4]
        bbLog("ddcWrite cmd=0x\(String(command, radix:16)) value=\(value) packet=\(packet.map{String(format:"%02x",$0)}.joined(separator:" "))")
        // m1ddc/MonitorControl always perform 2 write cycles (some monitors need the duplicate)
        var success = false
        for _ in 0 ..< 2 {
            usleep(10_000)
            let ret = IOAVServiceWriteI2C(rawSvc, ddcI2CAddress, UInt32(inputAddr), &packet, UInt32(packet.count))
            bbLog("ddcWrite ret=\(ret)")
            if ret == kIOReturnSuccess { success = true }
        }
        return success
    }

    private static func ddcRead(service: Unmanaged<AnyObject>, command: UInt8) -> (current: UInt16, max: UInt16)? {
        let rawSvc: CFTypeRef = service.takeUnretainedValue()
        let inputAddr: UInt8 = 0x51
        // Read request packet matches m1ddc's prepareDDCRead exactly:
        // [0]=0x82, [1]=0x01, [2]=VCP, [3]=checksum
        // checksum = 0x6E ^ data[0] ^ data[1] ^ data[2]  (NO inputAddr term!)
        var packet: [UInt8] = [0x82, 0x01, command, 0x00]
        packet[3] = 0x6E ^ packet[0] ^ packet[1] ^ packet[2]
        usleep(10_000)
        guard IOAVServiceWriteI2C(rawSvc, ddcI2CAddress, UInt32(inputAddr), &packet, UInt32(packet.count)) == kIOReturnSuccess else {
            bbLog("ddcRead: write failed")
            return nil
        }
        usleep(50_000)
        var reply = [UInt8](repeating: 0, count: 12)
        // m1ddc reads at offset = inputAddr (0x51), not 0
        guard IOAVServiceReadI2C(rawSvc, ddcI2CAddress, UInt32(inputAddr), &reply, UInt32(reply.count)) == kIOReturnSuccess else {
            bbLog("ddcRead: read failed")
            return nil
        }
        bbLog("ddcRead reply=\(reply.map{String(format:"%02x",$0)}.joined(separator:" "))")
        // MonitorControl Arm64DDC reply layout: [6-7]=max [8-9]=current
        let maxVal     = UInt16(reply[6]) * 256 + UInt16(reply[7])
        let currentVal = UInt16(reply[8]) * 256 + UInt16(reply[9])
        guard maxVal > 0 else { bbLog("ddcRead: maxVal=0"); return nil }
        return (currentVal, maxVal)
    }

    private static func ddcGetBrightness(displayID: CGDirectDisplayID) -> Float? {
        guard let svc = avService(for: displayID) else {
            bbLog("DDC: no AVService for displayID=\(displayID)")
            return nil
        }
        guard let (current, max) = ddcRead(service: svc, command: ddcBrightnessVCP), max > 0 else {
            bbLog("DDC: ddcRead failed for displayID=\(displayID)")
            return nil
        }
        bbLog("DDC: getBrightness displayID=\(displayID) current=\(current) max=\(max)")
        return Float(current) / Float(max)
    }

    private static func ddcSetBrightness(displayID: CGDirectDisplayID, value: Float) {
        guard let svc = avService(for: displayID) else {
            bbLog("DDC: no AVService for displayID=\(displayID)")
            return
        }
        // Standard DDC brightness range is 0-100
        let maxVal: UInt16 = 100
        let ddcValue = UInt16(max(0, min(1, value)) * Float(maxVal))
        let ok = ddcWrite(service: svc, command: ddcBrightnessVCP, value: ddcValue)
        bbLog("DDC: write brightness \(ddcValue)/\(maxVal) -> \(ok ? "ok" : "failed")")
    }

    // MARK: - Display Enumeration

    static func externalDisplayIDs() -> [CGDirectDisplayID] {
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetActiveDisplayList(16, &displayIDs, &count)
        let all = (0..<Int(count)).map { displayIDs[$0] }
        bbLog("DEBUG displays: \(all.map { "id=\($0) builtin=\(CGDisplayIsBuiltin($0))" })")
        return all.filter { CGDisplayIsBuiltin($0) == 0 }
    }

    static func displayName(for displayID: CGDirectDisplayID) -> String {
        if CGDisplayIsBuiltin(displayID) != 0 { return "Built-in Display" }

        // NSScreen.localizedName is the most reliable source on Apple Silicon
        for screen in NSScreen.screens {
            if let screenID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
               screenID == displayID {
                bbLog("displayName: NSScreen -> \(screen.localizedName) for displayID=\(displayID)")
                return screen.localizedName
            }
        }

        // Try IODisplayConnect with vendor/product matching (works on Intel; may work on AS too)
        let vendor  = CGDisplayVendorNumber(displayID)
        let product = CGDisplayModelNumber(displayID)
        var iter: io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault,
                                        IOServiceMatching("IODisplayConnect"),
                                        &iter) == KERN_SUCCESS {
            var service = IOIteratorNext(iter)
            while service != 0 {
                defer { IOObjectRelease(service); service = IOIteratorNext(iter) }
                guard let info = IODisplayCreateInfoDictionary(service,
                    IOOptionBits(kIODisplayOnlyPreferredName))?.takeRetainedValue() as? [String: Any]
                else { continue }
                let v = (info[kDisplayVendorID as String] as? UInt32) ?? 0
                let p = (info[kDisplayProductID as String] as? UInt32) ?? 0
                if v == vendor && p == product,
                   let names = info["DisplayProductName"] as? [String: String],
                   let name = names.values.first {
                    bbLog("displayName: IODisplayConnect match -> \(name) for displayID=\(displayID)")
                    IOObjectRelease(iter)
                    return name
                }
            }
            IOObjectRelease(iter)
        }

        // Apple Silicon fallback: read DisplayProductName from DCPAVServiceProxy parent
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        var regIter = io_iterator_t()
        if IORegistryEntryCreateIterator(root, "IOService",
                                         IOOptionBits(kIORegistryIterateRecursively),
                                         &regIter) == KERN_SUCCESS {
            var entry = IOIteratorNext(regIter)
            while entry != IO_OBJECT_NULL {
                defer { IOObjectRelease(entry); entry = IOIteratorNext(regIter) }
                var nameBuf = [CChar](repeating: 0, count: 128)
                IORegistryEntryGetName(entry, &nameBuf)
                guard String(cString: nameBuf) == "DCPAVServiceProxy" else { continue }
                if let locUnmanaged = IORegistryEntryCreateCFProperty(entry, "Location" as CFString,
                                                                       kCFAllocatorDefault, 0),
                   let loc = locUnmanaged.takeRetainedValue() as? String, loc == "External",
                   let parent = ({ () -> io_registry_entry_t? in
                       var p = io_registry_entry_t()
                       return IORegistryEntryGetParentEntry(entry, "IOService", &p) == KERN_SUCCESS ? p : nil
                   }()) {
                    defer { IOObjectRelease(parent) }
                    if let namesUnmanaged = IORegistryEntryCreateCFProperty(parent,
                        "DisplayProductName" as CFString, kCFAllocatorDefault, 0),
                       let names = namesUnmanaged.takeRetainedValue() as? [String: String],
                       let name = names.values.first {
                        bbLog("displayName: DCPAVServiceProxy fallback -> \(name) for displayID=\(displayID)")
                        IOObjectRelease(regIter)
                        IOObjectRelease(root)
                        return name
                    }
                }
            }
            IOObjectRelease(regIter)
        }
        IOObjectRelease(root)
        bbLog("displayName: fallback to 'External Display' for displayID=\(displayID)")
        return "External Display"
    }
}
