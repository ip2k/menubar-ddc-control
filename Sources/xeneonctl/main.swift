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
  dump [<file>]             read every advertised VCP code; print or save as JSON (read-only)
  load <file>               write a dump's writable settings back and verify them
  state show                print every restorable setting (read-only)
  state save <file>         save them as JSON (read-only)
  state restore <file>      write a saved state back and verify it

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
    case "dump":
        let display = target()
        let ddc = channel(display)
        let data = try DDCDump.encoder.encode(ddc.dump(identity: display.identity, capabilities: try? ddc.capabilities()))
        if arguments.count == 2 {
            try data.write(to: URL(fileURLWithPath: arguments[1]))
        } else {
            print(String(decoding: data, as: UTF8.self))
        }
    case "load":
        guard arguments.count == 2 else { fail(usage) }
        let display = target()
        let ddc = channel(display)
        let dump = try DDCDump.decoder.decode(DDCDump.self, from: Data(contentsOf: URL(fileURLWithPath: arguments[1])))
        guard dump.matches(display.identity) else { fail("that file is from \(dump.display.name ?? "another monitor"), not \(display.name)") }
        let caps = try? ddc.capabilities()
        let report = ddc.restore(dump.restorableState, allowColorDefaults: caps?.supports(.restoreColorDefaults) ?? false)
        for m in report.mismatches { print("NOT restored: \(m.code) wanted \(m.wanted), is \(m.actual.map(String.init) ?? "unreadable")") }
        print(report.succeeded ? "wrote back \(dump.restorableState.values.count) settings" : "some settings were not restored")
        if !report.succeeded { exit(2) }
    case "state":
        guard arguments.count >= 2 else { fail(usage) }
        let ddc = channel(target())
        let caps = try? ddc.capabilities()
        switch (arguments[1], arguments.count) {
        case ("show", 2):
            let state = ddc.captureState { caps?.supports($0) ?? true }
            for code in state.values.keys.sorted() { print("\(VCPCode(code)) \(state.values[code]!)") }
        case ("save", 3):
            let state = ddc.captureState { caps?.supports($0) ?? true }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(state).write(to: URL(fileURLWithPath: arguments[2]))
            print("saved \(state.values.count) settings")
        case ("restore", 3):
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let state = try decoder.decode(DisplayState.self, from: Data(contentsOf: URL(fileURLWithPath: arguments[2])))
            let report = ddc.restore(state, allowColorDefaults: caps?.supports(.restoreColorDefaults) ?? false)
            if report.usedColorDefaults { print("gains were refused; sent restore colour defaults (0x08)") }
            if report.succeeded {
                print("restored all \(state.values.count) settings")
            } else {
                for m in report.mismatches { print("NOT restored: \(m.code) wanted \(m.wanted), is \(m.actual.map(String.init) ?? "unreadable")") }
                exit(2)
            }
        default:
            fail(usage)
        }
    default:
        fail(usage)
    }
} catch {
    fail("\(error)")
}
