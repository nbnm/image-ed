import AppKit
import SwiftUI

// Render the app's actual native views with sample-only data. No desktop capture
// or user files are involved in these documentation screenshots.
@main
@MainActor
struct CaptureDemos {
    static func main() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let output = root.appendingPathComponent("build/docs-capture")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let model = EditorModel()
        let view = NSHostingView(rootView: EditorView(model: model).environment(\.controlActiveState, .key))
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 1220, height: 800),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        view.frame = NSRect(x: 0, y: 0, width: 1220, height: 800)
        window.backgroundColor = NSColor(hex: "FAFBF8")

        func save(_ target: NSView, _ name: String) async throws {
            try await Task.sleep(for: .milliseconds(120))
            target.layoutSubtreeIfNeeded()
            target.displayIfNeeded()
            let bounds = target.bounds
            guard let bitmap = target.bitmapImageRepForCachingDisplay(in: bounds) else { throw ImageError.cannotRender }
            target.cacheDisplay(in: bounds, to: bitmap)
            guard let data = bitmap.representation(using: .png, properties: [:]) else { throw ImageError.cannotRender }
            try data.write(to: output.appendingPathComponent(name + ".png"))
            print(name)
        }

        var frames: [(String, Double)] = []
        func capture(_ name: String, hold: Double = 1) async throws {
            try await save(view, name)
            frames.append((name, hold))
        }
        func finish(_ name: String) throws {
            var manifest = "ffconcat version 1.0\n"
            for (file, hold) in frames {
                manifest += "file '\(file).png'\nduration \(hold)\n"
            }
            if let last = frames.last { manifest += "file '\(last.0).png'\n" }
            try manifest.write(to: output.appendingPathComponent(name + ".ffconcat"), atomically: true, encoding: .utf8)
            frames = []
        }

        try await capture("text-00-welcome", hold: 1.4)
        model.openSample()
        while model.isLoading { await Task.yield() }
        try await capture("text-01-open", hold: 1)
        model.addText()
        try await capture("text-02-add", hold: 0.8)
        model.updateText { $0.fontSize = 72; $0.text = "Alpine" }
        try await capture("text-03-type", hold: 0.45)
        model.updateText { $0.text = "Alpine lake" }
        try await capture("text-04-type", hold: 0.85)
        let textStart = model.currentText!
        model.beginTransaction("Move text")
        for step in 1...9 {
            let fraction = CGFloat(step) / 9
            model.updateText {
                $0.x = textStart.x + (110 - textStart.x) * fraction
                $0.y = textStart.y + (930 - textStart.y) * fraction
            }
            try await capture("text-move-\(step)", hold: step == 9 ? 0.8 : 0.1)
        }
        model.endTransaction()
        model.updateText { $0.whiteBox = false; $0.color = "FAFBF8" }
        try await capture("text-transparent", hold: 1.2)
        model.updateText { $0.whiteBox = true; $0.color = "243D35" }
        try await capture("text-white-box", hold: 1.2)
        try finish("text")

        model.selectTool(.image)
        try await capture("overlay-00-tool", hold: 1)
        let overlay = try ImageAsset.load(root.appendingPathComponent("Resources/Brand/EddieCharacter.png"))
        model.addImages([overlay])
        try await capture("overlay-01-added", hold: 1)
        let imageStart = model.currentImage!
        model.beginTransaction("Move image overlay")
        for step in 1...9 {
            let fraction = CGFloat(step) / 9
            model.updateImage("Move image overlay") {
                $0.rect.origin = CGPoint(x: imageStart.rect.minX + (1000 - imageStart.rect.minX) * fraction,
                                         y: imageStart.rect.minY + (610 - imageStart.rect.minY) * fraction)
            }
            try await capture("overlay-move-\(step)", hold: step == 9 ? 0.65 : 0.1)
        }
        model.endTransaction()
        let initialWidth = model.currentImage!.rect.width
        model.beginTransaction("Resize image overlay")
        for step in 1...7 {
            model.setImageWidth(initialWidth + (300 - initialWidth) * CGFloat(step) / 7)
            try await capture("overlay-size-\(step)", hold: step == 7 ? 0.8 : 0.1)
        }
        model.endTransaction()
        model.updateImage("Change overlay opacity") { $0.opacity = 0.55 }
        try await capture("overlay-opacity", hold: 1.2)
        model.updateImage("Change overlay opacity") { $0.opacity = 1 }
        try await capture("overlay-final", hold: 1.2)
        try finish("overlays")

        model.resetAll()
        model.selectTool(.crop)
        try await capture("crop-00-tool", hold: 0.9)
        model.setCropRatio(.square)
        try await capture("crop-01-square", hold: 1)
        for step in 1...6 {
            let fraction = CGFloat(step) / 6
            model.cropSelection = CGRect(x: 200 + 100 * fraction, y: 100 * fraction,
                                         width: 1200 - 200 * fraction, height: 1200 - 200 * fraction)
            try await capture("crop-corner-\(step)", hold: step == 6 ? 0.8 : 0.1)
        }
        model.applyCrop()
        try await capture("crop-02-applied", hold: 0.9)
        model.selectTool(.resize)
        try await capture("resize-00-tool", hold: 0.9)
        model.resize(width: 800, height: 800)
        try await capture("resize-01-applied", hold: 1)
        model.notice = nil
        model.selectTool(.color)
        try await capture("color-00-tool", hold: 0.8)
        for preset in [ColorPreset.mono, .noir, .warm] {
            model.commit("Change filter") { $0.preset = preset }
            try await capture("color-\(preset.id)", hold: 1.1)
        }
        try finish("crop-color")

        func exportFrame(_ name: String, settings: ExportSettings, hold: Double) async throws {
            let content = ZStack {
                Theme.canvas
                ExportView(model: model, settings: settings)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(color: Theme.ink.opacity(0.10), radius: 20, y: 6)
            }.frame(width: 1220, height: 800).environment(\.controlActiveState, .key)
            let host = NSHostingView(rootView: content)
            let panel = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 1220, height: 800),
                                 styleMask: [.borderless], backing: .buffered, defer: false)
            panel.contentView = host
            host.frame = NSRect(x: 0, y: 0, width: 1220, height: 800)
            try await save(host, name)
            frames.append((name, hold))
        }
        try await exportFrame("export-png", settings: ExportSettings(format: .png), hold: 1.8)
        try await exportFrame("export-jpeg-high", settings: ExportSettings(format: .jpeg, quality: 0.9), hold: 1.8)
        try await exportFrame("export-jpeg-small", settings: ExportSettings(format: .jpeg, quality: 0.45), hold: 1.8)
        try await exportFrame("export-svg", settings: ExportSettings(format: .svg), hold: 1.8)
        try finish("export")
    }
}
