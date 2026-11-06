import Foundation

/// What a list extension's row puts on the clipboard when the owner chooses it, for an extension whose
/// manifest declares the `clipboard-write` permission. Either `text`, at most 64 KB of UTF-8 copied as
/// plain text, or a `url` on a declared host with a `type`, which Volant downloads through its fetch
/// helper only when the owner chooses the copy, checks against that type, and copies as text (`svg`,
/// `text`) or as an image (`png`, `jpeg`, `webp`, `ico`). The module never sees the downloaded bytes,
/// and nothing is fetched while listing. `title` names the entry in the row's Actions menu.
public struct ExtensionItemCopy: Codable, Hashable, Sendable {
    public static let permission = "clipboard-write"
    public static let maximumTextBytes = 64 * 1024
    public static let maximumTitleLength = 40
    /// The largest download a copy accepts, the same as any extension fetch.
    public static let maximumDownloadBytes = ExtensionNetwork.maximumResponseBytes

    public var text: String?
    public var url: String?
    public var type: String?
    public var title: String?

    public init(text: String? = nil, url: String? = nil, type: String? = nil, title: String? = nil) {
        self.text = text; self.url = url; self.type = type; self.title = title
    }

    /// What a downloaded copy must be. SVG and text are copied as plain text; the others as an image.
    public enum Kind: String, CaseIterable, Sendable {
        case svg, png, jpeg, webp, ico, text

        public var isImage: Bool { ![.svg, .text].contains(self) }

        /// The Uniform Type Identifier ImageIO reports for a decoded image of this kind.
        public var imageTypeIdentifier: String? {
            switch self {
            case .png: "public.png"
            case .jpeg: "public.jpeg"
            case .webp: "org.webmproject.webp"
            case .ico: "com.microsoft.ico"
            case .svg, .text: nil
            }
        }

        /// The kind's name in messages, such as "PNG image".
        public var displayName: String {
            switch self {
            case .svg: String(localized: "SVG", table: "Core", comment: "Kind of file an extension row copies")
            case .png: String(localized: "PNG image", table: "Core", comment: "Kind of file an extension row copies")
            case .jpeg: String(localized: "JPEG image", table: "Core", comment: "Kind of file an extension row copies")
            case .webp: String(localized: "WebP image", table: "Core", comment: "Kind of file an extension row copies")
            case .ico: String(localized: "ICO image", table: "Core", comment: "Kind of file an extension row copies")
            case .text: String(localized: "text", table: "Core", comment: "Kind of file an extension row copies, in the middle of a sentence")
            }
        }
    }

    /// The kind of a `url` copy; nil for a `text` copy.
    public var kind: Kind? { url == nil ? nil : type.flatMap(Kind.init(rawValue:)) }

    /// The Actions menu entry's title: the extension's, or "Copy".
    public var displayTitle: String {
        title ?? String(localized: "Copy", table: "Core", comment: "Default Actions menu title for an extension row's copy")
    }

    /// The confirmation shown after copying: "Copied SVG" for a title such as "Copy SVG", otherwise what
    /// was copied.
    public var confirmation: String {
        if let title, title.hasPrefix("Copy "), title.count > 5 {
            let rest = String(title.dropFirst(5))
            return String(localized: "Copied \(rest, format: .verbatim)", table: "Core", comment: "Launcher feedback after copying; the value is the rest of the extension's Copy title, such as SVG")
        }
        switch kind {
        case .svg?: return String(localized: "Copied SVG", table: "Core", comment: "Launcher feedback after an extension row copies SVG markup")
        case let kind? where kind.isImage: return String(localized: "Copied image", table: "Core", comment: "Launcher feedback after an extension row copies an image")
        default: return String(localized: "Copied text", table: "Core", comment: "Launcher feedback after an extension row copies text")
        }
    }

