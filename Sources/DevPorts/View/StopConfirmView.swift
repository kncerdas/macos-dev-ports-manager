import SwiftUI

/// Inline confirmation. Lives inside the row rather than in a popover so the menu bar
/// panel never loses key focus and dismisses itself mid-decision.
struct StopConfirmView: View {
    @EnvironmentObject private var model: PortsViewModel
    let prompt: StopPrompt
    let row: PortRow

    @State private var remember = false

    private var treeCount: Int { prompt.tree.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(treeCount > 1 ? "Stop just the listener, or the whole tree?" : "Stop this process?")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            if treeCount > 1 {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(prompt.tree) { entry in
                        HStack(spacing: 5) {
                            Text(String(entry.pid))
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundStyle(entry.pid == prompt.listeningPID ? .primary : .secondary)
                                .frame(width: 44, alignment: .trailing)
                            Text(entry.label)
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundStyle(entry.pid == prompt.listeningPID ? .primary : .secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .padding(.leading, CGFloat(min(entry.depth, 4)) * 9)
                    }
                }
                .padding(7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
            }

            HStack(spacing: 6) {
                Button("Stop Process") {
                    model.perform(stop: row, mode: .process, remember: remember)
                }
                .controlSize(.small)

                if treeCount > 1 {
                    Button("Stop Tree (\(treeCount))") {
                        model.perform(stop: row, mode: .tree, remember: remember)
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                }

                Button("Cancel") { model.stopPrompt = nil }
                    .controlSize(.small)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(.system(size: 11))
            }

            if row.isFavorite {
                Toggle("Remember this choice for “\(row.displayName)”", isOn: $remember)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
