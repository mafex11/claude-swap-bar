import Foundation

/// What claude-swap writes to `~/.claude-swap/status.json` on every tick: each
/// account's login state and usage. It never contains tokens.
public struct Snapshot: Codable, Equatable {
    public var version: Int
    public var writtenAt: Double
    public var machine: String
    public var threshold: Double
    public var active: String?
    public var lastSwapAt: Double?
    public var accounts: [Account]

    public static func decode(_ data: Data) throws -> Snapshot {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Snapshot.self, from: data)
    }
}

public enum LoginState: String, Codable {
    /// Logged in and usable.
    case ok
    /// The login expired or was signed out; it has to be logged in again.
    case loggedOut = "logged_out"
    /// Never logged in on this machine.
    case missing

    public init(from decoder: Decoder) throws {
        // A state this version doesn't know is safest shown as "needs a login".
        self = LoginState(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .loggedOut
    }
}

public struct Window: Codable, Equatable {
    public var label: String
    public var percent: Double
    public var resetsAt: Double?
}

public struct Account: Codable, Equatable, Identifiable {
    public var email: String
    public var name: String
    public var login: LoginState
    public var active: Bool
    public var sessionPercent: Double
    public var sessionResetsAt: Double?
    public var weekly: [Window]
    public var extraUsd: Double?
    public var checkedAt: Double?
    public var loginExpiresAt: Double?

    public var id: String { email }
}
