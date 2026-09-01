import Foundation

enum PortScanner {
    private static let lsofPath = "/usr/sbin/lsof"

    struct Snapshot {
        var listeners: [Listener] = []
        var table: ProcessTable = .empty
        var failure: String?
    }

    /// Blocking; callers run it off the main actor.
    static func scan() -> Snapshot {
        let result = ShellRunner.run(lsofPath, ["-nP", "-iTCP", "-sTCP:LISTEN", "-F", "pcLn"])

        // lsof exits 1 when it merely skipped something it could not stat, so trust the
        // parsed output and only report a failure when nothing came back at all.
        var snapshot = Snapshot()
        let sockets = parse(result.stdout)
        if sockets.isEmpty {
            if !result.succeeded {
                let message = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                snapshot.failure = message.isEmpty ? "lsof failed (status \(result.status))" : message
            }
            return snapshot
        }

        let table = ProcessInspector.processTable()
        snapshot.table = table

        // Resolve every listener's command source first, then fetch all working
        // directories in one batched lsof call.
        var resolutions: [Int32: ProcessInspector.Resolution] = [:]
        for pid in Set(sockets.map(\.pid)) {
            resolutions[pid] = ProcessInspector.resolveCommand(for: pid, in: table)
        }
        let directories = ProcessInspector.workingDirectories(for: Array(Set(resolutions.values.map(\.sourcePID))))

        snapshot.listeners = sockets.map { socket in
            var listener = socket
            let node = table[socket.pid]
            listener.executablePath = node?.executablePath ?? ""
            listener.rawCommand = node?.command ?? socket.processName
            listener.isSystem = ProcessInspector.isSystemProcess(node, user: socket.user)

            if let resolution = resolutions[socket.pid] {
                let directory = directories[resolution.sourcePID]
                let command = ProcessInspector.normalize(command: resolution.command, relativeTo: directory)
                listener.commandSourcePID = resolution.sourcePID
                listener.directory = directory
                listener.resolvedCommand = command.isEmpty ? nil : command
                listener.commandVerified = ProcessInspector.isReplayable(command)
            }
            return listener
        }
        .sorted { ($0.port, $0.pid) < ($1.port, $1.pid) }

        return snapshot
    }

    // MARK: - Parsing

    /// Parses `lsof -F` field output. Process fields (`p`, `c`, `L`) apply to every file
    /// set that follows until the next `p` line; `f` opens a file set and `n` carries
    /// `address:port`. IPv4/IPv6 duplicates of the same (pid, port) collapse into one row.
    static func parse(_ output: String) -> [Listener] {
        var byKey: [String: Listener] = [:]
        var order: [String] = []

        var pid: Int32?
        var processName = ""
        var user = ""

        for line in output.split(separator: "\n") {
            guard let marker = line.first else { continue }
            let value = String(line.dropFirst())
            switch marker {
            case "p":
                pid = Int32(value)
                processName = ""
                user = ""
            case "c": processName = value
            case "L": user = value
            case "n":
                guard let pid, let socket = parseAddress(value) else { continue }
                let key = "\(pid)-\(socket.port)"
                if var existing = byKey[key] {
                    if !existing.bindAddresses.contains(socket.address) {
                        existing.bindAddresses.append(socket.address)
                        byKey[key] = existing
                    }
                } else {
                    byKey[key] = Listener(
                        pid: pid,
                        processName: processName,
                        port: socket.port,
                        bindAddresses: [socket.address],
                        user: user,
                        commandSourcePID: pid
                    )
                    order.append(key)
                }
            default: break
            }
        }
        return order.compactMap { byKey[$0] }
    }

    /// Handles `*:3000`, `127.0.0.1:8080` and `[::1]:5173`.
    private static func parseAddress(_ value: String) -> (address: String, port: Int)? {
        guard let separator = value.lastIndex(of: ":") else { return nil }
        let portText = value[value.index(after: separator)...]
        guard let port = Int(portText) else { return nil }
        var address = String(value[value.startIndex..<separator])
        if address.hasPrefix("["), address.hasSuffix("]") {
            address = String(address.dropFirst().dropLast())
        }
        return (address.isEmpty ? "*" : address, port)
    }
}
