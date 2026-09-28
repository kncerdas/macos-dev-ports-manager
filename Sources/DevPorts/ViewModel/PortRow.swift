import Foundation

/// One line in the panel. A row is either a live listener, a saved-but-stopped
/// favorite, or both merged together.
struct PortRow: Identifiable, Hashable {
    let id: String
    let port: Int
    let displayName: String
    let subtitle: String
    let processLabel: String
    let bindSummary: String
    let scheme: String

    let isRunning: Bool
    let isSystem: Bool
    let isFavorite: Bool
    let commandVerified: Bool

    let pid: Int32?
    let stopRootPID: Int32?
    let directory: String?
    let command: String?
    let favoriteID: UUID?
    let hasAlias: Bool
    /// Set only when a favorite is running on a port other than the one it was saved
    /// with — i.e. the command ignored `$PORT`.
    var savedPort: Int?
    /// Set when the port is published by a Docker container; stop and restart go through
    /// the Docker CLI, because `pid` is Docker's shared forwarder.
    var container: DockerContainer?

    var canOpenInBrowser: Bool { isRunning }
    var url: URL? { URL(string: "\(scheme)://localhost:\(port)") }
}

struct Banner: Identifiable, Equatable {
    enum Kind { case info, error }
    let id = UUID()
    let text: String
    let kind: Kind
}

/// Backing state for the editor window (rename / command / directory / scheme).
struct EditorDraft: Identifiable, Equatable {
    enum Mode: Equatable { case createFavorite, editFavorite, renameOnly }

    var id: String { rowKey }
    var rowKey: String
    var mode: Mode
    var favoriteID: UUID?
    var name: String
    var command: String
    var directory: String
    var port: Int
    var scheme: String
    var commandWarning: String?

    var title: String {
        switch mode {
        case .createFavorite: return "Save to Favorites"
        case .editFavorite: return "Edit Favorite"
        case .renameOnly: return "Rename"
        }
    }
}

/// What a Stop click is about to kill, shown inline before anything is signalled.
struct StopPrompt: Identifiable, Equatable {
    struct Entry: Identifiable, Equatable {
        let pid: Int32
        let label: String
        let depth: Int
        var id: Int32 { pid }
    }

    var id: String { rowKey }
    var rowKey: String
    var port: Int
    var listeningPID: Int32
    var tree: [Entry]
    var container: DockerContainer?
}
