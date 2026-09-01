import AppKit
import SwiftUI

enum Theme {
    static let panelWidth: CGFloat = 400
    static let maxListHeight: CGFloat = 460
    static let rowRadius: CGFloat = 7
    static let gutter: CGFloat = 10
}

enum Symbols {
    /// SF Symbol names drift between releases; fall back rather than render a blank slot.
    static func firstAvailable(_ names: [String], fallback: String = "circle") -> String {
        for name in names where NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil {
            return name
        }
        return fallback
    }

    static let menuBar = firstAvailable(
        ["powerplug.portrait.fill", "powerplug.fill", "powerplug", "network"],
        fallback: "network"
    )
    static let open = firstAvailable(["arrow.up.forward.app", "safari"], fallback: "safari")
    static let restart = firstAvailable(["arrow.clockwise"], fallback: "arrow.clockwise")
    static let stop = firstAvailable(["stop.fill"], fallback: "xmark")
    static let start = firstAvailable(["play.fill"], fallback: "play")
    static let favorite = "star"
    static let favoriteFilled = "star.fill"
    static let more = "ellipsis"
}

/// Compact, borderless icon button used across every row.
struct RowIconButton: View {
    let symbol: String
    let help: String
    var tint: Color = .primary
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 22, height: 20)
                .foregroundStyle(tint)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(hovering ? Color.primary.opacity(0.10) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// Monospaced port chip — the primary identifier in every row.
struct PortChip: View {
    let port: Int
    let isRunning: Bool

    var body: some View {
        Text(String(port))
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundStyle(isRunning ? Color.primary : Color.secondary)
            .frame(width: 52, height: 22)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.primary.opacity(isRunning ? 0.08 : 0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07))
            )
    }
}

struct StatusDot: View {
    let isRunning: Bool
    let isBusy: Bool

    var body: some View {
        Circle()
            .fill(isRunning ? Color.green : Color.secondary.opacity(0.45))
            .frame(width: 6, height: 6)
            .opacity(isBusy ? 0.35 : 1)
            .overlay {
                if isBusy {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.55)
                }
            }
            .frame(width: 14)
    }
}

/// Tab in the panel's segmented header. Counts are post-filter, so they answer
/// "how many will I see if I click this" rather than "how many exist".
struct TabButton: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                Text(String(count))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isSelected ? Color.secondary : Color.secondary.opacity(0.6))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(background)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var background: Color {
        if isSelected { return Color.primary.opacity(0.10) }
        return hovering ? Color.primary.opacity(0.05) : .clear
    }
}
