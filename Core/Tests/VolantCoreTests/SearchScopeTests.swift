import VolantCore
import XCTest

/// Which typed queries name a Contacts, Files or Clipboard scope, which search one in one go, and the
/// typed shortcut each routes through.
final class SearchScopeTests: XCTestCase {
    func testScopeWordsShowTheirCommand() {
        XCTAssertEqual(SearchScope.command(for: "contacts"), .contacts)
        XCTAssertEqual(SearchScope.command(for: "  People "), .contacts)
        XCTAssertEqual(SearchScope.command(for: "files"), .files)
        XCTAssertEqual(SearchScope.command(for: "file"), .files)
        XCTAssertEqual(SearchScope.command(for: "Clipboard"), .clipboard)
        XCTAssertEqual(SearchScope.command(for: "clipboard  history"), .clipboard)
        XCTAssertNil(SearchScope.command(for: "clip"), "bare clip keeps listing clipboard history")
        XCTAssertNil(SearchScope.command(for: "contact"))
        XCTAssertNil(SearchScope.command(for: "contacts jane"))
    }

    func testOneGoQueriesSearchTheirScope() {
        XCTAssertEqual(SearchScope.oneShot("contacts jane")?.scope, .contacts)
        XCTAssertEqual(SearchScope.oneShot("contacts jane")?.term, "jane")
        XCTAssertEqual(SearchScope.oneShot("People  Ana Ruiz")?.term, "Ana Ruiz")
        XCTAssertEqual(SearchScope.oneShot("files quarterly report")?.scope, .files)
        XCTAssertEqual(SearchScope.oneShot("files quarterly report")?.term, "quarterly report")
        XCTAssertEqual(SearchScope.oneShot("clipboard history invoice")?.term, "invoice", "the longer phrase wins")
        XCTAssertEqual(SearchScope.oneShot("clipboard invoice")?.term, "invoice")
        XCTAssertNil(SearchScope.oneShot("clipboard history"), "naming the scope shows its command instead")
        XCTAssertNil(SearchScope.oneShot("file merge"), "singular file stays an ordinary search")
        XCTAssertNil(SearchScope.oneShot("contacts"))
        XCTAssertNil(SearchScope.oneShot("contactsjane"))
        XCTAssertNil(SearchScope.oneShot("safari"))
    }

    func testScopesRouteThroughTheirTypedShortcut() {
        XCTAssertEqual(SearchScope.contacts.shortcutQuery("jane"), "@jane")
        XCTAssertEqual(SearchScope.files.shortcutQuery("report"), "/report")
        XCTAssertEqual(SearchScope.clipboard.shortcutQuery("invoice"), "clip invoice")
        XCTAssertTrue(SearchScope.contacts.waitsForInput)
        XCTAssertTrue(SearchScope.files.waitsForInput)
        XCTAssertFalse(SearchScope.clipboard.waitsForInput)
    }

    func testEachScopeHasItsCommand() {
        for scope in SearchScope.allCases {
            XCTAssertEqual(SearchScope(command: scope.command), scope)
            XCTAssertTrue(CoreCommand.allCases.contains(scope.command))
        }
        XCTAssertNil(SearchScope(command: .notes))
        XCTAssertTrue(CoreCommand.search("people").contains(.contacts))
        XCTAssertTrue(CoreCommand.search("clipboard history").contains(.clipboard))
    }

    func testScopeWordsAreReserved() {
        for word in ["contacts", "people jane", "files", "file", "clipboard", "clipboard history"] {
            XCTAssertTrue(LauncherRouting.isReserved(word), word)
        }
    }
}
