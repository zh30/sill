import SwiftUI

/// Attention Rail (V1): 224px, collapsible to 52px. One row per pane —
/// provider tile, title, `cwd · status` subline, status marker. Blocked rows
/// keep their accent ring even collapsed.
struct RailView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            if appState.railCollapsed {
                collapseButton(expanded: false)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
            } else {
                HStack {
                    Text("SESSIONS")
                        .font(T.ui(10, .semibold))
                        .foregroundStyle(T.faint)
                        .tracking(1.2)
                    Spacer()
                    collapseButton(expanded: true)
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)
            }

            if appState.panes.isEmpty && !appState.railCollapsed {
                Text("No sessions\n⌘N to start")
                    .font(T.ui(10))
                    .foregroundStyle(T.faint)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
            }

            List {
                ForEach(Array(appState.panes.enumerated()), id: \.element.id) { index, pane in
                    RailRow(pane: pane,
                            collapsed: appState.railCollapsed,
                            selected: appState.focusedId == pane.id,
                            index: index)
                        .listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .onTapGesture(count: 2) { rename(pane) }
                        .onTapGesture(count: 1) {
                            appState.focusedId = pane.id
                            pane.unread = false
                        }
                }
                .onMove { from, to in appState.panes.move(fromOffsets: from, toOffset: to) }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)

            Spacer(minLength: 0)

            if !appState.railCollapsed {
                Divider().overlay(T.borderSoft)
                HStack(spacing: 6) {
                    Text("⌘N new · ⌘' jump · ⌘B rail")
                        .font(T.ui(10))
                        .foregroundStyle(T.faint)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
        }
        .frame(width: appState.railCollapsed ? T.railCollapsed : T.railWidth)
        .background(T.raised)
        .animation(.easeOut(duration: 0.15), value: appState.railCollapsed)
    }

    private func collapseButton(expanded: Bool) -> some View {
        Button { appState.railCollapsed.toggle() } label: {
            Image(systemName: expanded ? "chevron.left" : "chevron.right")
                .font(T.ui(9, .semibold))
                .foregroundStyle(T.faint)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(expanded ? "Collapse rail (⌘B)" : "Expand rail (⌘B)")
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
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 9) {
            GlyphTile(agent: pane.agent, size: collapsed ? 24 : 22)
            if !collapsed {
                VStack(alignment: .leading, spacing: 1) {
                    Text(pane.title)
                        .font(T.ui(12, .medium))
                        .foregroundStyle(T.fg)
                        .lineLimit(1)
                    Text("\(pane.cwdSubline)\(pane.status.railLabel.isEmpty ? "" : " · ")\(pane.status.railLabel)")
                        .font(T.ui(10))
                        .foregroundStyle(T.subtle)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
            }
            StatusMark(pane: pane)
        }
        .frame(height: collapsed ? 44 : 46)
        .padding(.horizontal, collapsed ? 0 : 8)
        .background(selected ? T.rowHover : (hovering ? T.rowHover.opacity(0.5) : .clear))
        .clipShape(RoundedRectangle(cornerRadius: T.radiusSm))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .accessibilityLabel("\(pane.title), \(pane.status.railLabel)")
        .help(collapsed ? "\(pane.title) — \(pane.status.railLabel)" : "")
    }
}
