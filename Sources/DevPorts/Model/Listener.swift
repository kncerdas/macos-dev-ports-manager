import Foundation

/// A process holding a listening TCP port.
struct Listener: Identifiable, Hashable {
    let pid: Int32
    /// Short process name from `lsof` (e.g. `node`).
    let processName: String
    let port: Int
    /// Every address this pid binds on this port (`*`, `127.0.0.1`, `[::1]`).
    var bindAddresses: [String]
    let user: String

    var executablePath: String = ""
    /// Raw `ps -o command=` of the listening pid.
    var rawCommand: String = ""
    /// Working directory of `commandSourcePID`.
    var directory: String?
    /// Best-guess command that would bring this server back up.
    var resolvedCommand: String?
    /// False when the resolved command looks mangled or unsafe to replay verbatim.
    var commandVerified: Bool = false
    /// Ancestor the command and directory were taken from.
    var commandSourcePID: Int32
    /// Topmost process that should die with this server. Climbs past the command source
    /// through supervisors and shell wrappers, so it is never below it.
    var stopRootPID: Int32 = 0
    var isSystem: Bool = false
    /// Set when `pid` is only Docker's port forwarder and this container is the real server.
    var container: DockerContainer?

    var id: String { "\(pid)-\(port)" }

    var key: String {
        EntryKey.make(directory: directory, port: port, command: resolvedCommand ?? rawCommand)
    }

    var bindSummary: String {
        if bindAddresses.contains("*") || bindAddresses.contains("0.0.0.0") { return "all" }
        if bindAddresses.contains(where: { $0.hasPrefix("127.") || $0.contains("::1") }) { return "local" }
        return bindAddresses.first ?? ""
    }
}

/// Stable identity for an entry across restarts, so renames and favorites survive
/// PID churn. Directory + port is the strongest signal; command + port is the fallback.
enum EntryKey {
    static func make(directory: String?, port: Int, command: String?) -> String {
        if let directory, !directory.isEmpty { return "d:\(directory)|\(port)" }
        if let command, !command.isEmpty { return "c:\(command)|\(port)" }
        return "p:\(port)"
    }
}
