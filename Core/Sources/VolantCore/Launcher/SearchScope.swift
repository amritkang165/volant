import Foundation

/// A built-in source the launcher can search on its own, the way a list extension takes over the
/// field: entered from its command row, or typed in one go as `contacts jane`. Each scope searches
/// through the typed shortcut it shares (`@`, `/`, `clip`), so the two ways in always agree.
public enum SearchScope: String, CaseIterable, Hashable, Sendable {
    case contacts, files, clipboard

    /// Words that show the scope's command row when typed on their own. Bare `clip` is left out: it
    /// already lists clipboard history, and Return there keeps pasting the newest item.
    public var commandWords: [String] {
        switch self {
        case .contacts: return ["contacts", "people"]
        case .files: return ["files", "file"]
        case .clipboard: return ["clipboard", "clipboard history"]
        }
    }

    /// Words that, followed by a space and a term, search the scope at once, longest first so
    /// `clipboard history foo` searches for `foo` rather than `history foo`. Singular `file` is left
    /// out so app names such as "File Merge" stay ordinary searches.
    var oneShotWords: [String] {
        switch self {
        case .contacts: return ["contacts", "people"]
        case .files: return ["files"]
        case .clipboard: return ["clipboard history", "clipboard"]
        }
    }

    /// The launcher command that enters this scope.
    public var command: CoreCommand {
        switch self {
        case .contacts: return .contacts
        case .files: return .files
        case .clipboard: return .clipboard
        }
    }

    /// The scope a command enters, if it is one of the scope commands.
    public init?(command: CoreCommand) {
        guard let scope = Self.allCases.first(where: { $0.command == command }) else { return nil }
        self = scope
    }

    /// The typed shortcut query that searches `term` in this scope.
    public func shortcutQuery(_ term: String) -> String {
        switch self {
        case .contacts: return "@" + term
        case .files: return "/" + term
        case .clipboard: return "clip " + term
        }
    }

    /// Whether the scope shows a prompt until something is typed. Clipboard lists recent items at
    /// once; contacts and files search nothing, and contacts never asks for access, until then.
    public var waitsForInput: Bool { self != .clipboard }

    /// The scope's name on its Back chip.
    public var titleResource: LocalizedStringResource {
        switch self {
        case .contacts: return LocalizedStringResource("Contacts", table: "Core", comment: "Name of the contacts search scope on the launcher's Back chip")
        case .files: return LocalizedStringResource("Files", table: "Core", comment: "Name of the files search scope on the launcher's Back chip")
        case .clipboard: return LocalizedStringResource("Clipboard", table: "Core", comment: "Name of the clipboard search scope on the launcher's Back chip")
        }
    }

    /// The search field's placeholder inside the scope.
    public var placeholderResource: LocalizedStringResource {
        switch self {
        case .contacts: return LocalizedStringResource("Search contacts…", table: "Core", comment: "Launcher search field placeholder inside the contacts scope")
        case .files: return LocalizedStringResource("Search files…", table: "Core", comment: "Launcher search field placeholder inside the files scope")
        case .clipboard: return LocalizedStringResource("Search clipboard history…", table: "Core", comment: "Launcher search field placeholder inside the clipboard scope")
        }
    }

    /// What the launcher shows inside the scope before anything is typed.
    public var promptResource: LocalizedStringResource {
        switch self {
        case .contacts: return LocalizedStringResource("Type a name, email or phone number to search your contacts.", table: "Core", comment: "Launcher notice inside the contacts scope before anything is typed")
        case .files: return LocalizedStringResource("Type part of a file name to search your Mac.", table: "Core", comment: "Launcher notice inside the files scope before anything is typed")
        case .clipboard: return LocalizedStringResource("Type to search what you copied.", table: "Core", comment: "Launcher notice inside the clipboard scope before anything is typed")
        }
    }

    public var title: String { String(localized: titleResource) }
    public var placeholder: String { String(localized: placeholderResource) }
    public var prompt: String { String(localized: promptResource) }

    /// The scope whose command row a whole query asks for, such as `people` or `clipboard history`.
    public static func command(for query: String) -> SearchScope? {
        let value = normalized(query)
        return allCases.first { $0.commandWords.contains(value) }
    }

    /// The scope and term of a query typed in one go, such as `contacts jane` or `files report`.
    /// Nil when the query only names a scope, or names none.
    public static func oneShot(_ query: String) -> (scope: SearchScope, term: String)? {
        guard command(for: query) == nil else { return nil }
        let tokens = query.split(whereSeparator: \.isWhitespace).map(String.init)
        for scope in allCases {
            for word in scope.oneShotWords {
                let words = word.split(separator: " ").map(String.init)
                guard tokens.count > words.count, tokens.prefix(words.count).map({ $0.lowercased() }) == words else { continue }
                return (scope, tokens.dropFirst(words.count).joined(separator: " "))
            }
        }
        return nil
    }

    /// Lowercases and trims a query, and collapses runs of spaces so `clipboard  history` still matches.
    private static func normalized(_ query: String) -> String {
        query.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
