import SwiftUI

struct ExportView: View {
    @ObservedObject var model: EditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var settings = ExportSettings()
    init(model: EditorModel, settings: ExportSettings = ExportSettings()) {
        self.model = model
        self._settings = State(initialValue: settings)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 23) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Export image").font(.system(size: 23, weight: .semibold)).tracking(-0.7)
                    Text("Choose a format for your image.").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
                Spacer()
                IconButton(symbol: "xmark", help: "Cancel export") { dismiss() }
            }
            if let preview = model.preview, let state = model.state {
                HStack(spacing: 14) {
                    ZStack {
                        Checkerboard()
                        Image(nsImage: preview).resizable().scaledToFit()
                    }.frame(width: 67, height: 54).clipShape(RoundedRectangle(cornerRadius: 4))
                    VStack(alignment: .leading, spacing: 6) {
                        Text((model.asset?.name as NSString?)?.deletingPathExtension ?? "Image").font(.system(size: 12, weight: .medium)).lineLimit(1)
                        Text("\(state.width) × \(state.height) px").font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                }.padding(12).background(Theme.canvas.opacity(0.6), in: RoundedRectangle(cornerRadius: 7))
            }
            VStack(alignment: .leading, spacing: 10) {
                FieldLabel(title: "File format")
                HStack(spacing: 7) {
                    ForEach(ExportFormat.allCases) { format in
                        Button { settings.format = format } label: {
                            Text(format.rawValue).font(.system(size: 12, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 38)
                                .background(settings.format == format ? Theme.mint : Color.white, in: RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(settings.format == format ? Theme.accent.opacity(0.65) : Theme.line))
                        }.buttonStyle(.plain)
                    }
                }
                Text(formatDescription).font(.system(size: 11)).foregroundStyle(Theme.secondary).lineSpacing(3)
                    .frame(height: 32, alignment: .topLeading)
            }
            if settings.format == .jpeg {
                VStack(spacing: 11) {
                    HStack {
                        FieldLabel(title: "Quality")
                        Spacer()
                        Text("\(Int((settings.quality * 100).rounded()))%")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                    }
                    Slider(value: $settings.quality, in: 0.1...1, step: 0.01).tint(Theme.accent).accessibilityLabel("JPEG quality")
                    HStack {
                        Text("Smaller file"); Spacer(); Text("Better quality")
                    }.font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    HStack {
                        FieldLabel(title: "Background")
                        Spacer()
                        ColorPicker("JPEG background", selection: Binding(get: { Color(nsColor: NSColor(hex: settings.background)) }, set: {
                            settings.background = NSColor($0).hex
                        }), supportsOpacity: false).labelsHidden()
                    }.padding(.top, 9)
                }
            }
            Divider().overlay(Theme.line)
            HStack {
                Button("Cancel") { dismiss() }.buttonStyle(QuietButtonStyle()).keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    let result = settings
                    dismiss()
                    // Present the native save panel after this sheet has left the window.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { model.save(result) }
                } label: { HStack(spacing: 8) { Text("Export image"); Image(systemName: "arrow.up.right").font(.system(size: 11)) } }
                    .buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
            }
        }
        .padding(28).frame(width: 420).background(Theme.paper).foregroundStyle(Theme.ink)
        .animation(.easeOut(duration: 0.15), value: settings.format)
    }
    private var formatDescription: String {
        switch settings.format {
        case .png: "Full quality, with support for transparent backgrounds."
        case .jpeg: "A smaller file for sharing. Transparent areas use the background color."
        case .svg: model.asset?.svg != nil ? "Scalable artwork, image overlays, and text preserved." : "Your images embedded in an SVG, with vector text."
        }
    }
}
