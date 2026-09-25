import Foundation
import IOKit

/// The private IOKit functions Apple Silicon Macs use for display I2C (the approach of
/// m1ddc and MonitorControl). Resolved with `dlsym` so a macOS release that drops them
/// makes DDC unavailable instead of crashing at launch.
enum IOAV {
    typealias CreateWithService = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
    typealias CopyEDID = @convention(c) (CFTypeRef, UnsafeMutablePointer<Unmanaged<CFData>?>) -> IOReturn
    typealias I2C = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn

    private static func symbol<T>(_ name: String, as _: T.Type) -> T? {
        // IOKit is already linked, so this returns the loaded image rather than loading anything.
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW | RTLD_NOLOAD),
              let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }

    static let create = symbol("IOAVServiceCreateWithService", as: CreateWithService.self)
    static let copyEDID = symbol("IOAVServiceCopyEDID", as: CopyEDID.self)
    static let readI2C = symbol("IOAVServiceReadI2C", as: I2C.self)
    static let writeI2C = symbol("IOAVServiceWriteI2C", as: I2C.self)

    static var isAvailable: Bool { create != nil && copyEDID != nil && readI2C != nil && writeI2C != nil }

    /// Every external display's AV service that can report an EDID. Services without one
    /// are stale proxies left behind by unplugged displays and would fail every transfer.
    static func externalServices() -> [(service: CFTypeRef, edid: Data)] {
        guard isAvailable, let create, let copyEDID else { return [] }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("DCPAVServiceProxy"), &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }
        var found: [(CFTypeRef, Data)] = []
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            let location = IORegistryEntryCreateCFProperty(entry, "Location" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? String
            guard location == "External", let service = create(kCFAllocatorDefault, entry)?.takeRetainedValue() else { continue }
            var edid: Unmanaged<CFData>?
            guard copyEDID(service, &edid) == kIOReturnSuccess, let data = edid?.takeRetainedValue() as Data? else { continue }
            found.append((service, data))
        }
        return found
    }
}
