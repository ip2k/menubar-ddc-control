import Foundation

/// A dotted version such as "0.2.1" or "v1.0". Compared numerically, part by part; any
/// pre-release suffix ("-beta.1") ranks below the same version without one.
public struct AppVersion: Comparable, CustomStringConvertible, Sendable {
    public let parts: [Int]
    public let prerelease: String?

    public init?(_ text: String) {
        var body = text.trimmingCharacters(in: .whitespaces)
        if body.first == "v" || body.first == "V" { body.removeFirst() }
        let pieces = body.split(separator: "-", maxSplits: 1)
        guard let core = pieces.first else { return nil }
        let numbers = core.split(separator: ".").map { Int($0) }
        guard !numbers.isEmpty, numbers.allSatisfy({ $0 != nil }) else { return nil }
        parts = numbers.compactMap { $0 }
        prerelease = pieces.count > 1 ? String(pieces[1]) : nil
    }

    public var description: String {
        parts.map(String.init).joined(separator: ".") + (prerelease.map { "-\($0)" } ?? "")
    }

    public static func < (a: AppVersion, b: AppVersion) -> Bool {
        for i in 0..<max(a.parts.count, b.parts.count) {
            let x = i < a.parts.count ? a.parts[i] : 0
            let y = i < b.parts.count ? b.parts[i] : 0
            if x != y { return x < y }
        }
        switch (a.prerelease, b.prerelease) {
        case (nil, nil), (nil, _?): return false
        case (_?, nil): return true
        case (let p?, let q?): return p.compare(q, options: .numeric) == .orderedAscending
        }
    }

    public static func == (a: AppVersion, b: AppVersion) -> Bool { !(a < b) && !(b < a) }
}

/// The fields of a GitHub release (REST API `repos/{owner}/{repo}/releases/latest`) the updater needs.
public struct GitHubRelease: Decodable, Sendable {
    public struct Asset: Decodable, Sendable {
        public var name: String
        public var browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    public var tagName: String
    public var htmlURL: URL
    public var body: String?
    public var draft: Bool
    public var prerelease: Bool
    public var assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name", htmlURL = "html_url", body, draft, prerelease, assets
    }

    public var version: AppVersion? { AppVersion(tagName) }

    /// The disk image to download, or the release page when there is none.
    public var downloadURL: URL {
        assets.first { $0.name.lowercased().hasSuffix(".dmg") }?.browserDownloadURL ?? htmlURL
    }

    /// Whether this release should be offered to someone running `current`.
    public func isUpdate(over current: AppVersion) -> Bool {
        guard !draft, !prerelease, let version else { return false }
        return version > current
    }
}
