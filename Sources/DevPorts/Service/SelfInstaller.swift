import AppKit

/// Opening DevPorts straight from its disk image installs it, or, when a copy is already
/// in /Applications, replaces that copy in place. Updating never means quitting and
/// deleting the old app by hand first; favorites live in Application Support and survive.
enum SelfInstaller {
    static let destination = URL(fileURLWithPath: "/Applications/DevPorts.app")

    /// A mounted image, or the randomised copy Gatekeeper runs a quarantined image's app from.
    static var isRunningFromDiskImage: Bool {
        let path = Bundle.main.bundlePath
        return path.hasPrefix("/Volumes/") || path.contains("/AppTranslocation/")
    }

    @MainActor
    static func offerInstallIfNeeded() {
        guard isRunningFromDiskImage else { return }

        let isUpdate = FileManager.default.fileExists(atPath: destination.path)
        let alert = NSAlert()
        alert.messageText = isUpdate ? "Update DevPorts?" : "Install DevPorts?"
        alert.informativeText = isUpdate
            ? "Replaces DevPorts \(version(of: Bundle(url: destination))) in Applications with "
                + "\(version(of: .main)) and reopens it. Favorites and settings are kept."
            : "Copies DevPorts \(version(of: .main)) to your Applications folder and opens it from there."
        alert.addButton(withTitle: isUpdate ? "Update" : "Install")
        alert.addButton(withTitle: "Not Now")

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            quitOtherInstances()
            try install()
            relaunch()
        } catch {
            let failure = NSAlert(error: error)
            failure.messageText = "Couldn't \(isUpdate ? "update" : "install") DevPorts"
            failure.runModal()
        }
    }

    private static func version(of bundle: Bundle?) -> String {
        let info = bundle?.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    /// A running bundle can't be replaced, so the old copy is asked to quit first.
    private static func quitOtherInstances() {
        guard let identifier = Bundle.main.bundleIdentifier else { return }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .filter { $0 != .current }
        others.forEach { $0.terminate() }

        let deadline = Date().addingTimeInterval(5)
        while others.contains(where: { !$0.isTerminated }), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        others.filter { !$0.isTerminated }.forEach { $0.forceTerminate() }
    }

    /// Copies next to the destination first, then swaps it in, so a failed copy leaves
    /// the installed app untouched.
    private static func install() throws {
        let fileManager = FileManager.default
        let staging = try fileManager.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: destination,
            create: true
        )
        defer { try? fileManager.removeItem(at: staging) }

        let copy = staging.appendingPathComponent(destination.lastPathComponent)
        try fileManager.copyItem(at: Bundle.main.bundleURL, to: copy)

        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: copy)
        } else {
            try fileManager.moveItem(at: copy, to: destination)
        }
    }

    @MainActor
    private static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        // Same bundle id as this process; without this, Launch Services just reactivates us.
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: destination, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
