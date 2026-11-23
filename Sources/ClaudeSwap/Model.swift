import AppKit
import Foundation
import SwapCore

/// One machine's section: its latest snapshot, or why there isn't one.
struct Machine {
    var title: String
    var isRemote: Bool
    var snapshot: Snapshot?
    var problem: String?
    var loginHelper: String?
}

/// A login in progress for one account, driven by the user's login helper.
struct LoginFlow {
    enum Phase: Equatable { case starting, waitingForCode, finishing, failed(String) }
    var account: Account
    var isRemote: Bool
    var helper: String
    var phase: Phase = .starting
    var link: URL?
    var code = ""
}

@MainActor
final class Model: ObservableObject {
    @Published var local: Machine
    @Published var remote: Machine?
    @Published var now = Date().timeIntervalSince1970
    @Published var login: LoginFlow?
    /// What the app is doing right now ("Switching to t3…"), shown in the footer.
    @Published var busy: String?
    @Published var notice: String?

    let settings = Settings()
    private var timers: [Timer] = []
    private var remoteFetchedAt: Double = 0
    private var remoteFetching = false

    /// `statusFile` overrides the configured one and turns off the timers and the
    /// second machine: a fixed picture of one file, for `--render`.
    private let statusFileOverride: String?

    init(statusFile: String? = nil) {
        statusFileOverride = statusFile
        local = Machine(title: "This Mac", isRemote: false)
        if statusFile != nil {
            local.loginHelper = "render"  // so the picture shows the Log in buttons
            reloadLocal()
            if let written = local.snapshot?.writtenAt { now = written + 20; reloadLocal(keepClock: true) }
            return
        }
        local.loginHelper = Self.existing(settings.loginHelper)
        if settings.hasRemote {
            remote = Machine(title: settings.remoteName, isRemote: true,
                             loginHelper: Self.existing(settings.remoteLoginHelper))
        }
        reloadLocal()
        fetchRemote()
        // claude-swap rewrites the file every minute; looking every 15 s keeps the
        // menu bar within seconds of it without a file watcher.
        timers.append(.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reloadLocal() }
        })
        timers.append(.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.fetchRemote() }
        })
    }

    private static func existing(_ path: String) -> String? {
        !path.isEmpty && FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    // MARK: reading

    func reloadLocal(keepClock: Bool = false) {
        if !keepClock { now = Date().timeIntervalSince1970 }
        let path = statusFileOverride ?? settings.statusFile
        guard let data = FileManager.default.contents(atPath: path) else {
            local.snapshot = nil
            local.problem = "No status yet. claude-swap writes \(path.replacingOccurrences(of: NSHomeDirectory(), with: "~")) on every tick."
            return
        }
        do {
            let snapshot = try Snapshot.decode(data)
            local.snapshot = snapshot
            local.problem = Presentation.isStale(snapshot, now: now)
                ? "claude-swap last ran \(Presentation.ago(snapshot.writtenAt, now: now)). It may have stopped."
                : nil
        } catch {
            local.problem = "Can't read the status file (written by a newer claude-swap?)."
        }
    }

    /// Fetches the second machine's snapshot. `force` skips the 30 s freshness check.
    func fetchRemote(force: Bool = false) {
        guard settings.hasRemote, !remoteFetching, force || now - remoteFetchedAt > 30 else { return }
        remoteFetching = true
        let command = settings.remoteStatusCommand, name = settings.remoteName
        Task.detached {
            let result = Shell.run(command, timeout: 20)
            await MainActor.run {
                self.remoteFetching = false
                self.remoteFetchedAt = Date().timeIntervalSince1970
                if result.ok, let data = result.output.data(using: .utf8),
                   let snapshot = try? Snapshot.decode(data) {
                    self.remote?.snapshot = snapshot
                    self.remote?.problem = nil
                } else {
                    // Keep the last snapshot on screen, marked as old.
                    let seen = self.remote?.snapshot.map { " Showing \(Presentation.ago($0.writtenAt, now: self.now))'s numbers." } ?? ""
                    self.remote?.problem = "Can't reach \(name) (off, asleep or not on the network)." + seen
                }
            }
        }
    }

    func opened() {
        guard statusFileOverride == nil else { return }
        reloadLocal()
        fetchRemote()
    }

    // MARK: actions

    /// Runs a helper off the main thread, showing `label` meanwhile.
    private func run(_ label: String, _ command: String, timeout: TimeInterval = 60,
                     then: @escaping @MainActor (Shell.Result) -> Void) {
        busy = label
        Task.detached {
            let result = Shell.run(command, timeout: timeout)
            await MainActor.run {
                self.busy = nil
                then(result)
            }
        }
    }

    func refresh() {
        notice = nil
        fetchRemote(force: true)
        run("Checking usage…", "\(Shell.quote(settings.swapCommand)) tick") { _ in self.reloadLocal() }
    }

    func use(_ account: Account) {
        notice = nil
        run("Switching to \(account.name)…", "\(Shell.quote(settings.swapCommand)) use \(Shell.quote(account.email))") { result in
            self.notice = result.ok ? nil : "Couldn't switch: \(result.lastLine)"
            self.reloadLocal()
        }
    }

    func startLogin(_ account: Account, on machine: Machine) {
        guard let helper = machine.loginHelper else { return }
        notice = nil
        login = LoginFlow(account: account, isRemote: machine.isRemote, helper: helper)
        let command = "\(Shell.quote(helper)) start \(Shell.quote(account.name))"
        Task.detached {
            let result = Shell.run(command, timeout: 90)
            await MainActor.run {
                guard self.login?.account.id == account.id else { return }  // cancelled meanwhile
                if result.ok, let url = URL(string: result.lastLine), url.scheme == "https" {
                    self.login?.link = url
                    self.login?.phase = .waitingForCode
                    NSWorkspace.shared.open(url)
                } else {
                    self.login?.phase = .failed(result.lastLine.isEmpty ? "The login helper printed no sign-in link." : result.lastLine)
                }
            }
        }
    }

    func finishLogin() {
        guard var flow = login, flow.phase == .waitingForCode else { return }
        let code = flow.code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }
        flow.phase = .finishing
        login = flow
        let command = "\(Shell.quote(flow.helper)) finish \(Shell.quote(flow.account.name)) \(Shell.quote(code))"
        let swap = settings.swapCommand
        Task.detached {
            let result = Shell.run(command, timeout: 120)
            // Let claude-swap notice the new login straight away.
            if result.ok, !flow.isRemote { _ = Shell.run("\(Shell.quote(swap)) tick") }
            await MainActor.run {
                if result.ok {
                    self.login = nil
                    self.notice = "\(flow.account.name) is logged in again."
                    self.reloadLocal()
                    self.fetchRemote(force: true)
                } else {
                    self.login?.phase = .failed(result.lastLine.isEmpty ? "The login didn't complete." : result.lastLine)
                }
            }
        }
    }

    func cancelLogin() { login = nil }
}