    /// The copy as Volant keeps it, or nil to drop it: exactly one of `text` (non-empty, at most 64 KB of
    /// UTF-8) or `url` (permitted for `hosts`, the manifest's declared hosts, with a known `type`). The
    /// title becomes one trimmed line of at most 40 characters, or nil for the default.
    public func sanitized(hosts: Set<String>) -> ExtensionItemCopy? {
        let title = title.map { line in
            String(line.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces).prefix(Self.maximumTitleLength))
                .trimmingCharacters(in: .whitespaces)
        }.flatMap { $0.isEmpty ? nil : $0 }
        switch (text, url) {
        case (let text?, nil):
            guard !text.isEmpty, text.utf8.count <= Self.maximumTextBytes else { return nil }
            return ExtensionItemCopy(text: text, title: title)
        case (nil, let url?):
            guard let type, let kind = Kind(rawValue: type), ExtensionNetwork.permittedURL(url, hosts: hosts) != nil else { return nil }
            return ExtensionItemCopy(url: url, type: kind.rawValue, title: title)
        default:
            return nil
        }
    }

    /// The text to copy from downloaded `svg` or `text` bytes: valid UTF-8 without NUL characters, and for
    /// SVG starting, after an optional byte order mark and whitespace, with `<svg` or an XML prolog and
    /// containing an `<svg` element. Nil when the bytes are not that. The markup is never rendered.
    public static func downloadedText(_ data: Data, kind: Kind) -> String? {
        guard !kind.isImage, !data.isEmpty, !data.contains(0), let text = String(data: data, encoding: .utf8) else { return nil }
        guard kind == .svg else { return text }
        let start = text.drop { $0 == "\u{FEFF}" || $0.isWhitespace }
        guard start.hasPrefix("<svg") || start.hasPrefix("<?xml"), start.contains("<svg") else { return nil }
        return text
    }

    /// Whether downloaded bytes start with the signature of an image `kind`. The app then decodes them
    /// with ImageIO before copying; this only refuses obvious mismatches early.
    public static func hasImageSignature(_ data: Data, kind: Kind) -> Bool {
        let bytes = [UInt8](data.prefix(12))
        switch kind {
        case .png: return bytes.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        case .jpeg: return bytes.starts(with: [0xFF, 0xD8, 0xFF])
        case .webp: return ExtensionManifest.looksLikeWebP(data)
        case .ico: return bytes.starts(with: [0x00, 0x00, 0x01, 0x00])
        case .svg, .text: return false
        }
    }
}

/// Why a row's copy put nothing on the clipboard.
public enum ExtensionCopyError: Error, LocalizedError, Equatable {
    case notAllowed, hostNotApproved(String), unavailable(Int), tooLarge, wrongType(ExtensionItemCopy.Kind)
    public var errorDescription: String? {
        switch self {
        case .notAllowed:
            return String(localized: "This extension isn’t allowed to copy to your clipboard.", table: "Core", comment: "Extension copy error")
        case .hostNotApproved(let host):
            return String(localized: "Allow access to \(host, format: .verbatim) to copy this.", table: "Core", comment: "Extension copy error; the value is a web host")
        case .unavailable(let status) where status > 0:
            return String(localized: "Couldn’t download it: the server answered \(status, specifier: "%lld"). Nothing was copied.", table: "Core",
                          comment: "Extension copy error; the number is an HTTP status code")
        case .unavailable:
            return String(localized: "Couldn’t download it. Check your connection; files over 512 KB can’t be copied. Nothing was copied.", table: "Core",
                          comment: "Extension copy error")
        case .tooLarge:
            return String(localized: "It’s larger than 512 KB, so nothing was copied.", table: "Core", comment: "Extension copy error")
        case .wrongType(let kind):
            return String(localized: "The download isn’t a valid \(kind.displayName, format: .verbatim), so nothing was copied.", table: "Core",
                          comment: "Extension copy error; the value is a kind of file such as PNG image")
        }
    }
}

extension ExtensionItem {
    /// Whether Return performs the row's copy: it has one, no link to open and no action Return runs
    /// instead. A row with a link keeps opening it, and its copy is in the Actions menu.
    public var returnCopies: Bool { copy != nil && url == nil && primaryAction == nil }
}

extension ExtensionManifest {
    /// The hosts a row's `copy` may download from, or nil when the manifest does not declare
    /// `clipboard-write`, so every row's copy is dropped while sanitizing.
    public var rowCopyHosts: Set<String>? { wantsClipboardWrite ? Set(declaredHosts) : nil }
}
