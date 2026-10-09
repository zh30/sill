import SwiftUI

/// Chrome tokens — the `themes/void.toml` [chrome] layer as SwiftUI.
/// The app's own theme pack file is the source of truth; these mirror it.
/// Accent is reserved for attention (blocked ring, selected row, primary CTA).
enum T {
    // surfaces (void.toml chrome layer)
    static let bg = Color(hex: 0x0C0C0E)        // window
    static let surface = Color(hex: 0x111113)   // cards, strips, composer
    static let raised = Color(hex: 0x161618)    // rail, hover states
    static let rowHover = Color(hex: 0x1E1E21)
    static let border = Color(hex: 0x26262A)
    static let borderSoft = Color(hex: 0x1D1D20)

    // text
    static let fg = Color(hex: 0xE8E8EA)
    static let subtle = Color(hex: 0x8E8E93)
    static let faint = Color(hex: 0x5A5A5E)

    // semantic
    static let accent = Color(hex: 0x0A84FF)
    static let error = Color(hex: 0xFF453A)
    static let ok = Color(hex: 0x32D74B)

    // type
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    // metrics
    static let radiusSm: CGFloat = 6
    static let radiusMd: CGFloat = 9
    static let railWidth: CGFloat = 224
    static let railCollapsed: CGFloat = 52
    static let stripHeight: CGFloat = 36
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// Provider tile — a small bordered square with the provider glyph.
struct GlyphTile: View {
    let agent: String?
    var size: CGFloat = 22

    private var glyph: String {
        switch agent {
        case "claude": return "◐"
        case "codex": return "◆"
        case "grok": return "▲"
        default: return "▣"
        }
    }

    var body: some View {
        Text(glyph)
            .font(T.ui(size * 0.55, .medium))
            .foregroundStyle(T.subtle)
            .frame(width: size, height: size)
            .background(T.raised)
            .overlay(RoundedRectangle(cornerRadius: size * 0.25).stroke(T.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: size * 0.25))
    }
}

/// Flat button: filled accent (primary) or bordered (ghost). No system chrome.
struct SillButtonStyle: ButtonStyle {
    var primary = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(T.ui(12, primary ? .medium : .regular))
            .foregroundStyle(primary ? .white : T.fg)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(primary ? T.accent : T.raised)
            .overlay(
                RoundedRectangle(cornerRadius: T.radiusSm)
                    .stroke(primary ? .clear : T.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: T.radiusSm))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// Status marker: blocked = accent ring (the signature), done-unread = filled
/// dot, working = dashed spin ring, error = triangle, idle/unknown = muted.
struct StatusMark: View {
    let pane: Pane

    var body: some View {
        Group {
            switch pane.status {
            case .blocked:
                Circle()
                    .stroke(T.accent, lineWidth: 2)
                    .frame(width: 11, height: 11)
                    .help("awaiting input")
            case .done where pane.unread:
                Circle().fill(T.accent).frame(width: 6, height: 6).help("done — unread")
            case .working:
                Circle()
                    .strokeBorder(T.subtle, style: StrokeStyle(lineWidth: 1.4, dash: [3, 2]))
                    .frame(width: 9, height: 9)
                    .help("working")
            case .error:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(T.ui(9))
                    .foregroundStyle(T.error)
                    .help("error")
            case .idle:
                Circle().fill(T.faint).frame(width: 5, height: 5).help("idle")
            case .unknown:
                Circle()
                    .stroke(T.faint, lineWidth: 1)
                    .frame(width: 5, height: 5)
                    .help(pane.processAlive ? "unknown — process alive" : "unknown — no process")
            case .done:
                Image(systemName: "checkmark")
                    .font(T.ui(8, .semibold))
                    .foregroundStyle(T.subtle)
                    .help("done")
            }
        }
        .frame(width: 14, alignment: .trailing)
    }
}
