import SwiftUI

/// Attention Rail (V1): 220px, collapsible to 48px. One row per pane —
/// provider glyph, title, `cwd · branch` subline, status. Blocked rows keep
/// their ring marker even collapsed.
struct RailView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            if !appState.railCollapsed {
                Text("SESSIONS")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 4)
            }
            List {
                ForEach(appState.panes) { pane in
                    RailRow(pane: pane,
                            collapsed: appState.railCollapsed,
                            selected: appState.focusedId == pane.id,
                            index: appState.panes.firstIndex(where: { $0.id == pane.id }) ?? 0)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { rename(pane) }
                        .onTapGesture(count: 1) {
                            appState.focusedId = pane.id
                            pane.unread = false
                        }
                }
                .onMove { from, to in appState.panes.move(fromOffsets: from, toOffset: to) }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            Spacer(minLength: 0)
        }
        .frame(width: appState.railCollapsed ? 48 : 220)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func rename(_ pane: Pane) {
        let alert = NSAlert()
        alert.messageText = "Rename session"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 22))
        field.stringValue = pane.title
        alert.accessoryView = field
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn, !field.stringValue.isEmpty {
            pane.title = field.stringValue
        }
    }
}

struct RailRow: View {
    @ObservedObject var pane: Pane
    let collapsed: Bool
    let selected: Bool
    let index: Int

    /// Provider mark is a *shape*, not just color (V1).
    private var glyph: String {
        switch pane.agent {
        case "claude": return "◐"
        case "codex": return "◆"
        case "grok": return "▲"
        default: return "▣"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(glyph)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 14)
            if !collapsed {
                VStack(alignment: .leading, spacing: 1) {
                    Text(pane.title)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Text("\(pane.cwdSubline)\(pane.status.railLabel.isEmpty ? "" : " · ")\(pane.status.railLabel)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            statusMark
        }
        .frame(height: collapsed ? 40 : 44)
        .padding(.horizontal, collapsed ? 0 : 8)
        .background(selected ? Color.accentColor.opacity(0.15) : .clear)
        .cornerRadius(6)
        .accessibilityLabel("\(pane.title), \(pane.status.railLabel)")
    }

    @ViewBuilder
    private var statusMark: some View {
        switch pane.status {
        case .blocked:
            Circle()
                .stroke(Color.accentColor, lineWidth: 2)
                .frame(width: 12, height: 12)
                .help("awaiting input")
        case .done where pane.unread:
            Circle()
                .fill(Color.accentColor)
                .frame(width: 7, height: 7)
                .help("done — unread")
        case .working:
            Circle()
                .strokeBorder(Color.secondary, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                .frame(width: 10, height: 10)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9))
                .foregroundStyle(.red)
        case .idle:
            Circle().fill(Color.secondary.opacity(0.4)).frame(width: 5, height: 5)
        case .unknown:
            Circle()
                .stroke(Color.secondary.opacity(0.4), lineWidth: 1)
                .frame(width: 5, height: 5)
                .help(pane.processAlive ? "unknown — process alive" : "unknown — no process")
        default:
            EmptyView()
        }
    }
}
