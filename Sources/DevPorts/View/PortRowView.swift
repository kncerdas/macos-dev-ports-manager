import SwiftUI

struct PortRowView: View {
    @EnvironmentObject private var model: PortsViewModel
    let row: PortRow

    @State private var hovering = false

    private var isBusy: Bool { model.busyRows.contains(row.id) }
    private var isPrompting: Bool { model.stopPrompt?.rowKey == row.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                StatusDot(isRunning: row.isRunning, isBusy: isBusy)
                PortChip(port: row.port, isRunning: row.isRunning)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(row.displayName)
                            .font(.system(size: 12.5, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if row.isFavorite {
                            Image(systemName: Symbols.favoriteFilled)
                                .font(.system(size: 8))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Text(metaLine)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }

                Spacer(minLength: 4)
                actions.opacity(hovering || isPrompting || !row.isRunning ? 1 : 0)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.vertical, 6)

            if isPrompting, let prompt = model.stopPrompt {
                StopConfirmView(prompt: prompt, row: row)
                    .padding(.leading, Theme.gutter + 22)
                    .padding(.trailing, Theme.gutter)
                    .padding(.bottom, 8)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
                .fill(hovering || isPrompting ? Color.primary.opacity(0.055) : .clear)
        )
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu { menuItems }
    }

    private var metaLine: String {
        var parts: [String] = [row.subtitle]
        if let savedPort = row.savedPort { parts.append("saved :\(savedPort)") }
        if !row.processLabel.isEmpty { parts.append(row.processLabel) }
        if !row.bindSummary.isEmpty { parts.append(row.bindSummary) }
        if let pid = row.pid { parts.append("pid \(pid)") }
        return parts.filter { !$0.isEmpty }.joined(separator: "  ·  ")
    }

    // MARK: - Actions

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 1) {
            if row.isRunning {
                RowIconButton(symbol: Symbols.open, help: "Open \(row.scheme)://localhost:\(row.port)") {
                    model.openInBrowser(row)
                }
                RowIconButton(symbol: Symbols.restart, help: "Restart") {
                    model.restart(row)
                }
                RowIconButton(symbol: Symbols.stop, help: "Stop", tint: .red.opacity(0.85)) {
                    model.requestStop(row)
                }
            } else {
                RowIconButton(symbol: Symbols.start, help: "Start", tint: .green) {
                    model.start(row)
                }
            }

            RowIconButton(
                symbol: row.isFavorite ? Symbols.favoriteFilled : Symbols.favorite,
                help: row.isFavorite ? "Remove from favorites" : "Save to favorites",
                tint: row.isFavorite ? .yellow : .primary
            ) {
                model.toggleFavorite(row)
            }

            Menu {
                menuItems
            } label: {
                Image(systemName: Symbols.more)
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 20)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 22)
        }
        .disabled(isBusy)
    }

    @ViewBuilder
    private var menuItems: some View {
        Button(row.isFavorite ? "Edit…" : "Rename…") { model.beginRename(row) }
        if let savedPort = row.savedPort {
            // Concatenated, not interpolated: a Text/Button literal would render "3,000".
            Button("Save Port " + String(row.port) + " (replaces " + String(savedPort) + ")") {
                model.adoptObservedPort(row)
            }
        }
        if row.isRunning {
            Button("Open in Browser") { model.openInBrowser(row) }
            Button("Copy PID") { model.copyPID(row) }
        }
        if let directory = row.directory, !directory.isEmpty {
            Button("Reveal in Finder") { model.revealInFinder(row) }
        }
        if row.isFavorite {
            Button("View Log") { model.openLog(row) }
            Divider()
            Button("Delete Favorite", role: .destructive) { model.deleteFavorite(row) }
        }
    }
}
