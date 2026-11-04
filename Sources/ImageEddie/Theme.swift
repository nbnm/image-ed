import SwiftUI

enum Theme {
    static let ink = Color(nsColor: NSColor(hex: "243B33"))
    static let secondary = Color(nsColor: NSColor(hex: "7D857F"))
    static let accent = Color(nsColor: NSColor(hex: "3C6B55"))
    static let mint = Color(nsColor: NSColor(hex: "E5EDE3"))
    static let paper = Color(nsColor: NSColor(hex: "FAFBF8"))
    static let canvas = Color(nsColor: NSColor(hex: "EBEEE8"))
    static let line = Color(nsColor: NSColor(hex: "DFE4DB"))
}

struct PrimaryButtonStyle: ButtonStyle {
    var compact = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 12 : 13, weight: .semibold))
            .padding(.horizontal, compact ? 15 : 21)
            .frame(height: compact ? 32 : 38)
            .foregroundStyle(Color.white.opacity(enabled ? 1 : 0.7))
            .background(enabled ? Theme.ink : Theme.secondary.opacity(0.4), in: RoundedRectangle(cornerRadius: 7))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct QuietButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(enabled ? Theme.ink : Theme.secondary.opacity(0.5))
            .padding(.horizontal, 12).frame(height: 32)
            .background(configuration.isPressed ? Theme.line : Color.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.line))
    }
}

struct IconButton: View {
    let symbol: String
    let help: String
    var enabled = true
    let action: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .regular))
                .foregroundStyle(enabled ? Theme.ink : Theme.secondary.opacity(0.35))
                .frame(width: 30, height: 30)
                .background(hovered && enabled ? Theme.line.opacity(0.7) : .clear, in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain).disabled(!enabled).help(help).accessibilityLabel(help)
        .onHover { hovered = $0 }
    }
}

struct FieldLabel: View {
    let title: String
    var body: some View {
        Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.secondary)
    }
}

struct InspectorHeading: View {
    let title: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 17, weight: .semibold)).tracking(-0.4).foregroundStyle(Theme.ink)
            Text(detail).font(.system(size: 12)).foregroundStyle(Theme.secondary).lineSpacing(3)
        }
    }
}

struct EddieMark: View {
    private static let artwork: NSImage = {
        let bundled = Bundle.main.url(forResource: "EddieCharacter", withExtension: "png")
        let development = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources/Brand/EddieCharacter.png")
        return NSImage(contentsOf: bundled ?? development) ?? NSImage()
    }()
    var size: CGFloat = 56
    var body: some View {
        Image(nsImage: Self.artwork).resizable().interpolation(.high).scaledToFit()
            .frame(width: size, height: size)
            .accessibilityLabel("Image-Eddie character logo")
    }
}
