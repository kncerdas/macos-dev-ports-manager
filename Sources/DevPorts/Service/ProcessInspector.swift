import Foundation

enum ProcessInspector {
    private static let psPath = "/bin/ps"
    private static let lsofPath = "/usr/sbin/lsof"

    // MARK: - Process table

    /// Two `ps` calls instead of one: each asks for a single space-containing field
    /// (`comm`, then `command`) in the trailing position, which keeps parsing
    /// unambiguous for executables living under paths with spaces.
    static func processTable() -> ProcessTable {
        let header = ShellRunner.run(psPath, ["-axo", "pid=,ppid=,pgid=,user=,comm="])
        let full = ShellRunner.run(psPath, ["-axo", "pid=,command="])

        var commands: [Int32: String] = [:]
        for line in full.stdout.split(separator: "\n") {
            let fields = splitFields(String(line), leading: 1)
            guard fields.count == 2, let pid = Int32(fields[0]) else { continue }
            commands[pid] = fields[1]
        }

        var nodes: [ProcessNode] = []
        for line in header.stdout.split(separator: "\n") {
            let fields = splitFields(String(line), leading: 4)
            guard fields.count == 5,
                  let pid = Int32(fields[0]),
                  let ppid = Int32(fields[1]),
                  let pgid = Int32(fields[2]) else { continue }
            nodes.append(ProcessNode(
                pid: pid,
                ppid: ppid,
                pgid: pgid,
                user: fields[3],
                executablePath: fields[4],
                command: commands[pid] ?? fields[4]
            ))
        }
        return ProcessTable(nodes: nodes)
    }

    /// Splits `leading` whitespace-delimited fields off the front and returns the
    /// untouched remainder as the final element.
    private static func splitFields(_ line: String, leading: Int) -> [String] {
        var result: [String] = []
        var rest = Substring(line).drop { $0 == " " }
        for _ in 0..<leading {
            guard let space = rest.firstIndex(of: " ") else { return result }
            result.append(String(rest[rest.startIndex..<space]))
            rest = rest[space...].drop { $0 == " " }
        }
        result.append(String(rest))
        return result
    }

    // MARK: - Working directories

    /// One batched `lsof` for every pid we care about — `-p` accepts a comma list, so
    /// this stays a single process spawn no matter how many servers are running.
    static func workingDirectories(for pids: [Int32]) -> [Int32: String] {
        guard !pids.isEmpty else { return [:] }
        let list = pids.map(String.init).joined(separator: ",")
        let result = ShellRunner.run(lsofPath, ["-a", "-p", list, "-d", "cwd", "-Fn"])

        var directories: [Int32: String] = [:]
        var currentPID: Int32?
        for line in result.stdout.split(separator: "\n") {
            guard let marker = line.first else { continue }
            let value = String(line.dropFirst())
            switch marker {
            case "p": currentPID = Int32(value)
            case "n": if let pid = currentPID, directories[pid] == nil { directories[pid] = value }
            default: break
            }
        }
        return directories
    }

    // MARK: - Classification

    private static let systemPrefixes = [
        "/System/", "/usr/libexec/", "/usr/sbin/", "/usr/bin/", "/sbin/",
        "/Library/Apple/", "/Library/PrivilegedHelperTools/", "/usr/local/libexec/"
    ]

    static func isSystemProcess(_ node: ProcessNode?, user: String) -> Bool {
        if user != NSUserName() { return true }
        guard let node else { return false }
        return systemPrefixes.contains { node.executablePath.hasPrefix($0) }
    }

    // MARK: - Command resolution

    /// Runtimes whose argv is worth climbing past — a Node child may report
    /// `next-server (v16.2.6)` while its parent still carries `next dev --turbopack`.
    private static let runtimeNames: Set<String> = [
        "node", "node.exe", "npm", "pnpm", "yarn", "bun", "deno", "npx",
        "python", "python2", "python3", "ruby", "rails", "puma", "php", "java",
        "cargo", "go", "dotnet", "dart", "flutter", "elixir", "beam.smp", "erl",
        "gunicorn", "uvicorn", "flask", "django-admin", "rustc", "air", "nodemon", "tsx", "ts-node"
    ]

