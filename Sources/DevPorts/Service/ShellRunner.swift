import Foundation

struct CommandResult {
    let status: Int32
    let stdout: String
    let stderr: String

    var succeeded: Bool { status == 0 }
}

enum ShellRunner {
    static let shell = "/bin/zsh"

    /// Runs a tool and waits for it. Both pipes are drained on background queues so a
    /// chatty stderr can never deadlock the read of stdout.
    @discardableResult
    static func run(_ path: String, _ arguments: [String], timeout: TimeInterval = 15) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return CommandResult(status: -1, stdout: "", stderr: error.localizedDescription)
        }

        let lock = NSLock()
        var outData = Data()
        var errData = Data()
        let group = DispatchGroup()
        for (pipe, isStdout) in [(outPipe, true), (errPipe, false)] {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                lock.lock()
                if isStdout { outData = data } else { errData = data }
                lock.unlock()
                group.leave()
            }
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            usleep(20_000)
        }
        if process.isRunning { process.terminate() }
        process.waitUntilExit()
        _ = group.wait(timeout: .now() + 2)

        lock.lock()
        defer { lock.unlock() }
        return CommandResult(
            status: process.terminationStatus,
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errData, as: UTF8.self)
        )
    }

    /// Starts a server that must outlive DevPorts itself.
    ///
    /// The command, directory and log path travel as environment variables rather than
    /// being interpolated into the script, so paths containing spaces or quotes need no
    /// escaping. `nohup ... &` + `disown` reparents the server to launchd, and the login
    /// shell (`-l`) restores the PATH that a GUI-launched app does not inherit.
    /// `port` is exported as `PORT`, the convention Next, CRA, Express, Rails and most
    /// dev servers read. A server that hard-codes its port ignores it — the caller
    /// reconciles that against what actually ends up listening.
    static func launchDetached(command: String, directory: String, logPath: String, port: Int?) throws {
        let script = """
        cd "$DP_DIR" || exit 1
        if [ -n "$DP_PORT" ]; then export PORT="$DP_PORT"; fi
        printf '\\n=== DevPorts start %s ===\\n' "$(date)" >> "$DP_LOG"
        printf '=== PORT=%s %s\\n' "$DP_PORT" "$DP_CMD" >> "$DP_LOG"
        nohup "$DP_SHELL" -lc "$DP_CMD" >> "$DP_LOG" 2>&1 &
        disown
        """

        var environment = ProcessInfo.processInfo.environment
        environment["DP_DIR"] = directory
        environment["DP_LOG"] = logPath
        environment["DP_CMD"] = command
        environment["DP_SHELL"] = shell
        environment["DP_PORT"] = port.map(String.init) ?? ""

        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-lc", script]
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
    }
}
