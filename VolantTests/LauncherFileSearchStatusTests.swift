import CryptoKit
import VolantCore
import XCTest
@testable import Volant

/// The launcher's "Searching files…" status and "No files match" notice, with file searches that
/// answer only when a test says so. Nothing searches the owner's Mac; paths are fictional.
@MainActor
final class LauncherFileSearchStatusTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("file-status-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func model(_ files: HeldFileSearch, merged: Bool = false) -> LauncherModel {
        let model = LauncherModel(index: AppIndex(entries: []),
            clipboard: ClipboardStore(retention: 10, storageURL: root.appendingPathComponent("clips.sqlite"), encryptionKey: SymmetricKey(size: .bits256)),
            notes: NotesStore(directory: root.appendingPathComponent("Notes")), config: Preferences(),
            usage: UsageStore(url: root.appendingPathComponent("usage.sqlite")), files: files) { _ in }
        model.searchesSecondarySources = merged
        model.appleShortcuts.loadOverride = { $0([], nil) }
        model.searchContacts = { _, _, completion in completion([]) }
        model.dismiss = {}
        return model
    }

    /// Waits past the status delay.
    private func waitForStatus() async { try? await Task.sleep(for: .seconds(LauncherModel.fileSearchStatusDelay + 0.15)) }

    private func file(_ name: String) -> FileEntry {
        FileEntry(id: "/fictional/\(name)", name: name, url: URL(fileURLWithPath: "/fictional/\(name)"), kind: "Plain Text")
    }

    func testFilesScopeShowsSearchingThenResults() async {
        let files = HeldFileSearch()
        let model = model(files)
        model.enterSearchScope(.files)
        model.query = "report"
        XCTAssertFalse(model.searchingFiles, "Not before the delay, so fast replies never flicker")
        XCTAssertEqual(model.emptyStateMessage, "", "No \"No results\" while the answer is on its way")
        await waitForStatus()
        XCTAssertTrue(model.searchingFiles)
        XCTAssertEqual(model.emptyStateMessage, String(localized: "Searching files…", comment: "Launcher status while a file search is in progress"))
        files.answer(.success([file("report.pdf")]))
        XCTAssertFalse(model.searchingFiles)
        XCTAssertEqual(model.rows.map(\.id), ["file:/fictional/report.pdf"])
    }

    func testFastRepliesNeverShowTheStatus() async {
        let files = HeldFileSearch()
        let model = model(files)
        model.query = "/report"
        files.answer(.success([file("report.pdf")]))
        await waitForStatus()
        XCTAssertFalse(model.searchingFiles)
    }

    func testNothingFoundSaysSoAlone() async {
        let files = HeldFileSearch()
        let model = model(files)
        model.query = "/zzqx"
        await waitForStatus()
        files.answer(.success([]))
        XCTAssertFalse(model.searchingFiles)
        XCTAssertTrue(model.sections.isEmpty)
        XCTAssertEqual(model.emptyStateMessage, String(localized: "No files match “\("zzqx", format: .verbatim)”.", comment: "Launcher notice when a file search finds nothing; the value is the typed name"))
        model.query = "/ab"
        files.answer(.success([]))
        XCTAssertEqual(model.emptyStateMessage, SearchScope.files.prompt, "A term too short to search asks for more, not \"No files match\"")
    }

    func testUnavailableClearsTheStatusForRetry() async {
        let files = HeldFileSearch()
        let model = model(files)
        model.enterSearchScope(.files)
        model.query = "report"
        await waitForStatus()
        files.answer(.failure(.unavailable))
        XCTAssertFalse(model.searchingFiles)
        XCTAssertNotNil(model.searchRecoveryMessage, "Retry Spotlight shows instead")
    }

    func testNewQueryAndLeavingTheScopeClearTheStatus() async {
        let files = HeldFileSearch()
        let model = model(files)
        model.enterSearchScope(.files)
        model.query = "report"
        await waitForStatus()
        XCTAssertTrue(model.searchingFiles)
        model.query = "reports"
        XCTAssertFalse(model.searchingFiles, "A new query starts over")
        let superseded = files.held.first
        superseded?.1(.success([file("report.pdf")]))
        XCTAssertTrue(model.rows.isEmpty, "The old query's answer is dropped")
        await waitForStatus()
        XCTAssertTrue(model.searchingFiles)
        model.exitScope()
        XCTAssertFalse(model.searchingFiles)
    }

    func testMergedSearchShowsTheStatusOnlyWithoutFileRows() async {
        let files = HeldFileSearch()
        let model = model(files, merged: true)
        model.query = "report"
        await waitForStatus()
        XCTAssertTrue(model.searchingFiles, "Merged search shows the quiet line while files are pending")
        files.answer(.success([file("report.pdf")]))
        XCTAssertFalse(model.searchingFiles)
        XCTAssertTrue(model.rows.contains { $0.id == "file:/fictional/report.pdf" })
        model.query = "report."
        await waitForStatus()
        XCTAssertFalse(model.searchingFiles, "Matching rows from the previous query stay instead of the status")
        files.answer(.success([]))
        XCTAssertFalse(model.searchingFiles)
    }
}

/// Holds each file search until `answer` is called; the newest search answers first.
private final class HeldFileSearch: FileSearch {
    private(set) var held: [(String, (SearchResult) -> Void)] = []

    init() { super.init(home: .unavailable) }

    override func search(_ term: String, completion: @escaping (SearchResult) -> Void) { held.append((term, completion)) }

    override func cancel() {}

    /// Answers the newest held search.
    func answer(_ result: SearchResult) { held.popLast()?.1(result) }
}
