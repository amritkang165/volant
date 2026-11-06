import Foundation
import VolantCore

/// Runs the launcher's Spotlight file search for the sandboxed app, which can't: inside the sandbox
/// Spotlight returns only files the app may read, so none of the owner's. One query runs at a time;
/// a newer search stops the one in flight and its caller gets an empty, superseded reply. Each search
/// replies exactly once, after Spotlight finishes gathering or after `HomeFileSearch.timeLimit` with
/// whatever was found by then. Terms and paths are never logged.
final class HomeFileSearchHost {
    /// Every query runs and reports on this queue, so no run loop is needed in the XPC service.
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.name = "com.mysticcoders.volant.home-file-search"
        return queue
    }()
    private var current: Search?
    private let home: String

    init(home: String = HomeFileSearchHost.ownerHome()) { self.home = home }

    /// Searches the owner's home folder for `term` and replies with JSON `[HomeFileSearch.Entry]`,
    /// or nil and a `HostMessage` code when the term is invalid or Spotlight can't start.
    func search(_ term: String, reply: @escaping (Data?, String?) -> Void) {
        guard let term = HomeFileSearch.term(term) else { reply(nil, HostMessage(.fileSearchUnavailable).wire); return }
        queue.addOperation { [self] in
            current?.finish(superseded: true)
            let search = Search(term: term, home: home, queue: queue, reply: reply)
            current = search
            search.start()
        }
    }

    /// Stops any query in flight, answering its caller with an empty reply.
    func stop() { queue.addOperation { [self] in current?.finish(superseded: true); current = nil } }

    /// The owner's real home folder from the user database, which an unsandboxed process shares
    /// with `NSHomeDirectory()`, read directly so a changed environment can't redirect it.
    static func ownerHome() -> String {
        if let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir { return String(cString: dir) }
        return NSHomeDirectory()
    }

    /// One Spotlight query and its single reply.
    private final class Search {
        private let query = NSMetadataQuery()
        private let queue: OperationQueue
        private var reply: ((Data?, String?) -> Void)?
        private var observer: NSObjectProtocol?

        init(term: String, home: String, queue: OperationQueue, reply: @escaping (Data?, String?) -> Void) {
            self.queue = queue
            self.reply = reply
            query.operationQueue = queue
            query.predicate = NSPredicate(format: "kMDItemFSName CONTAINS[cd] %@ AND kMDItemContentType != 'com.apple.application-bundle'", term)
            query.searchScopes = [URL(fileURLWithPath: home, isDirectory: true)]
            query.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSContentChangeDateKey, ascending: false)]
        }

        /// Starts the query and the time limit; a query Spotlight refuses replies with an error at once.
        func start() {
            observer = NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: query, queue: nil) { [weak self] _ in
                self?.finish(superseded: false)
            }
            guard query.start() else {
                respond(nil, HostMessage(.fileSearchUnavailable).wire)
                return
            }
            let deadline = DispatchTime.now() + HomeFileSearch.timeLimit
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: deadline) { [weak self, queue] in
                queue.addOperation { self?.finish(superseded: false) }
            }
        }

        /// Stops the query and replies with the newest interesting results gathered so far, or an
        /// empty list when a newer search replaced this one. Later calls do nothing.
        func finish(superseded: Bool) {
            guard reply != nil else { return }
            query.disableUpdates()
            var entries: [HomeFileSearch.Entry] = []
            if !superseded {
                for index in 0..<min(query.resultCount, HomeFileSearch.scannedResults) where entries.count < HomeFileSearch.maximumResults {
                    guard let item = query.result(at: index) as? NSMetadataItem,
                          let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
                          let entry = HomeFileSearch.entry(path: path, name: item.value(forAttribute: NSMetadataItemDisplayNameKey) as? String,
                                                           kind: item.value(forAttribute: kMDItemKind as String) as? String) else { continue }
                    entries.append(entry)
                }
            }
            if let data = try? HomeFileSearch.reply(entries) { respond(data, nil) } else { respond(nil, HostMessage(.fileSearchUnavailable).wire) }
        }

        /// Sends the one reply and releases the query.
        private func respond(_ data: Data?, _ error: String?) {
            guard let reply else { return }
            self.reply = nil
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            query.stop()
            reply(data, error)
        }
    }
}
