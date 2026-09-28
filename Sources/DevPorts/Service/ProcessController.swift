import Foundation

enum ProcessController {
    enum StopOutcome {
        case stopped
        case permissionDenied
        case alreadyGone
        case survived([Int32])

        var errorMessage: String? {
            switch self {
            case .stopped, .alreadyGone: return nil
            case .permissionDenied: return "Process is owned by another user — DevPorts can't stop it."
            case .survived(let pids):
                return "Still running after SIGKILL: \(pids.map(String.init).joined(separator: ", "))"
            }
        }
    }

    static func isAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    /// SIGTERM everything (children first, so a supervisor cannot respawn a child it
    /// still owns), wait out a grace period, then SIGKILL whatever is left.
    static func stop(pids: [Int32], grace: TimeInterval = 3) async -> StopOutcome {
        guard !pids.isEmpty else { return .alreadyGone }

        var deniedAll = true
        var anySignalled = false
        for pid in pids.reversed() {
            if kill(pid, SIGTERM) == 0 {
                anySignalled = true
                deniedAll = false
            } else if errno != EPERM {
                deniedAll = false
            }
        }
        if deniedAll { return .permissionDenied }
        if !anySignalled { return .alreadyGone }

        let deadline = Date().addingTimeInterval(grace)
        while Date() < deadline {
            if pids.allSatisfy({ !isAlive($0) }) { return .stopped }
            try? await Task.sleep(for: .milliseconds(150))
        }

        for pid in pids.reversed() where isAlive(pid) {
            _ = kill(pid, SIGKILL)
        }
        try? await Task.sleep(for: .milliseconds(400))

        let survivors = pids.filter { isAlive($0) }
        return survivors.isEmpty ? .stopped : .survived(survivors)
    }

    static func start(_ favorite: Favorite) throws {
        try ShellRunner.launchDetached(
            command: favorite.command,
            directory: favorite.directory,
            logPath: Paths.logFile(for: favorite.id).path,
            port: favorite.port
        )
    }

    /// Polls until the server is actually listening, and reports *where*. A command that
    /// hard-codes its port ignores the `PORT` we exported, so a listener that appears in
    /// the same working directory counts as success on a different port rather than as a
    /// failed start. Returns the observed port, or nil on timeout.
    static func waitForServer(expecting port: Int, directory: String, timeout: TimeInterval = 25) async -> Int? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try? await Task.sleep(for: .milliseconds(700))
            let listeners = await Task.detached(priority: .userInitiated) {
                PortScanner.scan().listeners
            }.value
            if listeners.contains(where: { $0.port == port }) { return port }
            if !directory.isEmpty,
               // Compose services share a directory, so a sibling container is not this server.
               let elsewhere = listeners.first(where: { $0.directory == directory && $0.container == nil }) {
                return elsewhere.port
            }
        }
        return nil
    }

    static func waitForPortToClear(_ port: Int, timeout: TimeInterval = 8) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let listening = await Task.detached(priority: .userInitiated) {
                PortScanner.scan().listeners.contains { $0.port == port }
            }.value
            if !listening { return }
            try? await Task.sleep(for: .milliseconds(400))
        }
    }
}
