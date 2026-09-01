import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject private var model: PortsViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            header
            tabBar
            Divider()

            if let banner = model.banner {
                BannerView(banner: banner) { model.dismissBanner() }
            }

            if let failure = model.lastScanFailure {
                BannerView(banner: Banner(text: failure, kind: .error), onDismiss: nil)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.rowSpacing) {
                    let rows = model.rows(for: model.tab)
                    if rows.isEmpty {
                        emptyState
                    } else {
                        ForEach(rows) { row in
                            PortRowView(row: row)
                        }
                    }
                }
                // A favorite appears in both tabs with the same identity; keying the stack
                // to the tab stops SwiftUI from reusing a row view across the switch.
                .id(model.tab)
                .padding(.vertical, Theme.listPadding)
            }
            // Shrinks to fit when there are fewer than seven rows, scrolls past that.
            .frame(maxHeight: Theme.maxListHeight)
            .scrollBounceBehavior(.basedOnSize)

            Divider()
            footer
        }
        .frame(width: Theme.panelWidth)
        .onAppear { model.panelAppeared() }
        .onDisappear { model.panelDisappeared() }
        .onChange(of: model.editor?.id) { _, newValue in
            guard newValue != nil else { return }
            openWindow(id: EditorWindow.id)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                TextField("Filter by port, name or path", text: $model.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !model.searchText.isEmpty {
                    Button {
                        model.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )

            RowIconButton(symbol: "arrow.clockwise", help: "Refresh") { model.refresh() }
                .opacity(model.isRefreshing ? 0.4 : 1)

            Menu {
                Toggle("Show system processes", isOn: $model.showSystem)
                Divider()
                Button("Open Data Folder") {
                    NSWorkspace.shared.open(Paths.supportDirectory)
                }
                Divider()
                Button("Quit DevPorts") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 20)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 22)
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.vertical, 8)
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(PortsViewModel.Tab.allCases, id: \.self) { tab in
                TabButton(
                    title: tab.title,
                    count: model.rows(for: tab).count,
                    isSelected: model.tab == tab
                ) {
                    model.tab = tab
                }
            }
            Spacer()
        }
        .padding(.horizontal, Theme.gutter - 2)
        .padding(.bottom, 8)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 6) {
            Text(String(model.runningRows.count) + " listening")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)

            if model.hiddenSystemCount > 0 {
                Button {
                    model.showSystem = true
                } label: {
                    Text("· " + String(model.hiddenSystemCount) + " system hidden")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Show system processes")
            }

            Spacer()

            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Theme.gutter + 2)
        .padding(.vertical, 7)
    }

    private var emptyState: some View {
        let otherTab: PortsViewModel.Tab = model.tab == .running ? .favorites : .running
        let otherCount = model.rows(for: otherTab).count

        return VStack(spacing: 6) {
            Image(systemName: model.tab == .running ? Symbols.menuBar : Symbols.favorite)
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(.tertiary)

            Text(emptyTitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            if !model.searchText.isEmpty, otherCount > 0 {
                Button {
                    model.tab = otherTab
                } label: {
                    Text(String(otherCount) + " in " + otherTab.title)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            } else if model.searchText.isEmpty {
                Text(emptyHint)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
    }

    private var emptyTitle: String {
        if !model.searchText.isEmpty { return "No matches" }
        return model.tab == .running ? "No dev servers listening" : "No favorites yet"
    }

    private var emptyHint: String {
        if model.tab == .favorites {
            return "Star a running port to save its command"
        }
        return model.hiddenSystemCount > 0
            ? String(model.hiddenSystemCount) + " system processes are hidden"
            : "Start a dev server and it shows up here"
    }
}

struct BannerView: View {
    let banner: Banner
    let onDismiss: (() -> Void)?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: banner.kind == .error ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(banner.kind == .error ? Color.orange : Color.accentColor)
            Text(banner.text)
                .font(.system(size: 11))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let onDismiss {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.vertical, 7)
        .background(banner.kind == .error ? Color.orange.opacity(0.10) : Color.accentColor.opacity(0.10))
    }
}
