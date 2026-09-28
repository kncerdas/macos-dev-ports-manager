import AppKit
import Foundation
import SwiftUI

@MainActor
final class PortsViewModel: ObservableObject {
    enum Tab: String, CaseIterable, Hashable {
        case running
        case favorites

        var title: String {
            switch self {
            case .running: return "Running"
            case .favorites: return "Favorites"
            }
        }
    }

    @Published var tab: Tab = .running
    @Published private(set) var runningRows: [PortRow] = []
    /// Every favorite, running or not — a Favorites tab that hid the running ones would
    /// be a list with holes in it.
    @Published private(set) var favoriteRows: [PortRow] = []
    @Published private(set) var hiddenSystemCount = 0
    @Published private(set) var isRefreshing = false
    @Published private(set) var busyRows: Set<String> = []
    @Published private(set) var lastScanFailure: String?

    @Published var searchText = "" { didSet { rebuild() } }
    @Published var stopPrompt: StopPrompt?
    @Published var editor: EditorDraft?
    @Published var banner: Banner?

    @Published var showSystem: Bool {
        didSet {
            guard showSystem != store.data.settings.showSystem else { return }
            store.mutate { $0.settings.showSystem = showSystem }
            rebuild()
        }
    }

    private let store = Store()
    private var listeners: [Listener] = []
    private var table = ProcessTable.empty
    private var timer: Timer?
    private var bannerTask: Task<Void, Never>?

    init() {
        showSystem = store.data.settings.showSystem
    }

    var favorites: [Favorite] { store.data.favorites }

    // MARK: - Lifecycle

