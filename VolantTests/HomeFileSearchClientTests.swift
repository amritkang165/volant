import VolantCore
import XCTest
@testable import Volant

/// File search through the agent helper's Spotlight query, with a fake helper call instead of XPC.
/// Paths are fictional.
@MainActor
final class HomeFileSearchClientTests: XCTestCase {
    private func search(_ files: FileSearch, _ term: String) async -> FileSearch.SearchResult {
        await withCheckedContinuation { continuation in files.search(term) { continuation.resume(returning: $0) } }
    }

    func testHelperResultsBecomeFileRows() async throws {
        var terms: [String] = []
        let files = FileSearch(home: HomeFileSearchClient { term, completion in
            terms.append(term)
            completion(try? HomeFileSearch.reply([HomeFileSearch.Entry(path: "/Users/me/Documents/Q3 report.pdf", name: "Q3 report.pdf", kind: "PDF document")]), nil)
            return {}
        })
        guard case .success(let entries) = await search(files, "  report ") else { return XCTFail("Expected files") }
        XCTAssertEqual(terms, ["report"], "The helper receives the trimmed term")
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entry.id, "/Users/me/Documents/Q3 report.pdf")
        XCTAssertEqual(entry.url.path, "/Users/me/Documents/Q3 report.pdf")
        XCTAssertEqual(entry.name, "Q3 report.pdf")
        XCTAssertEqual(entry.kind, "PDF document")
    }

    func testShortTermsNeverReachTheHelper() async {
        var calls = 0
        let files = FileSearch(home: HomeFileSearchClient { _, completion in calls += 1; completion(nil, nil); return {} })
        guard case .success(let entries) = await search(files, "re") else { return XCTFail("A short term is an empty answer, not a failure") }
        XCTAssertTrue(entries.isEmpty)
        XCTAssertEqual(calls, 0)
    }

    func testHelperFailureOrMalformedReplyIsUnavailable() async {
        let failing = FileSearch(home: .unavailable)
        guard case .failure(.unavailable) = await search(failing, "invoice") else { return XCTFail("Expected unavailable") }
        let malformed = FileSearch(home: HomeFileSearchClient { _, completion in completion(Data("nope".utf8), nil); return {} })
        guard case .failure(.unavailable) = await search(malformed, "invoice") else { return XCTFail("A malformed reply is unavailable, never an empty list") }
    }

    func testHelperRepliesAreReboundedAndFiltered() async {
        let reply = try? JSONEncoder().encode([HomeFileSearch.Entry(path: "/Users/me/Library/Caches/invoice", name: "invoice", kind: "")]
            + (0..<10).map { HomeFileSearch.Entry(path: "/Users/me/invoice-\($0).pdf", name: "invoice-\($0).pdf", kind: "PDF document") })
        let files = FileSearch(home: HomeFileSearchClient { _, completion in completion(reply, nil); return {} })
        guard case .success(let entries) = await search(files, "invoice") else { return XCTFail("Expected files") }
        XCTAssertEqual(entries.count, 8)
        XCTAssertFalse(entries.contains { $0.url.path.contains("/Library/") })
    }

    func testCancelStopsTheHelperSearchWithoutCompleting() async {
        var started = false
        var cancelled = false
        let files = FileSearch(home: HomeFileSearchClient { _, _ in started = true; return { cancelled = true } })
        var answered = false
        files.search("invoice") { _ in answered = true }
        for _ in 0..<100 where !started { try? await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(started)
        files.cancel()
        XCTAssertTrue(cancelled)
        XCTAssertFalse(answered)
    }
}
