import CryptoKit
import VolantCore
import XCTest
@testable import Volant

/// Volant's own Contacts, Files and Clipboard scopes: a scope word puts its command first, Return or
/// Tab enters it, typing searches only that source through its typed shortcut, Escape and Back leave,
/// one-go queries search at once, and the typed shortcuts behave as before. Contacts and Spotlight are
/// replaced by recorders, so no test host asks for access or searches the owner's Mac.
@MainActor
final class LauncherSearchScopeTests: XCTestCase {
    private var root: URL!
    private var contactSearches: [(term: String, asks: Bool)] = []
    private var fileSearches: [String] = []
    private var clipboard: ClipboardStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("search-scope-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        contactSearches = []
        fileSearches = []
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    /// A launcher whose contact and file searches are recorded, with two fictional clipboard items.
    private func model() -> LauncherModel {
        clipboard = ClipboardStore(retention: 10, storageURL: root.appendingPathComponent("clips.sqlite"), encryptionKey: SymmetricKey(size: .bits256))
        clipboard.record("fictional alpha invoice")
        clipboard.record("fictional beta address")
        let files = RecordingFileSearch()
        files.record = { [weak self] term in self?.fileSearches.append(term) }
        let model = LauncherModel(index: AppIndex(entries: []), clipboard: clipboard,
                                  notes: NotesStore(directory: root.appendingPathComponent("Notes")), config: Preferences(),
                                  usage: UsageStore(url: root.appendingPathComponent("usage.sqlite")), files: files) { _ in }
        model.searchesSecondarySources = false
        model.appleShortcuts.loadOverride = { $0([], nil) }
        model.searchContacts = { [weak self] term, asks, completion in
            self?.contactSearches.append((term, asks))
            completion([ContactEntry(id: "fixture-ana", name: "Ana Fictional", organization: "Example Co", fields: [])])
        }
        model.dismiss = {}
        return model
    }

    func testScopeWordsPutTheirCommandFirst() {
        let model = model()
        for (word, id) in [("contacts", "core:contacts"), ("people", "core:contacts"), ("files", "core:files"), ("file", "core:files"),
                           ("clipboard", "core:clipboard"), ("clipboard history", "core:clipboard")] {
            model.query = word
            XCTAssertEqual(model.rows.first?.id, id, word)
            XCTAssertEqual(model.selection, 0, word)
            XCTAssertEqual(model.rows.filter { $0.id == id }.count, 1, "\(word) lists its command once")
        }
        XCTAssertTrue(contactSearches.isEmpty)
        XCTAssertTrue(fileSearches.isEmpty)
    }

    func testReturnEntersContactsWithoutAskingUntilSomethingIsTyped() {
        let model = model()
        model.query = "people"
        model.activateSelection()
        XCTAssertEqual(model.searchScope, .contacts)
        XCTAssertEqual(model.query, "")
        XCTAssertEqual(model.searchPlaceholder, SearchScope.contacts.placeholder)
        XCTAssertEqual(model.notice, SearchScope.contacts.prompt)
        XCTAssertTrue(model.rows.isEmpty)
        XCTAssertTrue(contactSearches.isEmpty, "entering never asks for Contacts access")
        model.query = "ana"
        XCTAssertEqual(contactSearches.last?.term, "ana")
        XCTAssertEqual(contactSearches.last?.asks, true)
        XCTAssertEqual(model.rows.first?.id, "contact:fixture-ana")
        XCTAssertEqual(model.selection, 0)
        model.query = "define ana"
        XCTAssertEqual(contactSearches.last?.term, "define ana", "inside a scope no other source takes the text")
        XCTAssertFalse(model.canTabToAIChat)
    }

    func testTabEntersFilesAndTypingSearchesOnlyFiles() {
        let model = model()
        model.query = "files"
        XCTAssertTrue(model.enterSelectedSearchScope())
        XCTAssertEqual(model.searchScope, .files)
        XCTAssertEqual(model.notice, SearchScope.files.prompt)
        XCTAssertTrue(fileSearches.isEmpty)
        model.query = "quarterly"
        XCTAssertEqual(fileSearches, ["quarterly"])
        XCTAssertEqual(model.rows.first?.id, "file:/fictional/quarterly.txt")
        XCTAssertTrue(contactSearches.isEmpty)
        XCTAssertFalse(model.enterSelectedSearchScope(), "Tab inside a scope does nothing more")
    }

    func testTabOnAnotherRowLeavesTabForAIChat() {
        let model = model()
        model.query = "2 + 2"
        XCTAssertFalse(model.enterSelectedSearchScope())
        XCTAssertNil(model.scope)
        XCTAssertTrue(model.canTabToAIChat)
    }

    func testClipboardListsRecentItemsAtOnceThenSearches() {
        let model = model()
        model.query = "clipboard"
        model.activateSelection()
        XCTAssertEqual(model.searchScope, .clipboard)
        XCTAssertEqual(model.searchPlaceholder, SearchScope.clipboard.placeholder)
        XCTAssertEqual(model.rows.count, 2)
        XCTAssertTrue(model.rows.allSatisfy { $0.id.hasPrefix("clip:") })
        model.query = "invoice"
        XCTAssertEqual(model.rows.map(\.id), ["clip:1"])
        XCTAssertNotNil(model.clipboardMessage == nil ? "" : nil)
    }

    func testEscapeClearsTextFirstThenLeaves() {
        let model = model()
        model.enterSearchScope(.contacts)
        model.query = "ana"
        XCTAssertTrue(model.backOutOfScope())
        XCTAssertEqual(model.query, "")
        XCTAssertEqual(model.searchScope, .contacts, "the first Escape only clears the text")
        XCTAssertTrue(model.backOutOfScope())
        XCTAssertNil(model.scope)
        XCTAssertEqual(model.searchPlaceholder, LauncherModel.defaultSearchPlaceholder)
        XCTAssertFalse(model.backOutOfScope(), "outside a scope Escape is the launcher's")
    }

    func testBackLeavesFromAnEmptyField() {
        let model = model()
        model.enterSearchScope(.clipboard)
        model.exitScope()
        XCTAssertNil(model.scope)
        XCTAssertEqual(model.query, "")
        XCTAssertFalse(model.rows.contains { $0.id.hasPrefix("clip:") }, "back on the launcher's suggestions")
    }

    func testOneGoQueriesSearchAtOnce() {
        let model = model()
        model.query = "contacts ana"
        XCTAssertNil(model.scope)
        XCTAssertEqual(contactSearches.last?.term, "ana")
        XCTAssertEqual(model.rows.first?.id, "contact:fixture-ana")
        model.query = "files quarterly report"
        XCTAssertEqual(fileSearches.last, "quarterly report")
        model.query = "clipboard beta"
        XCTAssertEqual(model.rows.map(\.id), ["clip:2"])
        model.query = "clipboard history alpha"
        XCTAssertEqual(model.rows.map(\.id), ["clip:1"])
    }

    func testTypedShortcutsAreUnchanged() {
        let model = model()
        model.query = "@an"
        XCTAssertEqual(contactSearches.last?.term, "an")
        XCTAssertEqual(contactSearches.last?.asks, true)
        model.query = "/report"
        XCTAssertEqual(fileSearches.last, "report")
        model.query = "clip"
        XCTAssertEqual(model.rows.count, 2, "bare clip still lists history, so Return pastes the newest")
        XCTAssertTrue(model.rows.allSatisfy { $0.id.hasPrefix("clip:") })
        model.query = "clip beta"
        XCTAssertEqual(model.rows.map(\.id), ["clip:2"])
        XCTAssertNil(model.scope)
    }

    func testEmptyLauncherOffersTheScopeCommands() {
        let model = model()
        model.query = "x"
        model.query = ""
        let ids = Set(model.rows.map(\.id))
        for scope in SearchScope.allCases { XCTAssertTrue(ids.contains("core:" + scope.command.rawValue), scope.rawValue) }
    }
}

/// Records each file search term and answers with one fictional file, without Spotlight.
private final class RecordingFileSearch: FileSearch {
    var record: (String) -> Void = { _ in }

    override func search(_ term: String, completion: @escaping (SearchResult) -> Void) {
        record(term)
        completion(.success([FileEntry(id: "/fictional/\(term).txt", name: "\(term).txt", url: URL(fileURLWithPath: "/fictional/\(term).txt"), kind: "Plain Text")]))
    }
}
