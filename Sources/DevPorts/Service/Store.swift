import Foundation

struct Settings: Codable, Hashable {
    var showSystem = false
    var refreshSeconds = 5
}

struct StoreData: Codable {
    var version = 1
    var favorites: [Favorite] = []
    /// Entry key -> user-supplied display name, kept separate from favorites so a
    /// process can be renamed without being saved for later.
    var aliases: [String: String] = [:]
    var settings = Settings()
}

/// JSON-backed persistence. Writes are debounced and atomic.
final class Store {
    private(set) var data: StoreData
    private var saveWorkItem: DispatchWorkItem?
    private let queue = DispatchQueue(label: "dev.nullkyu.devports.store")

    init() {
        if let raw = try? Data(contentsOf: Paths.storeFile),
           let decoded = try? JSONDecoder().decode(StoreData.self, from: raw) {
            data = decoded
        } else {
            data = StoreData()
        }
    }

    func mutate(_ change: (inout StoreData) -> Void) {
        change(&data)
        scheduleSave()
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let snapshot = data
        let item = DispatchWorkItem {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            guard let encoded = try? encoder.encode(snapshot) else { return }
            try? encoded.write(to: Paths.storeFile, options: .atomic)
        }
        saveWorkItem = item
        queue.asyncAfter(deadline: .now() + 0.4, execute: item)
    }

    func flush() {
        saveWorkItem?.perform()
        saveWorkItem?.cancel()
        saveWorkItem = nil
    }
}
