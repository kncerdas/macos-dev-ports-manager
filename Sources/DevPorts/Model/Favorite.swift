import Foundation

enum StopMode: String, Codable, Hashable {
    /// SIGTERM only the process holding the port.
    case process
    /// SIGTERM the resolved root and every descendant.
    case tree
}

/// A saved server: enough information to start it again from nothing.
struct Favorite: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var command: String
    var directory: String
    var port: Int
    var scheme: String = "http"
    /// `nil` means ask which stop mode to use every time.
    var stopMode: StopMode?
    var lastStarted: Date?

    var key: String { EntryKey.make(directory: directory, port: port, command: command) }
}

enum URLScheme {
    static let known = ["http", "https"]

    /// Ports that are conventionally TLS, so the first click lands on the right scheme.
    static func suggested(for port: Int) -> String {
        [443, 3443, 4443, 8443, 9443].contains(port) ? "https" : "http"
    }
}