    func panelAppeared() {
        refresh()
        timer?.invalidate()
        let interval = TimeInterval(max(2, store.data.settings.refreshSeconds))
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh(showSpinner: false) }
        }
    }

    func panelDisappeared() {
        timer?.invalidate()
        timer = nil
        stopPrompt = nil
    }

    // MARK: - Scanning

    func refresh(showSpinner: Bool = true) {
        if showSpinner { isRefreshing = true }
        Task {
            let snapshot = await Task.detached(priority: .userInitiated) { PortScanner.scan() }.value
            self.listeners = snapshot.listeners
            self.table = snapshot.table
            self.lastScanFailure = snapshot.failure
            self.isRefreshing = false
            self.rebuild()
        }
    }

    // MARK: - Row assembly

    private func rebuild() {
        let visibleListeners = listeners.filter { showSystem || !$0.isSystem }
        hiddenSystemCount = showSystem ? 0 : listeners.count - visibleListeners.count

        var claimedFavorites: Set<UUID> = []
        var pairs: [(listener: Listener, favorite: Favorite?)] = []

        // Pass 1: match on identity and port.
        for listener in visibleListeners {
            let favorite = matchFavorite(for: listener, excluding: claimedFavorites)
            if let favorite { claimedFavorites.insert(favorite.id) }
            pairs.append((listener, favorite))
        }

        // Pass 2: a server that ignored $PORT is still its favorite's process. Claim the
        // leftovers by directory alone — but only where that directory maps to exactly one
        // unclaimed favorite, so a repo running an api and a web server can't cross-match.
        for index in pairs.indices where pairs[index].favorite == nil {
            guard let directory = pairs[index].listener.directory,
                  !directory.isEmpty, directory != "/" else { continue }
            let candidates = store.data.favorites.filter {
                $0.directory == directory && !claimedFavorites.contains($0.id)
            }
            guard candidates.count == 1 else { continue }
            claimedFavorites.insert(candidates[0].id)
            pairs[index].favorite = candidates[0]
        }

        let running = pairs.map { row(for: $0.listener, favorite: $0.favorite) }

        let stopped = store.data.favorites
            .filter { !claimedFavorites.contains($0.id) }
            .map(row(forStopped:))

        runningRows = filter(running).sorted { $0.port < $1.port }
        favoriteRows = filter(running.filter(\.isFavorite) + stopped)
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    func rows(for tab: Tab) -> [PortRow] {
        switch tab {
        case .running: return runningRows
        case .favorites: return favoriteRows
        }
    }

    private func filter(_ rows: [PortRow]) -> [PortRow] {
        let needle = searchText.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return rows }
        return rows.filter { row in
            [String(row.port), row.displayName, row.subtitle, row.processLabel, row.command ?? ""]
                .contains { $0.localizedCaseInsensitiveContains(needle) }
        }
    }

    /// Favorites bind to a listener by stable key first, then by directory+port, then by
    /// port alone — so a server keeps its identity even when its cwd can't be read.
    private func matchFavorite(for listener: Listener, excluding claimed: Set<UUID> = []) -> Favorite? {
        let favorites = store.data.favorites.filter { !claimed.contains($0.id) }
        if let exact = favorites.first(where: { $0.key == listener.key }) { return exact }
        if let directory = listener.directory,
           let byDirectory = favorites.first(where: { $0.directory == directory && $0.port == listener.port }) {
            return byDirectory
        }
        return favorites.first { $0.port == listener.port && $0.directory.isEmpty }
    }

    private func row(for listener: Listener, favorite: Favorite?) -> PortRow {
        let key = favorite?.key ?? listener.key
        let alias = store.data.aliases[key] ?? store.data.aliases[listener.key]
        let command = favorite?.command ?? listener.resolvedCommand

        return PortRow(
            id: key,
            port: listener.port,
            displayName: alias ?? favorite?.name ?? Self.inferredName(listener: listener),
            subtitle: Self.subtitle(
                directory: listener.directory,
                displayName: alias ?? favorite?.name ?? Self.inferredName(listener: listener),
                fallback: listener.container.map { $0.project ?? "docker" } ?? listener.rawCommand
            ),
            processLabel: listener.container?.shortImage ?? listener.processName,
            bindSummary: listener.bindSummary,
            scheme: favorite?.scheme ?? URLScheme.suggested(for: listener.port),
            isRunning: true,
            isSystem: listener.isSystem,
            isFavorite: favorite != nil,
            commandVerified: favorite != nil || listener.commandVerified,
            pid: listener.pid,
            stopRootPID: listener.stopRootPID == 0 ? listener.commandSourcePID : listener.stopRootPID,
            directory: favorite?.directory.isEmpty == false ? favorite?.directory : listener.directory,
            command: command,
            favoriteID: favorite?.id,
            hasAlias: alias != nil,
            savedPort: (favorite.map { $0.port != listener.port } ?? false) ? favorite?.port : nil,
            container: listener.container
        )
    }

    private func row(forStopped favorite: Favorite) -> PortRow {
        PortRow(
            id: favorite.key,
            port: favorite.port,
            displayName: store.data.aliases[favorite.key] ?? favorite.name,
            subtitle: Self.subtitle(
                directory: favorite.directory,
                displayName: store.data.aliases[favorite.key] ?? favorite.name,
                fallback: favorite.command
            ),
            processLabel: "",
            bindSummary: "",
            scheme: favorite.scheme,
            isRunning: false,
            isSystem: false,
            isFavorite: true,
            commandVerified: true,
            pid: nil,
            stopRootPID: nil,
            directory: favorite.directory,
            command: favorite.command,
            favoriteID: favorite.id,
            hasAlias: store.data.aliases[favorite.key] != nil,
            savedPort: nil
        )
    }

    /// The row title is usually the project folder's own name, so repeating it in the
    /// subtitle wastes the width that pushes the pid off the end. When the title already
    /// says the leaf, show where it lives instead of saying it twice.
    private static func subtitle(directory: String?, displayName: String, fallback: String) -> String {
        guard let directory, !directory.isEmpty, directory != "/" else { return fallback }
        let leaf = (directory as NSString).lastPathComponent
        guard leaf == displayName else { return Paths.compact(directory) }
        let parent = (directory as NSString).deletingLastPathComponent
        return parent.isEmpty ? Paths.compact(directory) : Paths.abbreviate(parent)
    }

    /// Project folder name reads better than an absolute bin path, and is what a
    /// developer actually calls the thing.
    private static func inferredName(listener: Listener) -> String {
        if let container = listener.container { return container.displayName }
        if let directory = listener.directory, !directory.isEmpty, directory != "/" {
            return (directory as NSString).lastPathComponent
        }
        return listener.processName
    }

    // MARK: - Browser

    func openInBrowser(_ row: PortRow) {
        guard let url = row.url else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Rename & favorites

    func beginRename(_ row: PortRow) {
        editor = EditorDraft(
            rowKey: row.id,
            mode: row.isFavorite ? .editFavorite : .renameOnly,
            favoriteID: row.favoriteID,
            name: row.displayName,
            command: row.command ?? "",
            directory: row.directory ?? "",
            port: row.port,
            scheme: row.scheme,
            commandWarning: commandWarning(for: row)
        )
    }

    /// Favoriting always opens the editor: the derived command is a guess, and the one
    /// moment the user is thinking about this server is the right time to confirm it.
    func toggleFavorite(_ row: PortRow) {
        if let favoriteID = row.favoriteID {
            store.mutate { $0.favorites.removeAll { $0.id == favoriteID } }
            rebuild()
            show(Banner(text: "Removed “\(row.displayName)” from favorites", kind: .info))
            return
        }

        let suggested = ProcessInspector.suggestedCommand(in: row.directory)
        editor = EditorDraft(
            rowKey: row.id,
            mode: .createFavorite,
            favoriteID: nil,
            name: row.displayName,
            command: suggested ?? row.command ?? "",
            directory: row.directory ?? "",
            port: row.port,
            scheme: row.scheme,
            commandWarning: suggested == nil ? commandWarning(for: row) : nil
        )
    }

    private func commandWarning(for row: PortRow) -> String? {
        guard !row.commandVerified else { return nil }
        return "DevPorts couldn't read a reliable start command for this process — check it before saving."
    }

    /// Describes who already holds `draft.port`, or nil when the port is free for this
    /// entry. Checked at save time rather than while typing, so a half-typed port
    /// ("30" on the way to "3000") never raises a false alarm.
    func portConflict(for draft: EditorDraft) -> String? {
        if let favorite = store.data.favorites.first(where: { $0.port == draft.port && $0.id != draft.favoriteID }) {
            return "Favorite “\(favorite.name)” is already saved on port \(draft.port)."
        }

        if let listener = listeners.first(where: { $0.port == draft.port }) {
            let isThisEntry = listener.key == draft.rowKey
                || (draft.favoriteID != nil && matchFavorite(for: listener)?.id == draft.favoriteID)
            if !isThisEntry {
                var owner = listener.processName
                if let directory = listener.directory {
                    let project = (directory as NSString).lastPathComponent
                    if !project.isEmpty, project != "/" { owner = project }
                }
                return "Port \(draft.port) is currently in use by \(owner) (\(listener.processName), pid \(listener.pid))."
            }
        }
        return nil
    }

    func saveEditor(_ draft: EditorDraft) {
        let name = draft.name.trimmingCharacters(in: .whitespaces)
        let command = draft.command.trimmingCharacters(in: .whitespaces)
        let directory = draft.directory.trimmingCharacters(in: .whitespaces)

        switch draft.mode {
        case .renameOnly:
            store.mutate { $0.aliases[draft.rowKey] = name.isEmpty ? nil : name }

        case .createFavorite:
            let favorite = Favorite(
                name: name.isEmpty ? "Port \(draft.port)" : name,
                command: command,
                directory: directory,
                port: draft.port,
                scheme: draft.scheme
            )
            store.mutate {
                $0.favorites.append(favorite)
                $0.aliases[draft.rowKey] = nil
            }

        case .editFavorite:
            store.mutate { data in
                guard let index = data.favorites.firstIndex(where: { $0.id == draft.favoriteID }) else { return }
                data.favorites[index].name = name.isEmpty ? data.favorites[index].name : name
                data.favorites[index].command = command
                data.favorites[index].directory = directory
                data.favorites[index].port = draft.port
                data.favorites[index].scheme = draft.scheme
                data.aliases[draft.rowKey] = nil
                data.aliases[data.favorites[index].key] = nil
            }
        }
        editor = nil
        rebuild()
    }

    func deleteFavorite(_ row: PortRow) {
        guard let favoriteID = row.favoriteID else { return }
        store.mutate {
            $0.favorites.removeAll { $0.id == favoriteID }
            $0.aliases[row.id] = nil
        }
        editor = nil
        rebuild()
    }

    // MARK: - Stop

    func requestStop(_ row: PortRow) {
        guard let pid = row.pid else { return }

        // The pid is Docker's forwarder for every published port; its process tree is
        // the whole Docker backend, so a container only ever offers `docker stop`.
        if let container = row.container {
            stopPrompt = StopPrompt(rowKey: row.id, port: row.port, listeningPID: pid, tree: [], container: container)
            return
        }

        if let favoriteID = row.favoriteID,
           let remembered = store.data.favorites.first(where: { $0.id == favoriteID })?.stopMode {
            perform(stop: row, mode: remembered, remember: false)
            return
        }

        let root = row.stopRootPID ?? pid
        var tree = table.tree(rootedAt: root)
        if !tree.contains(where: { $0.pid == pid }), let node = table[pid] {
            tree = [node]
        }

        stopPrompt = StopPrompt(
            rowKey: row.id,
            port: row.port,
            listeningPID: pid,
            tree: tree.map { node in
                StopPrompt.Entry(
                    pid: node.pid,
                    label: Self.shortLabel(for: node),
                    depth: table.depth(of: node.pid, below: root)
                )
            }
        )
    }

    func perform(stop row: PortRow, mode: StopMode, remember: Bool) {
        guard row.pid != nil else { return }
        stopPrompt = nil

        if remember, let favoriteID = row.favoriteID {
            store.mutate { data in
                guard let index = data.favorites.firstIndex(where: { $0.id == favoriteID }) else { return }
                data.favorites[index].stopMode = mode
            }
        }

        if let container = row.container {
            runDocker(on: row, verb: "stop") { DockerInspector.stop(container) }
            return
        }

        let pids = self.pids(for: row, mode: mode)
        busyRows.insert(row.id)
        Task {
            let outcome = await ProcessController.stop(pids: pids)
            busyRows.remove(row.id)
            if let error = outcome.errorMessage {
                show(Banner(text: error, kind: .error))
            }
            refresh(showSpinner: false)
        }
    }

    private func pids(for row: PortRow, mode: StopMode) -> [Int32] {
        guard let pid = row.pid else { return [] }
        switch mode {
        case .process:
            return [pid]
        case .tree:
            let root = row.stopRootPID ?? pid
            let tree = table.tree(rootedAt: root).map(\.pid)
            return tree.contains(pid) ? tree : [pid]
        }
    }

    // MARK: - Start & restart

    func start(_ row: PortRow) {
        guard let favorite = favorite(for: row) else {
            show(Banner(text: "Save this port as a favorite first so DevPorts knows how to start it.", kind: .error))
            return
        }
        guard !favorite.command.isEmpty, !favorite.directory.isEmpty else {
            beginRename(row)
            return
        }

        busyRows.insert(row.id)
        Task {
            do {
                try ProcessController.start(favorite)
                store.mutate { data in
                    guard let index = data.favorites.firstIndex(where: { $0.id == favorite.id }) else { return }
                    data.favorites[index].lastStarted = Date()
                }
                let observed = await ProcessController.waitForServer(
                    expecting: favorite.port,
                    directory: favorite.directory
                )
                busyRows.remove(row.id)
                report(startOf: favorite, observed: observed)
            } catch {
                busyRows.remove(row.id)
                show(Banner(text: "Couldn't start: \(error.localizedDescription)", kind: .error))
            }
            refresh(showSpinner: false)
        }
    }

    func restart(_ row: PortRow) {
        if let container = row.container {
            runDocker(on: row, verb: "restart") { DockerInspector.restart(container) }
            return
        }
        guard let favorite = favorite(for: row) else {
            show(Banner(text: "Save this port as a favorite first so DevPorts knows how to restart it.", kind: .error))
            return
        }

        let mode = favorite.stopMode ?? .tree
        let pids = self.pids(for: row, mode: mode)
        busyRows.insert(row.id)
        Task {
            let outcome = await ProcessController.stop(pids: pids)
            if let error = outcome.errorMessage {
                busyRows.remove(row.id)
                show(Banner(text: error, kind: .error))
                refresh(showSpinner: false)
                return
            }
            await ProcessController.waitForPortToClear(favorite.port)
            do {
                try ProcessController.start(favorite)
                let observed = await ProcessController.waitForServer(
                    expecting: favorite.port,
                    directory: favorite.directory
                )
                busyRows.remove(row.id)
                report(startOf: favorite, observed: observed)
            } catch {
                busyRows.remove(row.id)
                show(Banner(text: "Couldn't restart: \(error.localizedDescription)", kind: .error))
            }
            refresh(showSpinner: false)
        }
    }

    private func runDocker(on row: PortRow, verb: String, _ action: @escaping @Sendable () -> CommandResult) {
        busyRows.insert(row.id)
        Task {
            let result = await Task.detached(priority: .userInitiated) { action() }.value
            busyRows.remove(row.id)
            if !result.succeeded {
                let message = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                show(Banner(text: "Couldn't \(verb) “\(row.displayName)”: \(message)", kind: .error))
            }
            refresh(showSpinner: false)
        }
    }

    /// DevPorts exports `PORT`, but a command with a hard-coded port wins. Say so
    /// plainly instead of reporting a healthy server as a failed start.
    private func report(startOf favorite: Favorite, observed: Int?) {
        guard let observed else {
            show(Banner(text: "“\(favorite.name)” didn't start listening. Check its log.", kind: .error))
            return
        }
        guard observed != favorite.port else { return }
        show(Banner(
            text: "“\(favorite.name)” ignored $PORT and started on \(observed) instead of \(favorite.port). "
                + "Use the row's ⋯ menu to save \(observed), or set the port in the command itself.",
            kind: .info
        ))
    }

    /// Adopts the port a server actually bound, for commands that will never honour $PORT.
    func adoptObservedPort(_ row: PortRow) {
        guard let favoriteID = row.favoriteID else { return }
        store.mutate { data in
            guard let index = data.favorites.firstIndex(where: { $0.id == favoriteID }) else { return }
            data.favorites[index].port = row.port
        }
        rebuild()
    }

    private func favorite(for row: PortRow) -> Favorite? {
        guard let favoriteID = row.favoriteID else { return nil }
        return store.data.favorites.first { $0.id == favoriteID }
    }

    // MARK: - Row extras

    func copyContainerName(_ row: PortRow) {
        guard let container = row.container else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(container.name, forType: .string)
        show(Banner(text: "Copied \(container.name)", kind: .info))
    }

    func copyPID(_ row: PortRow) {
        guard let pid = row.pid else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(String(pid), forType: .string)
        show(Banner(text: "Copied PID \(pid)", kind: .info))
    }

    func revealInFinder(_ row: PortRow) {
        guard let directory = row.directory, !directory.isEmpty else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: directory)
    }

    func hasLog(_ row: PortRow) -> Bool {
        guard let favoriteID = row.favoriteID else { return false }
        return FileManager.default.fileExists(atPath: Paths.logFile(for: favoriteID).path)
    }

    func openLog(_ row: PortRow) {
        guard let favoriteID = row.favoriteID else { return }
        let url = Paths.logFile(for: favoriteID)
        if !FileManager.default.fileExists(atPath: url.path) {
            show(Banner(text: "No log yet — start this server from DevPorts to capture one.", kind: .info))
            return
        }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Banner

    private func show(_ banner: Banner) {
        self.banner = banner
        bannerTask?.cancel()
        bannerTask = Task {
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            if self.banner?.id == banner.id { self.banner = nil }
        }
    }

    func dismissBanner() {
        bannerTask?.cancel()
        banner = nil
    }

    private static func shortLabel(for node: ProcessNode) -> String {
        let command = node.command.isEmpty ? node.executablePath : node.command
        return command.count > 78 ? String(command.prefix(78)) + "…" : command
    }
}
