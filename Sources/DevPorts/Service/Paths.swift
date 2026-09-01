import Foundation

enum Paths {
    static let supportDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let directory = base.appendingPathComponent("DevPorts", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }()

    static let storeFile = supportDirectory.appendingPathComponent("store.json")

    static let logsDirectory: URL = {
        let directory = supportDirectory.appendingPathComponent("logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }()

    static func logFile(for favoriteID: UUID) -> URL {
        logsDirectory.appendingPathComponent("\(favoriteID.uuidString).log")
    }

    /// `/Users/me/Dev/App` -> `~/Dev/App`
    static func abbreviate(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
