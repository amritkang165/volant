import AppKit
import VolantCore

struct FileEntry: Identifiable, Hashable {
    let id: String
    let name: String
    let url: URL
    let kind: String
}

/// Debounced file search within the owner's home folder. The Spotlight query runs in the agent
/// helper (`HomeFileSearchClient`), because inside the sandbox Spotlight returns only files the app
/// may read, which is none of the owner's. Opening or revealing a hit hands the URL to the system,
/// which the sandbox allows. With `fsearch` set (the owner turned on Use fsearch), a running fsearch
/// daemon answers first, across the whole disk with typo tolerance; if it can't, the same term goes
/// to the helper's Spotlight search. Not final so launcher tests can deliver fictional results.
class FileSearch {
    enum Failure: Error { case unavailable }
    typealias SearchResult = Result<[FileEntry], Failure>
    private let home: HomeFileSearchClient
    init(home: HomeFileSearchClient = .shared) { self.home = home }
    deinit { cancelHome?() }
    private var pending: DispatchWorkItem?
    /// Stops the helper search in flight without completing it.
    private var cancelHome: (() -> Void)?
    /// Set while Use fsearch is on.
    var fsearch: FSearchClient?
    /// Advanced by every search and cancel, so only the newest request's answer completes.
    private var generation = 0

    func search(_ term: String, completion: @escaping (SearchResult) -> Void) {
        cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pending = nil
            if let fsearch = self.fsearch, term.trimmingCharacters(in: .whitespaces).count >= 2 { self.runFSearch(fsearch, term, completion: completion) }
            else { self.runHome(term, completion: completion) }
        }
        pending = work
        // fsearch answers in about a millisecond, so it needs only enough delay to skip keystrokes.
        DispatchQueue.main.asyncAfter(deadline: .now() + (fsearch == nil ? 0.15 : 0.05), execute: work)
    }

    /// Asks fsearch, keeping only the newest request's answer. Noisy paths are hidden as for Spotlight;
    /// an error falls back to the helper's Spotlight search for the same term.
    private func runFSearch(_ fsearch: FSearchClient, _ term: String, completion: @escaping (SearchResult) -> Void) {
        generation += 1
        let request = generation
        fsearch.search(term, limit: FSearch.maximumHits) { [weak self] result in
            guard let self, request == self.generation else { return }
            switch result {
            case .success(let entries): completion(.success(Array(entries.filter { FileSearch.isInteresting($0.url.path) }.prefix(HomeFileSearch.maximumResults))))
            case .failure: self.runHome(term, completion: completion)
            }
        }
    }

    /// Asks the helper's Spotlight search, keeping only the newest request's answer. A term too
    /// short to search answers with no files rather than a failure.
    private func runHome(_ term: String, completion: @escaping (SearchResult) -> Void) {
        guard let term = HomeFileSearch.term(term) else { completion(.success([])); return }
        generation += 1
        let request = generation
        cancelHome = home.search(term) { [weak self] result in
            guard let self, request == self.generation else { return }
            self.cancelHome = nil
            completion(result)
        }
    }

    func cancel() {
        pending?.cancel()
        pending = nil
        generation += 1
        cancelHome?()
        cancelHome = nil
    }

    /// Hide library internals, caches, build products and dotfiles from the results.
    static func isInteresting(_ path: String) -> Bool { HomeFileSearch.isInteresting(path) }

    static func open(_ entry: FileEntry) { NSWorkspace.shared.open(entry.url) }
    static func reveal(_ entry: FileEntry) { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) }
}

/// The helper's Spotlight search of the owner's home folder. Each search opens a short-lived
/// connection to the agent helper and completes once on the main queue, with the helper's files or
/// `.unavailable` after an error or a timeout; cancelling ends the connection, which stops the
/// helper's query, and never completes. Tests and fixtures replace `call`.
final class HomeFileSearchClient {
    static let shared = HomeFileSearchClient()
    /// A client whose every search fails, for fixtures and tests that must not reach a helper.
    static var unavailable: HomeFileSearchClient {
        HomeFileSearchClient { _, completion in
            DispatchQueue.main.async { completion(nil, HostMessage(.fileSearchUnavailable).wire) }
            return {}
        }
    }

    /// Sends one term and returns a closure that cancels it.
    let call: (String, @escaping (Data?, String?) -> Void) -> () -> Void

    init(call: @escaping (String, @escaping (Data?, String?) -> Void) -> () -> Void = HomeFileSearchClient.helperCall) { self.call = call }

    /// Files whose names contain `term`, newest first, at most `HomeFileSearch.maximumResults`.
    func search(_ term: String, completion: @escaping (FileSearch.SearchResult) -> Void) -> () -> Void {
        call(term) { data, _ in
            guard let data, let entries = HomeFileSearch.entries(from: data) else { completion(.failure(.unavailable)); return }
            completion(.success(entries.map(HomeFileSearchClient.fileEntry)))
        }
    }

    static func fileEntry(_ entry: HomeFileSearch.Entry) -> FileEntry {
        FileEntry(id: entry.path, name: entry.name, url: URL(fileURLWithPath: entry.path), kind: entry.kind)
    }

    /// One search over its own connection. Completes once on the main queue, after the helper
    /// replies, the connection fails, or the time limit plus a second passes.
    private static func helperCall(_ term: String, completion: @escaping (Data?, String?) -> Void) -> () -> Void {
        let connection = NSXPCConnection(serviceName: "com.mysticcoders.volant.AgentHost")
        connection.remoteObjectInterface = NSXPCInterface(with: VolantAgentHostProtocol.self)
        let lock = NSLock()
        var finished = false
        let finish: (Data?, String?, Bool) -> Void = { data, error, deliver in
            lock.lock()
            guard !finished else { lock.unlock(); return }
            finished = true
            lock.unlock()
            connection.invalidate()
            if deliver { DispatchQueue.main.async { completion(data, error) } }
        }
        let unavailable = HostMessage(.fileSearchUnavailable).wire
        connection.invalidationHandler = { finish(nil, unavailable, true) }
        connection.interruptionHandler = { finish(nil, unavailable, true) }
        connection.resume()
        DispatchQueue.main.asyncAfter(deadline: .now() + HomeFileSearch.timeLimit + 1) { finish(nil, unavailable, true) }
        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in finish(nil, unavailable, true) }) as? VolantAgentHostProtocol else {
            finish(nil, unavailable, true)
            return {}
        }
        proxy.searchHomeFiles(term: term) { data, error in finish(data, error, true) }
        return { finish(nil, nil, false) }
    }
}
