import XCTest
@testable import VolantCore

/// The term and reply rules the app and the agent helper share for Spotlight file search. Paths are fictional.
final class HomeFileSearchTests: XCTestCase {
    func testTermIsTrimmedAndBounded() {
        XCTAssertEqual(HomeFileSearch.term("  invoice \n"), "invoice")
        XCTAssertNil(HomeFileSearch.term("ab"), "Shorter than three characters")
        XCTAssertNil(HomeFileSearch.term("   "))
        XCTAssertEqual(HomeFileSearch.term(String(repeating: "a", count: 200))?.count, 200)
        XCTAssertNil(HomeFileSearch.term(String(repeating: "a", count: 201)))
        XCTAssertNil(HomeFileSearch.term("in\u{0}voice"), "Control characters are refused")
        XCTAssertNil(HomeFileSearch.term("in\tvoice"))
        XCTAssertEqual(HomeFileSearch.term("Résumé 2026"), "Résumé 2026")
        XCTAssertEqual(HomeFileSearch.term("a\"b*'c"), "a\"b*'c", "Quotes and wildcards are ordinary characters; the helper passes the term as a predicate argument")
    }

    func testNoisyAndUnusablePathsAreDropped() {
        XCTAssertNotNil(HomeFileSearch.entry(path: "/Users/me/Documents/plan.md", name: "plan.md", kind: "Markdown"))
        XCTAssertNil(HomeFileSearch.entry(path: "/Users/me/Library/Caches/x", name: "x", kind: nil))
        XCTAssertNil(HomeFileSearch.entry(path: "/Users/me/.config/thing", name: "thing", kind: nil))
        XCTAssertNil(HomeFileSearch.entry(path: "/Users/me/app/build-release/App", name: "App", kind: nil))
        XCTAssertNil(HomeFileSearch.entry(path: "relative/plan.md", name: "plan.md", kind: nil))
        XCTAssertNil(HomeFileSearch.entry(path: "/Users/me/a\nb.md", name: "b.md", kind: nil))
        XCTAssertNil(HomeFileSearch.entry(path: "/" + String(repeating: "a", count: 4100), name: nil, kind: nil))
        XCTAssertTrue(HomeFileSearch.isInteresting("/Users/me/Documents/Building Plans.pdf"))
    }

    func testEntryFallsBackToFileNameAndFlattensText() throws {
        let entry = try XCTUnwrap(HomeFileSearch.entry(path: "/Users/me/Notes/today.txt", name: nil, kind: "Plain\nText"))
        XCTAssertEqual(entry.name, "today.txt")
        XCTAssertEqual(entry.kind, "Plain Text")
        let long = try XCTUnwrap(HomeFileSearch.entry(path: "/Users/me/x.txt", name: String(repeating: "n", count: 400), kind: String(repeating: "k", count: 400)))
        XCTAssertEqual(long.name.count, 255)
        XCTAssertEqual(long.kind.count, 120)
    }

    func testReplyRoundTripsAndIsReboundedOnArrival() throws {
        let entries = (0..<12).map { HomeFileSearch.Entry(path: "/Users/me/f\($0).txt", name: "f\($0).txt", kind: "Plain Text") }
        let data = try HomeFileSearch.reply(entries)
        XCTAssertEqual(HomeFileSearch.entries(from: data)?.count, 8, "At most eight entries are sent")
        let hostile = try JSONEncoder().encode([
            HomeFileSearch.Entry(path: "/Users/me/ok.txt", name: "ok.txt", kind: ""),
            HomeFileSearch.Entry(path: "not/absolute", name: "x", kind: ""),
            HomeFileSearch.Entry(path: "/Users/me/Library/Keychains/x", name: "x", kind: "")
        ] + entries)
        let parsed = try XCTUnwrap(HomeFileSearch.entries(from: hostile))
        XCTAssertEqual(parsed.first?.path, "/Users/me/ok.txt")
        XCTAssertFalse(parsed.contains { !$0.path.hasPrefix("/") || $0.path.contains("/Library/") })
        XCTAssertEqual(parsed.count, 8)
        XCTAssertNil(HomeFileSearch.entries(from: Data("{\"not\":\"a list\"}".utf8)))
        XCTAssertNil(HomeFileSearch.entries(from: Data(repeating: 32, count: 70_000)), "Oversized replies are refused")
    }

    func testHostMessageCodeHasText() {
        XCTAssertEqual(HostMessage(wire: HostMessage(.fileSearchUnavailable).wire)?.code, .fileSearchUnavailable)
    }
}
