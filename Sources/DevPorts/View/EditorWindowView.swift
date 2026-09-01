import AppKit
import SwiftUI

enum EditorWindow {
    static let id = "dev.nullkyu.devports.editor"
}

/// Editing happens in a real window, not a sheet: a sheet attached to the menu bar
/// panel would dismiss the panel the moment focus moved.
struct EditorWindowView: View {
    @EnvironmentObject private var model: PortsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var draft: EditorDraft?
    @State private var conflictMessage: String?
    @State private var pendingDraft: EditorDraft?

    var body: some View {
        Group {
            if let draft {
                form(for: draft)
            } else {
                Text("Nothing to edit")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 460)
        .onAppear { draft = model.editor }
        .onChange(of: model.editor) { _, newValue in
            if let newValue { draft = newValue }
        }
        .alert(
            "Port already in use",
            isPresented: Binding(
                get: { conflictMessage != nil },
                set: { if !$0 { conflictMessage = nil; pendingDraft = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) {
                conflictMessage = nil
                pendingDraft = nil
            }
            Button("Use It Anyway") {
                if let pendingDraft {
                    model.saveEditor(pendingDraft)
                    dismiss()
                }
                conflictMessage = nil
                pendingDraft = nil
            }
        } message: {
            Text((conflictMessage ?? "") + "\n\nSaving won't stop anything — DevPorts will just point this entry at that port.")
        }
    }

    private func form(for current: EditorDraft) -> some View {
        let binding = Binding<EditorDraft>(
            get: { draft ?? current },
            set: { draft = $0 }
        )

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(current.title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                // Built by concatenation, not interpolation: a SwiftUI Text literal would
                // localise the number and render port 3000 as "3,000".
                Text(current.port == 0 ? "no port" : "port " + String(current.port))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                field("Name") {
                    TextField("Project name", text: binding.name)
                        .textFieldStyle(.roundedBorder)
                }

                if current.mode != .renameOnly {
                    field("Start command") {
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("npm run dev", text: binding.command)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                            Text("Runs in a login shell from the directory below, so nvm and Homebrew paths resolve.")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                    }

                    field("Directory") {
                        HStack(spacing: 6) {
                            TextField("~/Dev/project", text: binding.directory)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                            Button("Choose…") { chooseDirectory(into: binding) }
                                .controlSize(.small)
                        }
                    }

                    field("Open with") {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 10) {
                                Picker("", selection: binding.scheme) {
                                    ForEach(URLScheme.known, id: \.self) { scheme in
                                        Text(scheme).tag(scheme)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.segmented)
                                .frame(width: 128)

                                HStack(spacing: 5) {
                                    Text("Port")
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(.secondary)
                                    TextField("3000", text: portText(binding))
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(size: 12, design: .monospaced))
                                        .frame(width: 74)
                                }

                                Spacer(minLength: 0)
                            }

                            Text(previewURL(current))
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(.tertiary)

                            Text("Exported to the command as $PORT, and used for Open in Browser. A command that hard-codes its port ignores it — DevPorts will tell you where it actually landed.")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                if let warning = current.commandWarning {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                        Text(warning)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(16)

            Divider()

            HStack(spacing: 8) {
                if current.mode == .editFavorite {
                    Button("Delete Favorite", role: .destructive) {
                        deleteFavorite(current)
                    }
                    .controlSize(.regular)
                }
                Spacer()
                Button("Cancel") {
                    model.editor = nil
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button(current.mode == .createFavorite ? "Save" : "Done") {
                    attemptSave(binding.wrappedValue)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid(current))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Saving

    private func attemptSave(_ value: EditorDraft) {
        if let message = model.portConflict(for: value) {
            pendingDraft = value
            conflictMessage = message
            return
        }
        model.saveEditor(value)
        dismiss()
    }

    private func isValid(_ draft: EditorDraft) -> Bool {
        guard draft.mode != .renameOnly else { return true }
        guard (1...65_535).contains(draft.port) else { return false }
        return !draft.command.trimmingCharacters(in: .whitespaces).isEmpty
            && !draft.directory.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Fields

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(.secondary)
            content()
        }
    }

    /// Digits only, capped at the 16-bit port range. An empty field reads back as 0,
    /// which `isValid` rejects, so the Save button disables instead of saving a bad port.
    private func portText(_ binding: Binding<EditorDraft>) -> Binding<String> {
        Binding(
            get: { binding.wrappedValue.port == 0 ? "" : String(binding.wrappedValue.port) },
            set: { text in
                let digits = String(text.filter(\.isNumber).prefix(5))
                binding.wrappedValue.port = min(65_535, Int(digits) ?? 0)
            }
        )
    }

    private func previewURL(_ draft: EditorDraft) -> String {
        draft.port == 0 ? "\(draft.scheme)://localhost:…" : "\(draft.scheme)://localhost:\(draft.port)"
    }

    private func chooseDirectory(into binding: Binding<EditorDraft>) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if !binding.wrappedValue.directory.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: binding.wrappedValue.directory)
        }
        if panel.runModal() == .OK, let url = panel.url {
            binding.wrappedValue.directory = url.path
        }
    }

    private func deleteFavorite(_ current: EditorDraft) {
        guard let favoriteID = current.favoriteID else { return }
        model.deleteFavorite(PortRow(
            id: current.rowKey,
            port: current.port,
            displayName: current.name,
            subtitle: "",
            processLabel: "",
            bindSummary: "",
            scheme: current.scheme,
            isRunning: false,
            isSystem: false,
            isFavorite: true,
            commandVerified: true,
            pid: nil,
            stopRootPID: nil,
            directory: current.directory,
            command: current.command,
            favoriteID: favoriteID,
            hasAlias: false
        ))
        dismiss()
    }
}