    /// Anything that means "a human typed the next command here" — climbing past these
    /// would attribute the server to a terminal or editor.
    private static let boundaryNames: Set<String> = [
        "zsh", "bash", "sh", "fish", "dash", "csh", "tcsh", "login", "tmux", "screen",
        "Terminal", "iTerm2", "WezTerm", "kitty", "alacritty", "Warp", "Hyper",
        "Code", "Code Helper", "Electron", "cursor", "windsurf", "sshd", "launchd",
        "claude", "docker", "com.docker.backend"
    ]

    struct Resolution {
        var sourcePID: Int32
        var command: String
        var verified: Bool
    }

    /// Climbs from the listening pid to the topmost runtime ancestor and takes its argv.
    static func resolveCommand(for pid: Int32, in table: ProcessTable) -> Resolution {
        guard let start = table[pid] else {
            return Resolution(sourcePID: pid, command: "", verified: false)
        }

        var chosen = start
        var current = start
        var hops = 0
        while hops < 8, let parent = table.parent(of: current.pid) {
            hops += 1
            let name = parent.executableName
            if boundaryNames.contains(name) { break }
            guard runtimeNames.contains(name) else { break }
            chosen = parent
            current = parent
        }

        let command = chosen.command.trimmingCharacters(in: .whitespaces)
        return Resolution(sourcePID: chosen.pid, command: command, verified: isReplayable(command))
    }

    /// `ps` reports argv unquoted, so an absolute path containing a space
    /// (`node /Users/me/AI Coach/node_modules/.bin/next dev`) would re-split into two
    /// arguments if replayed. Because the command is always launched after `cd <dir>`,
    /// rewriting those paths relative to the working directory removes the space
    /// entirely instead of guessing where quotes belong.
    static func normalize(command: String, relativeTo directory: String?) -> String {
        guard let directory, directory != "/", !directory.isEmpty else { return command }
        return command.replacingOccurrences(of: directory + "/", with: "")
    }

    /// A command is replayable only if it still looks like a real, re-runnable argv.
    /// Node-style rewritten titles (`next-server (v16.2.6)`) carry no path or arguments,
    /// and an absolute-looking token that does not exist on disk is the fingerprint of a
    /// path that already lost a space.
    static func isReplayable(_ command: String) -> Bool {
        guard !command.isEmpty else { return false }
        if command.contains("(") && command.contains(")") { return false }
        guard command.contains("/") else { return false }

        for token in command.split(separator: " ") where token.hasPrefix("/") {
            if !FileManager.default.fileExists(atPath: String(token)) { return false }
        }
        return true
    }

    // MARK: - Command suggestion

    /// Reads `package.json` so favoriting a Node project offers `pnpm run dev` rather
    /// than a raw absolute path to a bin shim.
    static func suggestedCommand(in directory: String?) -> String? {
        guard let directory else { return nil }
        let packageURL = URL(fileURLWithPath: directory).appendingPathComponent("package.json")
        guard let data = try? Data(contentsOf: packageURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let scripts = json["scripts"] as? [String: Any] else { return nil }

        let preferred = ["dev", "start", "serve", "develop"]
        guard let script = preferred.first(where: { scripts[$0] != nil }) else { return nil }
        return "\(packageManager(in: directory)) run \(script)"
    }

    private static func packageManager(in directory: String) -> String {
        let base = URL(fileURLWithPath: directory)
        let lockfiles = [
            ("pnpm-lock.yaml", "pnpm"),
            ("yarn.lock", "yarn"),
            ("bun.lockb", "bun"),
            ("bun.lock", "bun")
        ]
        for (file, manager) in lockfiles
        where FileManager.default.fileExists(atPath: base.appendingPathComponent(file).path) {
            return manager
        }
        return "npm"
    }
}
