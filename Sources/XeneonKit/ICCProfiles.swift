@preconcurrency import ColorSync
import CoreGraphics
import Foundation

/// An installed display-class ICC profile.
public struct ICCProfile: Identifiable, Hashable, Sendable {
    public var url: URL
    public var name: String
    public var id: URL { url }

    public init(url: URL, name: String) {
        self.url = url
        self.name = name
    }
}

/// Per-display ICC profile assignment through ColorSync: the same setting as
/// System Settings → Displays → Color profile, so it persists without this app running.
public enum ICCProfiles {
    /// Every installed profile of the display ("mntr") class, sorted by name.
    public static func installedDisplayProfiles() -> [ICCProfile] {
        final class Box { var profiles: [ICCProfile] = [] }
        let box = Box()
        let options = [kColorSyncWaitForCacheReply.takeUnretainedValue(): kCFBooleanTrue] as CFDictionary
        let unmanaged = Unmanaged.passRetained(box)
        defer { unmanaged.release() }
        ColorSyncIterateInstalledProfilesWithOptions({ info, userInfo in
            guard let info = info as? [String: Any], let userInfo else { return true }
            let profileClass = info[kColorSyncProfileClass.takeUnretainedValue() as String] as? String
            guard profileClass == (kColorSyncSigDisplayClass.takeUnretainedValue() as String),
                  let url = info[kColorSyncProfileURL.takeUnretainedValue() as String] as? URL else { return true }
            let name = info[kColorSyncProfileDescription.takeUnretainedValue() as String] as? String
                ?? url.deletingPathExtension().lastPathComponent
            Unmanaged<Box>.fromOpaque(userInfo).takeUnretainedValue().profiles.append(ICCProfile(url: url, name: name))
            return true
        }, nil, unmanaged.toOpaque(), options, nil)
        var seen = Set<URL>()
        return box.profiles.filter { seen.insert($0.url).inserted }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The profile the display is using now.
    public static func current(for display: CGDirectDisplayID) -> ICCProfile? {
        guard let profile = ColorSyncProfileCreateWithDisplayID(display)?.takeRetainedValue(),
              let url = ColorSyncProfileGetURL(profile, nil)?.takeUnretainedValue() as URL? else { return nil }
        let name = ColorSyncProfileCopyDescriptionString(profile)?.takeRetainedValue() as String?
        return ICCProfile(url: url, name: name ?? url.deletingPathExtension().lastPathComponent)
    }

    /// Assigns `profile` to the display for the current user; `nil` reverts to the factory profile.
    @discardableResult
    public static func assign(_ profile: ICCProfile?, to display: CGDirectDisplayID) -> Bool {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(display)?.takeRetainedValue() else { return false }
        let value: CFTypeRef = profile.map { $0.url as CFURL } ?? kCFNull
        let info = [
            kColorSyncDeviceDefaultProfileID.takeUnretainedValue(): value,
            kColorSyncProfileUserScope.takeUnretainedValue(): kCFPreferencesCurrentUser,
        ] as CFDictionary
        return ColorSyncDeviceSetCustomProfiles(kColorSyncDisplayDeviceClass.takeUnretainedValue(), uuid, info)
    }

    /// Adds a profile file to ~/Library/ColorSync/Profiles so ColorSync lists it.
    public static func install(fileAt source: URL) throws -> URL {
        let directory = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/ColorSync/Profiles")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appending(path: source.lastPathComponent)
        if source.standardizedFileURL != destination.standardizedFileURL {
            if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
            try FileManager.default.copyItem(at: source, to: destination)
        }
        return destination
    }
}
