import Foundation

/// Runs the user's own helper commands (claude-swap, the login helpers, ssh).
public enum Shell {
    public struct Result {
        public var status: Int32
        public var output: String
        public var ok: Bool { status == 0 }
        /// The last non-empty line: what a failing command usually says went wrong.
        public var lastLine: String {
            output.split(whereSeparator: \.isNewline).last.map(String.init) ?? ""
        }
    }

    /// Runs `command` through a login shell (so PATH has `claude`, `ssh` config
    /// etc.) and returns once it exits or `timeout` passes.
    ///
    /// Output goes to a file, not a pipe: the login helpers leave background
    /// processes holding stdout open, and a pipe would never reach end-of-file.
    public static func run(_ command: String, timeout: TimeInterval = 60) -> Result {
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-swap-\(UUID().uuidString).out")
        FileManager.default.createFile(atPath: out.path, contents: nil, attributes: [.posixPermissions: 0o600])
        defer { try? FileManager.default.removeItem(at: out) }
        guard let handle = try? FileHandle(forWritingTo: out) else { return Result(status: -1, output: "no temp file") }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = handle
        process.standardError = handle
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        do { try process.run() } catch { return Result(status: -1, output: error.localizedDescription) }
        if done.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            return Result(status: -1, output: "timed out after \(Int(timeout))s")
        }
        try? handle.close()
        let text = (try? String(contentsOf: out, encoding: .utf8)) ?? ""
        return Result(status: process.terminationStatus, output: text.replacingOccurrences(of: "\r", with: ""))
    }

    /// Single-quotes `s` for a POSIX shell.
    public static func quote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
