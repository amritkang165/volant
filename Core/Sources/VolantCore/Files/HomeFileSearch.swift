import Foundation

/// The rules shared by the app and `VolantAgentHost` for searching the owner's home folder with
/// Spotlight; the query itself lives in the helper's `HomeFileSearchHost`. The sandboxed app can't run this query itself: Spotlight returns only files the
/// caller may read, so inside the sandbox it finds nothing of the owner's. The helper, which is not
/// sandboxed, runs it for one validated term and replies with at most `maximumResults` entries,
/// which the app parses again with the same bounds.
public enum HomeFileSearch {
    public static let minimumTermLength = 3
    public static let maximumTermLength = 200
    public static let maximumResults = 8
    /// Results read from Spotlight's newest-first list before giving up on finding eight that pass
    /// `isInteresting`, so a term matching tens of thousands of files stays cheap.
    public static let scannedResults = 200
    /// How long the helper waits for Spotlight before replying with what it has.
    public static let timeLimit: TimeInterval = 3
    static let maximumPathLength = 4096
    static let maximumNameLength = 255
    static let maximumKindLength = 120
    static let maximumReplyBytes = 64_000

    /// One file the search found.
    public struct Entry: Codable, Equatable, Sendable {
        public var path: String
        public var name: String
        public var kind: String
        public init(path: String, name: String, kind: String) { self.path = path; self.name = name; self.kind = kind }
    }

    /// The term to search for, trimmed, or nil when it is too short, too long or holds control
    /// characters, which a file name typed in the launcher never needs.
    public static func term(_ raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (minimumTermLength...maximumTermLength).contains(text.count),
              !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        return text
    }

    /// Hides library internals, caches, build products and dotfiles from file results, for
    /// Spotlight and fsearch alike.
    public static func isInteresting(_ path: String) -> Bool {
        let noisy = ["/Library/", "/node_modules/", "/DerivedData/", "/.Trash/", "/dist/", "/target/", "/Pods/"]
        if noisy.contains(where: { path.contains($0) }) { return false }
        let parts = path.split(separator: "/")
        if parts.contains(where: { $0.hasPrefix(".") }) { return false }
        let directories = parts.dropLast().map { $0.lowercased() }
        return !directories.contains { $0 == "build" || $0.hasPrefix("build-") || $0.hasPrefix("build_") }
    }

    /// The entry for one Spotlight result, or nil when its path is unusable or noisy. A missing
    /// display name falls back to the file name; names and kinds are flattened and trimmed.
    public static func entry(path: String, name: String?, kind: String?) -> Entry? {
        guard isUsable(path), isInteresting(path) else { return nil }
        let fallback = (path as NSString).lastPathComponent
        let shown = flattened(name ?? "", limit: maximumNameLength)
        return Entry(path: path, name: shown.isEmpty ? fallback : shown, kind: flattened(kind ?? "", limit: maximumKindLength))
    }

    /// Encodes the helper's reply.
    public static func reply(_ entries: [Entry]) throws -> Data {
        try JSONEncoder().encode(Array(entries.prefix(maximumResults)))
    }

    /// Parses a helper reply with the same bounds the helper applied, dropping entries that fail
    /// them. Nil when the reply is oversized or not a list of entries.
    public static func entries(from data: Data) -> [Entry]? {
        guard data.count <= maximumReplyBytes, let decoded = try? JSONDecoder().decode([Entry].self, from: data) else { return nil }
        return Array(decoded.compactMap { entry(path: $0.path, name: $0.name, kind: $0.kind) }.prefix(maximumResults))
    }

    /// An absolute path of reasonable length with no NUL or newline.
    static func isUsable(_ path: String) -> Bool {
        path.hasPrefix("/") && path.utf8.count <= maximumPathLength && !path.contains("\0") && !path.contains(where: \.isNewline)
    }

    /// Text on one line, at most `limit` characters.
    static func flattened(_ text: String, limit: Int) -> String {
        String(text.components(separatedBy: .newlines).joined(separator: " ").trimmingCharacters(in: .whitespaces).prefix(limit))
    }
}
