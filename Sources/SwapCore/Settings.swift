import Foundation

public enum ClaudeSwapApp {
    public static let version = "1.0.0"
    public static let bundleID = "dev.mafex.claudeswap"
    public static let homepage = "https://github.com/mafex11/claude-swap-bar"
}

/// Preferences (domain `dev.mafex.claudeswap`). Everything machine-specific lives
/// here, never in the code: the app itself knows no account names or hosts.
public struct Settings {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private func string(_ key: String, _ fallback: String) -> String {
        let v = defaults.string(forKey: key) ?? ""
        return v.isEmpty ? fallback : v
    }

    private func expand(_ path: String) -> String { (path as NSString).expandingTildeInPath }

    /// The snapshot claude-swap writes for this Mac.
    public var statusFile: String { expand(string("statusFile", "~/.claude-swap/status.json")) }
    /// The claude-swap command: `<it> use NAME` switches account, `<it> tick` re-checks.
    public var swapCommand: String { expand(string("swapCommand", "~/.local/bin/claude-swap")) }
    /// Login helper for this Mac: `start NAME` prints a sign-in link, `finish NAME CODE` completes it.
    public var loginHelper: String { expand(string("loginHelper", "~/.claude-swap/login.sh")) }

    /// A second machine, shown as its own section. Empty name = none.
    public var remoteName: String { string("remoteName", "") }
    /// Shell command that prints the second machine's status.json, e.g. over ssh.
    public var remoteStatusCommand: String { string("remoteStatusCommand", "") }
    /// Login helper for the second machine (same `start` / `finish` contract).
    public var remoteLoginHelper: String { expand(string("remoteLoginHelper", "")) }

    public var hasRemote: Bool { !remoteName.isEmpty && !remoteStatusCommand.isEmpty }

    public var loginItemInitialized: Bool {
        get { defaults.bool(forKey: "loginItemInitialized") }
        nonmutating set { defaults.set(newValue, forKey: "loginItemInitialized") }
    }
}
