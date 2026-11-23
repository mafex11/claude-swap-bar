import Foundation

/// Every word and number the app shows, worked out from a snapshot. Pure, so it
/// can be tested without a menu bar.
public enum Presentation {
    /// A snapshot older than this means claude-swap has stopped ticking.
    public static let staleAfter: Double = 5 * 60
    /// Logins last about 30 days; start warning this long before one runs out.
    public static let loginWarning: Double = 3 * 86400

    public enum Tone: Equatable { case normal, good, warn, bad, dim }

    /// "45m", "1h02m", "3d": how long until `t`.
    public static func until(_ t: Double, now: Double) -> String {
        let mins = max(0, Int(((t - now) / 60).rounded()))
        if mins < 60 { return "\(mins)m" }
        if mins < 48 * 60 { return "\(mins / 60)h" + String(format: "%02d", mins % 60) + "m" }
        return "\(mins / 1440)d"
    }

    /// "just now", "4m ago", "3h ago", "2d ago".
    public static func ago(_ t: Double, now: Double) -> String {
        let mins = max(0, Int((now - t) / 60))
        if mins < 1 { return "just now" }
        if mins < 60 { return "\(mins)m ago" }
        if mins < 48 * 60 { return "\(mins / 60)h ago" }
        return "\(mins / 1440)d ago"
    }

    public static func clock(_ t: Double) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: Date(timeIntervalSince1970: t))
    }

    public static func isStale(_ snapshot: Snapshot, now: Double) -> Bool {
        now - snapshot.writtenAt > staleAfter
    }

    /// Session usage that still counts: a window whose reset time has passed is 0.
    public static func sessionPercent(_ a: Account, now: Double) -> Int {
        if let reset = a.sessionResetsAt, reset <= now { return 0 }
        return Int(a.sessionPercent.rounded())
    }

    public static func usageTone(_ percent: Int) -> Tone {
        percent < 70 ? .good : percent < 90 ? .warn : .bad
    }

    /// The line under an account's name.
    public static func note(_ a: Account, now: Double) -> (text: String, tone: Tone) {
        switch a.login {
        case .missing: return ("Not logged in here", .dim)
        case .loggedOut: return ("Logged out", .bad)
        case .ok: break
        }
        if let expires = a.loginExpiresAt, expires - now < loginWarning {
            return (expires > now ? "Login expires in \(until(expires, now: now))" : "Login past its expiry", .warn)
        }
        if let reset = a.sessionResetsAt, reset > now {
            return ("Renews \(clock(reset)) · in \(until(reset, now: now))", .normal)
        }
        return ("Fresh · starts when used", .normal)
    }

    /// Weekly limits, e.g. "week 38% · sonnet 12%". Windows already reset are left out.
    public static func weekly(_ a: Account, now: Double) -> String {
        a.weekly
            .filter { $0.resetsAt.map { $0 > now } ?? true }
            .map { "\($0.label == "all" ? "week" : $0.label) \(Int($0.percent.rounded()))%" }
            .joined(separator: " · ")
    }

    public static func working(_ s: Snapshot) -> [Account] { s.accounts.filter { $0.login == .ok } }
    public static func loggedOut(_ s: Snapshot) -> [Account] { s.accounts.filter { $0.login == .loggedOut } }

    /// Session headroom left across every working account, in percent points.
    public static func totalLeft(_ s: Snapshot, now: Double) -> Int {
        working(s).reduce(0) { $0 + 100 - sessionPercent($1, now: now) }
    }

    public static func extraUSD(_ s: Snapshot) -> Double {
        s.accounts.reduce(0) { $0 + ($1.extraUsd ?? 0) }
    }

    /// The text next to the menu bar icon and whether something needs attention.
    public static func menuBar(_ s: Snapshot?, now: Double) -> (title: String, attention: Bool) {
        guard let s else { return ("–", true) }
        let out = !loggedOut(s).isEmpty
        guard let a = s.accounts.first(where: { $0.active }) else { return ("?", true) }
        if isStale(s, now: now) { return ("\(a.name) ?", true) }
        let pct = sessionPercent(a, now: now)
        return ("\(a.name) \(pct)%", out || a.login != .ok)
    }

    /// One line summing a machine up.
    public static func summary(_ s: Snapshot, now: Double) -> String {
        let ok = working(s).count
        var parts = ["\(totalLeft(s, now: now))% left across \(ok) account\(ok == 1 ? "" : "s")"]
        let out = loggedOut(s).count
        if out > 0 { parts.append("\(out) logged out") }
        return parts.joined(separator: " · ")
    }
}
