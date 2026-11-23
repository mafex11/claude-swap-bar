import XCTest
@testable import SwapCore

final class PresentationTests: XCTestCase {
    let now: Double = 1_800_000_000

    func account(_ name: String, login: LoginState = .ok, active: Bool = false, percent: Double = 0,
                 resets: Double? = nil, expires: Double? = nil) -> Account {
        Account(email: "\(name)@example.com", name: name, login: login, active: active,
                sessionPercent: percent, sessionResetsAt: resets, weekly: [], extraUsd: 0,
                checkedAt: now, loginExpiresAt: expires)
    }

    func snapshot(_ accounts: [Account], age: Double = 10) -> Snapshot {
        Snapshot(version: 1, writtenAt: now - age, machine: "test", threshold: 90,
                 active: accounts.first { $0.active }?.email, lastSwapAt: nil, accounts: accounts)
    }

    func testDecodesWhatClaudeSwapWrites() throws {
        let json = """
        {"version": 1, "written_at": 1795430819.35, "machine": "mac", "threshold": 90,
         "active": "a@example.com", "last_swap_at": null,
         "accounts": [
          {"email": "a@example.com", "name": "a", "login": "ok", "active": true,
           "session_percent": 19, "session_resets_at": 1795440000.5,
           "weekly": [{"label": "all", "percent": 2.4, "resets_at": 1796021999.6}],
           "extra_usd": 0.0, "checked_at": 1795430351.1, "login_expires_at": null},
          {"email": "b@example.com", "name": "b", "login": "logged_out", "active": false,
           "session_percent": 0, "session_resets_at": null, "weekly": [],
           "extra_usd": 1.5, "checked_at": null, "login_expires_at": 1795000000},
          {"email": "c@example.com", "name": "c", "login": "something_new", "active": false,
           "session_percent": 0, "session_resets_at": null, "weekly": []}
         ]}
        """
        let s = try Snapshot.decode(Data(json.utf8))
        XCTAssertEqual(s.accounts.map(\.login), [.ok, .loggedOut, .loggedOut])
        XCTAssertEqual(s.accounts[0].weekly.first?.percent, 2.4)
        XCTAssertNil(s.accounts[2].extraUsd)
        XCTAssertEqual(Presentation.extraUSD(s), 1.5)
    }

    func testUntilAndAgo() {
        XCTAssertEqual(Presentation.until(now + 45 * 60, now: now), "45m")
        XCTAssertEqual(Presentation.until(now + 62 * 60, now: now), "1h02m")
        XCTAssertEqual(Presentation.until(now + 3 * 86400, now: now), "3d")
        XCTAssertEqual(Presentation.until(now - 60, now: now), "0m")
        XCTAssertEqual(Presentation.ago(now - 20, now: now), "just now")
        XCTAssertEqual(Presentation.ago(now - 3 * 3600, now: now), "3h ago")
    }

    func testAResetWindowCountsAsZero() {
        XCTAssertEqual(Presentation.sessionPercent(account("a", percent: 80, resets: now - 1), now: now), 0)
        XCTAssertEqual(Presentation.sessionPercent(account("a", percent: 80, resets: now + 60), now: now), 80)
    }

    func testNotes() {
        XCTAssertEqual(Presentation.note(account("a", login: .loggedOut), now: now).tone, .bad)
        XCTAssertEqual(Presentation.note(account("a", login: .missing), now: now).tone, .dim)
        XCTAssertEqual(Presentation.note(account("a"), now: now).text, "Fresh · starts when used")
        XCTAssertTrue(Presentation.note(account("a", resets: now + 3720), now: now).text.hasSuffix("in 1h02m"))
        // An expiring login matters more than the renewal time.
        let expiring = Presentation.note(account("a", resets: now + 3720, expires: now + 86400), now: now)
        XCTAssertEqual(expiring.text, "Login expires in 24h00m")
        XCTAssertEqual(expiring.tone, .warn)
        XCTAssertEqual(Presentation.note(account("a", expires: now + 10 * 86400), now: now).tone, .normal)
    }

    func testTotalsLeaveOutLoggedOutAccounts() {
        let s = snapshot([account("a", active: true, percent: 30, resets: now + 60),
                          account("b", login: .loggedOut, percent: 50, resets: now + 60),
                          account("c")])
        XCTAssertEqual(Presentation.totalLeft(s, now: now), 170)
        XCTAssertEqual(Presentation.summary(s, now: now), "170% left across 2 accounts · 1 logged out")
    }

    func testMenuBar() {
        let a = account("a", active: true, percent: 30, resets: now + 60)
        XCTAssertEqual(Presentation.menuBar(snapshot([a, account("b")]), now: now).title, "a 30%")
        XCTAssertFalse(Presentation.menuBar(snapshot([a, account("b")]), now: now).attention)
        XCTAssertTrue(Presentation.menuBar(snapshot([a, account("b", login: .loggedOut)]), now: now).attention)
        XCTAssertEqual(Presentation.menuBar(snapshot([a], age: 600), now: now).title, "a ?")
        XCTAssertTrue(Presentation.menuBar(nil, now: now).attention)
    }

    func testShell() {
        XCTAssertEqual(Shell.quote("it's"), "'it'\\''s'")
        let r = Shell.run("echo one; echo two; exit 3")
        XCTAssertEqual(r.status, 3)
        XCTAssertEqual(r.lastLine, "two")
        // A background child holding stdout must not hang the call.
        let start = Date()
        XCTAssertTrue(Shell.run("(sleep 20 &) ; echo started").ok)
        XCTAssertLessThan(Date().timeIntervalSince(start), 10)
    }
}
