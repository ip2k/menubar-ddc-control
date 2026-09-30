// The probe that found why HDMI failed (2026-09-25): for every DCPAVServiceProxy it prints the
// parent port tag, whether an EDID reads, whether the EDID carries an HDMI vendor block, and the
// IOReturn of a Get VCP brightness request at three delays. Over the M1 Max MacBook Pro's built-in
// HDMI port every transfer returned 0xE0114000 while the EDID still read fine; over USB-C the
// same monitor answered. Kept for the record.
//
// Not safe to run while Menubar DDC Control is running: it does not take the bus lock.
import Foundation
import IOKit
typealias IOAVService = CFTypeRef
@_silgen_name("IOAVServiceCreateWithService") func IOAVServiceCreateWithService(_ a: CFAllocator?, _ s: io_service_t) -> Unmanaged<IOAVService>?
@_silgen_name("IOAVServiceCopyEDID") func IOAVServiceCopyEDID(_ s: IOAVService, _ edid: UnsafeMutablePointer<Unmanaged<CFData>?>) -> IOReturn
@_silgen_name("IOAVServiceReadI2C") func IOAVServiceReadI2C(_ s: IOAVService, _ chip: UInt32, _ off: UInt32, _ buf: UnsafeMutableRawPointer, _ len: UInt32) -> IOReturn
@_silgen_name("IOAVServiceWriteI2C") func IOAVServiceWriteI2C(_ s: IOAVService, _ chip: UInt32, _ off: UInt32, _ buf: UnsafeMutableRawPointer, _ len: UInt32) -> IOReturn
var it: io_iterator_t = 0
IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("DCPAVServiceProxy"), &it)
while case let svc = IOIteratorNext(it), svc != 0 {
  var p: io_registry_entry_t = 0; IORegistryEntryGetParentEntry(svc, kIOServicePlane, &p)
  var nm = [CChar](repeating: 0, count: 128); IORegistryEntryGetName(p, &nm)
  guard let av = IOAVServiceCreateWithService(nil, svc)?.takeRetainedValue() else { print("parent \(String(cString: nm)): no AV"); continue }
  var e: Unmanaged<CFData>?; let erc = IOAVServiceCopyEDID(av, &e)
  let d = erc == 0 ? [UInt8](e!.takeRetainedValue() as Data) : []
  print("parent=\(String(cString: nm)) edidRC=\(String(format:"0x%x",erc)) bytes=\(d.count)", d.count > 20 ? "ext-blocks=\(d[126])" : "")
  // The HDMI vendor-specific data block in the CEA extension shows the sink is on HDMI.
  if d.count >= 256 { let hdmi = (0..<(d.count-3)).contains { d[$0]==0x03 && d[$0+1]==0x0C && d[$0+2]==0x00 }; print("  HDMI VSDB present: \(hdmi)") }
  var pkt: [UInt8] = [0x82, 0x01, 0x10]; pkt.append(0x6E ^ 0x51 ^ 0x82 ^ 0x01 ^ 0x10)
  for delay in [40_000, 100_000, 200_000] {
    let w = IOAVServiceWriteI2C(av, 0x37, 0x51, &pkt, 4); usleep(UInt32(delay))
    var r = [UInt8](repeating: 0, count: 12); let rr = IOAVServiceReadI2C(av, 0x37, 0x51, &r, 12)
    print(String(format: "  delay %3dms write=0x%x read=0x%x ", delay/1000, w, rr) + r.map{String(format:"%02x",$0)}.joined(separator:" "))
  }
}
