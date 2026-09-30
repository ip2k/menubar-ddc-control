// The first probe (2026-09-25): finds each external display's IOAVService, reads its EDID, tries
// Get VCP on common codes and reads the capabilities string. Kept for the record; the
// `ddc-control` CLI does all of this properly (retries, checksums, the cross-process bus lock).
//
//   swiftc -O ddc-probe.swift -o ddc-probe && ./ddc-probe XENEON
//
// Not safe to run while Menubar DDC Control is running: it does not take the bus lock.
import Foundation
import IOKit

typealias IOAVService = CFTypeRef
@_silgen_name("IOAVServiceCreateWithService") func IOAVServiceCreateWithService(_ a: CFAllocator?, _ s: io_service_t) -> Unmanaged<IOAVService>?
@_silgen_name("IOAVServiceCopyEDID") func IOAVServiceCopyEDID(_ s: IOAVService, _ edid: UnsafeMutablePointer<Unmanaged<CFData>?>) -> IOReturn
@_silgen_name("IOAVServiceReadI2C") func IOAVServiceReadI2C(_ s: IOAVService, _ chip: UInt32, _ off: UInt32, _ buf: UnsafeMutableRawPointer, _ len: UInt32) -> IOReturn
@_silgen_name("IOAVServiceWriteI2C") func IOAVServiceWriteI2C(_ s: IOAVService, _ chip: UInt32, _ off: UInt32, _ buf: UnsafeMutableRawPointer, _ len: UInt32) -> IOReturn

func name(fromEDID d: Data) -> String {
    let b = [UInt8](d); guard b.count >= 128 else { return "?" }
    for i in stride(from: 54, to: 126, by: 18) where b[i] == 0 && b[i+1] == 0 && b[i+3] == 0xFC {
        return String(bytes: b[(i+5)..<(i+18)], encoding: .ascii)!.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return "?"
}

func ddcWrite(_ s: IOAVService, _ payload: [UInt8]) -> IOReturn {
    var pkt: [UInt8] = [0x80 | UInt8(payload.count)] + payload
    var chk: UInt8 = 0x6E ^ 0x51
    for x in pkt { chk ^= x }
    pkt.append(chk)
    return IOAVServiceWriteI2C(s, 0x37, 0x51, &pkt, UInt32(pkt.count))
}

func readVCP(_ s: IOAVService, _ code: UInt8) -> (cur: Int, max: Int)? {
    for _ in 0..<3 {
        _ = ddcWrite(s, [0x01, code])
        usleep(50_000)
        var r = [UInt8](repeating: 0, count: 12)
        let rc = IOAVServiceReadI2C(s, 0x37, 0x51, &r, 12)
        if rc == 0, r[2] == 0x02, r[3] == 0x00, r[4] == code {
            return (Int(r[8]) << 8 | Int(r[9]), Int(r[6]) << 8 | Int(r[7]))
        }
        usleep(40_000)
    }
    return nil
}

func capabilities(_ s: IOAVService) -> String {
    var out = [UInt8](); var offset = 0
    while offset < 2048 {
        var got = false
        for _ in 0..<4 {
            _ = ddcWrite(s, [0xF3, UInt8(offset >> 8), UInt8(offset & 0xFF)])
            usleep(60_000)
            var r = [UInt8](repeating: 0, count: 38)
            if IOAVServiceReadI2C(s, 0x37, 0x51, &r, 38) == 0, r[2] == 0xE3 {
                let len = Int(r[1] & 0x7F) - 3
                if len <= 0 { return String(bytes: out, encoding: .ascii) ?? "" }
                out += r[5..<(5+min(len, 32))]; offset += len; got = true; break
            }
            usleep(50_000)
        }
        if !got { break }
    }
    return String(bytes: out.filter { $0 != 0 }, encoding: .ascii) ?? ""
}

var it: io_iterator_t = 0
IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("DCPAVServiceProxy"), &it)
while case let svc = IOIteratorNext(it), svc != 0 {
    let loc = IORegistryEntryCreateCFProperty(svc, "Location" as CFString, nil, 0)?.takeRetainedValue() as? String ?? "?"
    guard loc == "External", let av = IOAVServiceCreateWithService(kCFAllocatorDefault, svc)?.takeRetainedValue() else { continue }
    var e: Unmanaged<CFData>?
    let edid = IOAVServiceCopyEDID(av, &e) == 0 ? (e!.takeRetainedValue() as Data) : Data()
    let n = name(fromEDID: edid)
    print("== \(n)  (EDID \(edid.count) bytes) mfg bytes: \(edid.prefix(12).map{String(format:"%02x",$0)}.joined())")
    if CommandLine.arguments.count > 1 && !n.uppercased().contains(CommandLine.arguments[1].uppercased()) { continue }
    for (c, label) in [(0x10,"brightness"),(0x12,"contrast"),(0x14,"color preset"),(0x16,"red gain"),(0x18,"green gain"),(0x1A,"blue gain"),(0xDC,"display mode"),(0x60,"input"),(0xD6,"power")] as [(UInt8,String)] {
        if let v = readVCP(av, c) { print(String(format: "  VCP 0x%02X %-13@ cur=%d max=%d", c, label as NSString, v.cur, v.max)) }
        else { print(String(format: "  VCP 0x%02X %-13@ no reply", c, label as NSString)) }
    }
    print("  caps: \(capabilities(av))")
}
