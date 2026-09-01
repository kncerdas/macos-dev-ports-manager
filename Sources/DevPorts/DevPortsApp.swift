import AppKit
import SwiftUI

@main
struct DevPortsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = PortsViewModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(model)
        } label: {
            Image(systemName: Symbols.menuBar)
        }
        .menuBarExtraStyle(.window)

        Window("DevPorts", id: EditorWindow.id) {
            EditorWindowView()
                .environmentObject(model)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Headless dump of what the scanner sees, for verifying resolution against `lsof`
        // without opening the panel: `swift run DevPorts --scan`.
        guard CommandLine.arguments.contains("--scan") else { return }
        let snapshot = PortScanner.scan()
        if let failure = snapshot.failure { FileHandle.standardError.write(Data("scan failed: \(failure)\n".utf8)) }
        for listener in snapshot.listeners {
            print("""
            \(listener.isSystem ? "sys " : "dev ")\(listener.port)\t\(listener.processName)\tpid=\(listener.pid) src=\(listener.commandSourcePID) stopRoot=\(listener.stopRootPID) bind=\(listener.bindAddresses.joined(separator: ","))
            \tdir: \(listener.directory ?? "-")
            \tcmd: \(listener.resolvedCommand ?? "-")  [verified: \(listener.commandVerified)]
            """)
        }
        exit(0)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Redundant with LSUIElement in the bundle, but keeps `swift run` out of the Dock too.
        NSApp.setActivationPolicy(.accessory)
    }
}
