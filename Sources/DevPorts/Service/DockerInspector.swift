import Foundation

/// A running container that publishes a host port.
struct DockerContainer: Hashable {
    let id: String
    let name: String
    let image: String
    /// Compose labels; nil for a plain `docker run` container.
    let project: String?
    let service: String?
    let workingDirectory: String?

    /// What a developer calls it: the compose service, else the container name.
    var displayName: String { service ?? name }

    /// `pgvector/pgvector:pg17` -> `pgvector:pg17`. The registry and namespace are the
    /// same noise on every row; the repository and tag are what tell containers apart.
    var shortImage: String {
        let withoutDigest = image.split(separator: "@").first.map(String.init) ?? image
        return (withoutDigest as NSString).lastPathComponent
    }
}

/// Docker publishes container ports through a host-side forwarder (`com.docker.backend`,
/// OrbStack's helper, Lima's host agent), so `lsof` only ever sees that one process on
/// every port. The container behind each port has to come from the Docker CLI instead.
enum DockerInspector {
    private static let forwarderNames: Set<String> = [
        "com.docker.backend", "com.docker.vpnkit", "vpnkit-bridge", "vpnkit",
        "OrbStack Helper", "limactl"
    ]

    static func isForwarder(_ node: ProcessNode?) -> Bool {
        guard let node else { return false }
        return forwarderNames.contains(node.executableName)
            || forwarderNames.contains((node.executablePath as NSString).lastPathComponent)
    }

    /// A menu bar app launched from Finder inherits no shell PATH, so look where the
    /// common Docker distributions install their CLI.
    static let cliPath: String? = {
        let home = NSHomeDirectory()
        let candidates = [
            "/usr/local/bin/docker",
            "/opt/homebrew/bin/docker",
            "/Applications/Docker.app/Contents/Resources/bin/docker",
            home + "/.docker/bin/docker",
            home + "/.orbstack/bin/docker",
            home + "/.rd/bin/docker"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }()

    private static let fields = [
        "{{.ID}}", "{{.Names}}", "{{.Image}}", "{{.Ports}}",
        #"{{.Label "com.docker.compose.project"}}"#,
        #"{{.Label "com.docker.compose.service"}}"#,
        #"{{.Label "com.docker.compose.project.working_dir"}}"#
    ]

    /// Host port -> container, for every running container. Blocking.
    static func containersByHostPort() -> [Int: DockerContainer] {
        guard let cliPath else { return [:] }
        let result = ShellRunner.run(cliPath, ["ps", "--format", fields.joined(separator: "\t")], timeout: 5)
        guard result.succeeded else { return [:] }

        var byPort: [Int: DockerContainer] = [:]
        for line in result.stdout.split(separator: "\n") {
            let columns = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard columns.count == fields.count else { continue }
            let container = DockerContainer(
                id: columns[0],
                name: columns[1],
                image: columns[2],
                project: columns[4].nilIfEmpty,
                service: columns[5].nilIfEmpty,
                workingDirectory: columns[6].nilIfEmpty
            )
            for port in hostPorts(in: columns[3]) where byPort[port] == nil {
                byPort[port] = container
            }
        }
        return byPort
    }

    /// Parses `0.0.0.0:5432->5432/tcp, [::]:5432->5432/tcp` and ranges such as
    /// `0.0.0.0:8000-8001->8000-8001/tcp`. Unpublished ports (`6379/tcp`) have no
    /// host side and are skipped.
    static func hostPorts(in ports: String) -> [Int] {
        var result: [Int] = []
        for mapping in ports.components(separatedBy: ", ") {
            guard mapping.hasSuffix("/tcp"),
                  let arrow = mapping.range(of: "->") else { continue }
            let host = mapping[mapping.startIndex..<arrow.lowerBound]
            guard let colon = host.lastIndex(of: ":") else { continue }
            let range = host[host.index(after: colon)...].split(separator: "-").compactMap { Int($0) }
            guard let low = range.first else { continue }
            let high = range.count > 1 ? range[1] : low
            guard high >= low, high - low < 1024 else { continue }
            result.append(contentsOf: low...high)
        }
        return result
    }

    // MARK: - Control

    static func stop(_ container: DockerContainer) -> CommandResult {
        run(["stop", container.id])
    }

    static func restart(_ container: DockerContainer) -> CommandResult {
        run(["restart", container.id])
    }

    private static func run(_ arguments: [String]) -> CommandResult {
        guard let cliPath else {
            return CommandResult(status: -1, stdout: "", stderr: "Docker CLI not found.")
        }
        return ShellRunner.run(cliPath, arguments, timeout: 60)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
