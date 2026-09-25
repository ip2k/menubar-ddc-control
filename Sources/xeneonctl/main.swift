import Foundation
import XeneonKit

let usage = """
usage: xeneonctl [--display <name>] <command>

  list                      external displays and whether they answer DDC/CI
  caps                      the display's capabilities string, parsed
  get <code>                read a VCP code (hex like 0x10, or a name below)
  set <code> <value>        write a VCP code
  profiles                  installed display ICC profiles
  profile [<path>|factory]  show, assign or reset the display's ICC profile

names: brightness contrast preset red green blue sharpness temperature language
The default display is the Xeneon Edge, else the first external display.
"""

let names: [String: VCPCode] = [
    "brightness": .brightness, "contrast": .contrast, "preset": .colorPreset,
    "red": .redGain, "green": .greenGain, "blue": .blueGain, "sharpness": .sharpness,
    "temperature": .colorTemperatureRequest, "language": .osdLanguage,
]

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func parseCode(_ text: String) -> VCPCode {
    if let named = names[text.lowercased()] { return named }
    let hex = text.lowercased().hasPrefix("0x") ? String(text.dropFirst(2)) : text
    guard let byte = UInt8(hex, radix: 16) else { fail("unknown VCP code \(text)") }
    return VCPCode(byte)
}

var arguments = Array(CommandLine.arguments.dropFirst())
var displayFilter: String?
if let index = arguments.firstIndex(of: "--display") {
    guard index + 1 < arguments.count else { fail(usage) }
    displayFilter = arguments[index + 1]
    arguments.removeSubrange(index...(index + 1))
}
guard let command = arguments.first else { fail(usage) }

let displays = DisplayDirectory.externalDisplays()
@MainActor func target() -> ExternalDisplay {
    let match = displayFilter.map { f in displays.first { $0.name.localizedCaseInsensitiveContains(f) } } ?? displays.first
    guard let match else { fail("no matching external display") }
    return match
}
func channel(_ display: ExternalDisplay) -> DDCChannel {
    guard let ddc = display.ddc else { fail("\(display.name): \(DDCError.unavailable)") }
    return ddc
}

do {
    switch command {
    case "list":
        for display in displays {
            let state: String
            if let ddc = display.ddc {
                state = (try? ddc.readVCP(.brightness)).map { "DDC/CI ok, brightness \($0.current)/\($0.maximum)" } ?? "DDC/CI does not answer"
            } else {
                state = "no DDC/CI channel"
            }
            print("\(display.name) [\(display.identity.manufacturerID) id \(display.id)]: \(state)")
        }
    case "caps":
        let caps = try channel(target()).capabilities()
        print(caps.raw)
        print("model \(caps.model ?? "?"), MCCS \(caps.mccsVersion ?? "?")")
        for (code, values) in caps.vcp.sorted(by: { $0.key < $1.key }) {
            print("  \(code)" + (values.isEmpty ? "" : " values " + values.map { String(format: "%02X", $0) }.joined(separator: " ")))
        }
    case "get":
        guard arguments.count == 2 else { fail(usage) }
        let reading = try channel(target()).readVCP(parseCode(arguments[1]))
        print("\(reading.current) (max \(reading.maximum))")
    case "set":
        guard arguments.count == 3, let value = UInt16(arguments[2]) else { fail(usage) }
        let ddc = channel(target())
        let code = parseCode(arguments[1])
        try ddc.writeVCP(code, value)
        let reading = try ddc.readVCP(code)
        print("\(code) now \(reading.current) (max \(reading.maximum))")
    case "profiles":
        for profile in ICCProfiles.installedDisplayProfiles() { print("\(profile.name)\t\(profile.url.path)") }
    case "profile":
        let display = target()
        if arguments.count == 2 {
            let profile = arguments[1] == "factory" ? nil : ICCProfile(url: URL(fileURLWithPath: arguments[1]), name: "")
            guard ICCProfiles.assign(profile, to: display.id) else { fail("ColorSync refused the profile") }
        }
        let current = ICCProfiles.current(for: display.id)
        print(current.map { "\($0.name)\t\($0.url.path)" } ?? "unknown")
    default:
        fail(usage)
    }
} catch {
    fail("\(error)")
}
