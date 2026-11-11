import AppKit
import Combine
import VolantCore

/// A blocked app or website the owner just tried to reach, shown in the reminder panel.
struct FocusReminder: Identifiable, Equatable {
    let id = UUID()
    let target: FocusTarget
    /// The app's or site's name, as the reminder shows it.
    let name: String
    let goal: String
}

/// Runs the owner's Focus session: keeps its timer, hides blocked apps when they come forward, and
/// saves the session so it survives relaunch. Page addresses are never stored here. The clock,
/// state file and app hiding are injected, so tests drive it without real apps or time.
final class FocusController: ObservableObject {
    @Published private(set) var session: FocusSession?
    /// Ticks once a second while a session runs, so views showing the time left redraw.
    @Published private(set) var now: Date
    @Published private(set) var reminder: FocusReminder?
    @Published private(set) var error: String?
    /// The focus bar's place: floating over windows, or text in the menu bar.
    @Published var docked: Bool {
        didSet { defaults.set(docked, forKey: Self.dockedKey) }
    }

    /// Called when a session completes, by time or by the owner, to celebrate it.
    var onComplete: () -> Void = {}

    private let clock: () -> Date
    private let stateURL: URL
    private let defaults: UserDefaults
    private let hide: (NSRunningApplication) -> Bool
    private let frontmost: () -> NSRunningApplication?
    private let automaticTimer: Bool
    private var timer: Timer?
    private var activationObserver: NSObjectProtocol?

    static let dockedKey = "focusBarDocked"
    static var defaultStateURL: URL { Preferences.supportDirectory.appendingPathComponent("focus-session.json") }

    init(stateURL: URL = FocusController.defaultStateURL, defaults: UserDefaults = .standard, clock: @escaping () -> Date = Date.init,
         hide: @escaping (NSRunningApplication) -> Bool = { $0.hide() },
         frontmost: @escaping () -> NSRunningApplication? = { NSWorkspace.shared.frontmostApplication },
         automaticTimer: Bool = true, restore: Bool = true) {
        self.stateURL = stateURL
        self.defaults = defaults
        self.clock = clock
        self.hide = hide
        self.frontmost = frontmost
        self.automaticTimer = automaticTimer
        now = clock()
        docked = defaults.bool(forKey: Self.dockedKey)
        if restore { restoreSavedSession() }
    }

    deinit {
        timer?.invalidate()
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
    }

    var isRunning: Bool { session != nil }

    /// Starts a session, replacing any running one, and hides a blocked app already in front.
    func start(_ setup: FocusSetup) {
        let at = clock()
        session = FocusSession(setup: setup, at: at)
        reminder = nil
        error = nil
        sessionChanged()
        if let app = frontmost() { handleActivation(of: app) }
    }

    func pause() { mutate { $0.pause(at: clock()) } }

    func resume() {
        mutate { $0.resume(at: clock()) }
        if let app = frontmost() { handleActivation(of: app) }
    }

    func edit(_ setup: FocusSetup) {
        mutate { $0.edit(setup, at: clock()) }
        if let app = frontmost() { handleActivation(of: app) }
    }

    /// Ends the session as done and celebrates it.
    func complete() {
        guard session != nil else { return }
        finish()
        onComplete()
    }

    /// Ends the session without celebrating.
    func end() {
        guard session != nil else { return }
        finish()
    }

    /// Lets the reminder's app or site through for the snooze length and closes the reminder.
    func snooze(_ reminder: FocusReminder, minutes: Int) {
        guard self.reminder?.id == reminder.id else { return }
        mutate { $0.snooze(reminder.target, minutes: minutes, at: clock()) }
        self.reminder = nil
    }

    func dismissReminder() { reminder = nil }

    /// Hides `app` and shows a reminder when the running session blocks it. Never quits the app.
    func handleActivation(of app: NSRunningApplication) {
        guard let bundleIdentifier = app.bundleIdentifier, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        handleActivation(bundleIdentifier: bundleIdentifier, name: app.localizedName) { [hide] in hide(app) }
    }

    /// The decision behind `handleActivation(of:)`, separate from `NSRunningApplication` so tests
    /// can drive it with any bundle identifier.
    func handleActivation(bundleIdentifier: String, name: String?, hideApp: () -> Bool) {
        guard let session, session.blocks(app: bundleIdentifier, at: clock()) else { return }
        _ = hideApp()
        reminder = FocusReminder(target: .app(bundleIdentifier), name: name ?? bundleIdentifier, goal: session.setup.goal)
    }

    /// The time left as the focus bar shows it: `24:59`, `1:05:00`, or nil for an untimed session.
    static func clockText(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded(.up))
        let hours = total / 3600, minutes = total / 60 % 60, seconds = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, seconds) : String(format: "%d:%02d", minutes, seconds)
    }

    /// The bar's time: what's left, or how long an untimed session has run.
    func timeText() -> String {
        guard let session else { return "" }
        if let remaining = session.remaining(at: now) { return Self.clockText(remaining) }
        return Self.clockText(max(0, now.timeIntervalSince(session.startedAt)))
    }

    /// Advances the clock: finishes an expired session and redraws the time. The timer calls it each
    /// second; tests call it directly.
    func tick() {
        now = clock()
        guard let session else { return }
        if session.isFinished(at: now) { complete() }
    }

    private func mutate(_ change: (inout FocusSession) -> Void) {
        guard var current = session else { return }
        change(&current)
        session = current
        sessionChanged()
    }

    private func finish() {
        session = nil
        reminder = nil
        sessionChanged()
    }

    /// Saves the session, and starts or stops the timer and the app observer to match it.
    private func sessionChanged() {
        now = clock()
        save()
        if session == nil {
            timer?.invalidate()
            timer = nil
            stopObserving()
        } else {
            startObserving()
            if automaticTimer, timer == nil {
                let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
                RunLoop.main.add(timer, forMode: .common)
                self.timer = timer
            }
        }
    }

    private func startObserving() {
        guard activationObserver == nil, automaticTimer else { return }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.handleActivation(of: app)
        }
    }

    private func stopObserving() {
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        activationObserver = nil
    }

    /// Writes the running session, or removes the file once none runs. A failed write is shown,
    /// not fatal: the session keeps running in memory.
    private func save() {
        do {
            if let session {
                try JSONEncoder().encode(session).write(to: stateURL, options: .atomic)
            } else if FileManager.default.fileExists(atPath: stateURL.path) {
                try FileManager.default.removeItem(at: stateURL)
            }
            error = nil
        } catch {
            self.error = String(localized: "Volant couldn’t save the Focus session, so it won’t survive a restart.", comment: "Focus error when the session file can't be written")
        }
    }

    /// Picks up a session saved before relaunch, unless it has already run out.
    private func restoreSavedSession() {
        guard let data = try? Data(contentsOf: stateURL), let saved = try? JSONDecoder().decode(FocusSession.self, from: data) else { return }
        if saved.isFinished(at: clock()) {
            try? FileManager.default.removeItem(at: stateURL)
            return
        }
        session = saved
        sessionChanged()
    }
}
