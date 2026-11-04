import SwiftUI

struct CanvasView: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        GeometryReader { geometry in
            let available = CGSize(width: geometry.size.width, height: geometry.size.height - 48)
            let dimensions = CGSize(width: model.state?.width ?? 1, height: model.state?.height ?? 1)
            let fit = max(0.01, min((available.width - 96) / dimensions.width, (available.height - 96) / dimensions.height, 1))
            let scale = model.zoom > 0 ? model.zoom : fit
            let imageSize = CGSize(width: dimensions.width * scale, height: dimensions.height * scale)
            VStack(spacing: 0) {
                ScrollView([.horizontal, .vertical]) {
                    ZStack {
                        if let preview = model.preview, let state = model.state {
                            ZStack(alignment: .topLeading) {
                                Checkerboard()
                                Image(nsImage: preview).resizable().interpolation(.high)
                                    .frame(width: imageSize.width, height: imageSize.height)
                                    .onTapGesture { model.selectedText = nil; model.selectedImage = nil }
                                if model.tool == .image {
                                    ForEach(state.images) { layer in
                                        ImageSelection(model: model, layer: layer, displaySize: imageSize)
                                    }
                                }
                                if model.tool == .text {
                                    ForEach(state.texts) { layer in
                                        TextSelection(model: model, layer: layer, displaySize: imageSize)
                                    }
                                }
                                if model.tool == .crop { CropOverlay(model: model, displaySize: imageSize) }
                            }
                            .frame(width: imageSize.width, height: imageSize.height)
                            .coordinateSpace(name: "image-canvas")
                            .clipped()
                            .overlay(Rectangle().strokeBorder(Theme.ink.opacity(0.07)))
                            .shadow(color: Theme.ink.opacity(0.12), radius: 16, x: 0, y: 5)
                            .accessibilityLabel("Image canvas, \(state.width) by \(state.height) pixels")
                        }
                    }
                    .frame(width: max(available.width, imageSize.width + 96), height: max(available.height, imageSize.height + 96))
                }
                .background(Theme.canvas)
                .overlay(alignment: .topLeading) {
                    if model.tool == .crop {
                        Text("Drag to select · Drag corners to adjust")
                            .font(.system(size: 11)).foregroundStyle(Theme.secondary).padding(.horizontal, 22).padding(.top, 15)
                            .allowsHitTesting(false)
                    }
                }
                HStack(spacing: 9) {
                    Text(model.asset?.format ?? "").font(.system(size: 9, weight: .semibold)).tracking(0.4)
                        .padding(.horizontal, 6).padding(.vertical, 3).background(Theme.mint, in: RoundedRectangle(cornerRadius: 3))
                    Text("\(model.state?.width ?? 0) × \(model.state?.height ?? 0) px")
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.secondary)
                    Spacer()
                    HStack(spacing: 1) {
                        IconButton(symbol: "minus", help: "Zoom out", enabled: scale > 0.05) { model.zoom = max(0.05, scale / 1.25) }
                        Text("\(Int((scale * 100).rounded()))%")
                            .font(.system(size: 11, design: .monospaced)).frame(width: 44)
                        IconButton(symbol: "plus", help: "Zoom in", enabled: scale < 4) { model.zoom = min(4, scale * 1.25) }
                    }
                    Rectangle().fill(Theme.line).frame(width: 1, height: 15).padding(.horizontal, 6)
                    Button { model.zoom = 0 } label: {
                        HStack(spacing: 5) { Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 10)); Text("Fit") }
                            .font(.system(size: 11, weight: .medium)).padding(.horizontal, 8).frame(height: 27)
                            .background(model.zoom == 0 ? Theme.mint : .clear, in: RoundedRectangle(cornerRadius: 4))
                    }.buttonStyle(.plain).help("Fit image · ⌘0")
                }
                .padding(.horizontal, 20).frame(height: 48).background(Theme.paper)
                .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
            }
        }
    }
}

struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            let cell: CGFloat = 12
            for y in 0...Int(size.height / cell) {
                for x in 0...Int(size.width / cell) where (x + y) % 2 == 0 {
                    context.fill(Path(CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell, height: cell)),
                                 with: .color(Color(nsColor: NSColor(hex: "F0F1ED"))))
                }
            }
        }.allowsHitTesting(false)
    }
}

struct TextSelection: View {
    @ObservedObject var model: EditorModel
    let layer: TextLayer
    let displaySize: CGSize
    @State private var dragStart: CGPoint?

    var body: some View {
        if let state = model.state {
            let sx = displaySize.width / state.crop.width
            let sy = displaySize.height / state.crop.height
            let rect = CGRect(x: (layer.x - state.crop.minX) * sx, y: (layer.y - state.crop.minY) * sy,
                              width: layer.rect.width * sx, height: layer.rect.height * sy)
            let selected = model.selectedText == layer.id
            Rectangle().fill(.white.opacity(0.001))
                .overlay {
                    if selected {
                        Rectangle().strokeBorder(Theme.accent, lineWidth: 1)
                        ForEach(0..<4) { corner in
                            Rectangle().fill(.white).frame(width: 5, height: 5)
                                .overlay(Rectangle().strokeBorder(Theme.accent, lineWidth: 1))
                                .position(x: corner % 2 == 0 ? 0 : rect.width, y: corner < 2 ? 0 : rect.height)
                        }
                    }
                }
                .frame(width: max(12, rect.width), height: max(12, rect.height))
                .contentShape(Rectangle())
                .position(x: rect.midX, y: rect.midY)
                .onTapGesture { model.selectedText = layer.id }
                .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .named("image-canvas")).onChanged { value in
                    if dragStart == nil {
                        dragStart = CGPoint(x: layer.x, y: layer.y)
                        model.selectedText = layer.id
                        model.beginTransaction("Move text")
                    }
                    guard let start = dragStart else { return }
                    let x = min(max(state.crop.minX, start.x + value.translation.width / sx), max(state.crop.minX, state.crop.maxX - layer.rect.width))
                    let y = min(max(state.crop.minY, start.y + value.translation.height / sy), max(state.crop.minY, state.crop.maxY - layer.rect.height))
                    model.updateText { $0.x = x; $0.y = y }
                }.onEnded { _ in dragStart = nil; model.endTransaction() })
                .help("Select and drag text")
                .accessibilityLabel("Text: \(layer.text)")
        }
    }
}

struct CropOverlay: View {
    @ObservedObject var model: EditorModel
    let displaySize: CGSize
    @State private var moveStart: CGRect?
    @State private var cornerStart: CGRect?

    var body: some View {
        if let state = model.state {
            let sx = displaySize.width / state.crop.width
            let sy = displaySize.height / state.crop.height
            let selection = model.cropSelection
            let rect = CGRect(x: (selection.minX - state.crop.minX) * sx, y: (selection.minY - state.crop.minY) * sy,
                              width: selection.width * sx, height: selection.height * sy)
            ZStack(alignment: .topLeading) {
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: displaySize))
                    path.addRect(rect)
                }.fill(Theme.ink.opacity(0.48), style: FillStyle(eoFill: true))
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .named("image-canvas")).onChanged { value in
                        let anchor = CGPoint(x: state.crop.minX + value.startLocation.x / sx,
                                             y: state.crop.minY + value.startLocation.y / sy)
                        let pointer = CGPoint(x: state.crop.minX + value.location.x / sx,
                                              y: state.crop.minY + value.location.y / sy)
                        model.cropSelection = cropRect(anchor: anchor, pointer: pointer, bounds: state.crop, ratio: model.cropAspect)
                    })
                Rectangle().fill(Color.white.opacity(0.001))
                    .overlay(Rectangle().strokeBorder(.white.opacity(0.85), lineWidth: 1))
                    .overlay {
                        Path { path in
                            for i in 1...2 {
                                let fraction = CGFloat(i) / 3
                                path.move(to: CGPoint(x: rect.width * fraction, y: 0))
                                path.addLine(to: CGPoint(x: rect.width * fraction, y: rect.height))
                                path.move(to: CGPoint(x: 0, y: rect.height * fraction))
                                path.addLine(to: CGPoint(x: rect.width, y: rect.height * fraction))
                            }
                        }.stroke(.white.opacity(0.35), lineWidth: 0.7)
                    }
                    .frame(width: rect.width, height: rect.height)
                    .contentShape(Rectangle())
                    .position(x: rect.midX, y: rect.midY)
                    .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .named("image-canvas")).onChanged { value in
                        if moveStart == nil { moveStart = selection }
                        guard let start = moveStart else { return }
                        model.cropSelection = CGRect(x: min(max(start.minX + value.translation.width / sx, state.crop.minX), state.crop.maxX - start.width),
                                                     y: min(max(start.minY + value.translation.height / sy, state.crop.minY), state.crop.maxY - start.height),
                                                     width: start.width, height: start.height)
                    }.onEnded { _ in moveStart = nil })
                ForEach(0..<4) { corner in
                    let left = corner % 2 == 0
                    let top = corner < 2
                    CropCorner(left: left, top: top)
                        .frame(width: 24, height: 24).contentShape(Rectangle())
                        .position(x: left ? rect.minX : rect.maxX, y: top ? rect.minY : rect.maxY)
                        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("image-canvas")).onChanged { value in
                            if cornerStart == nil { cornerStart = selection }
                            guard let start = cornerStart else { return }
                            let anchor = CGPoint(x: left ? start.maxX : start.minX, y: top ? start.maxY : start.minY)
                            let pointer = CGPoint(x: (left ? start.minX : start.maxX) + value.translation.width / sx,
                                                  y: (top ? start.minY : start.maxY) + value.translation.height / sy)
                            model.cropSelection = cropRect(anchor: anchor, pointer: pointer, bounds: state.crop, ratio: model.cropAspect)
                        }.onEnded { _ in cornerStart = nil })
                }
            }.frame(width: displaySize.width, height: displaySize.height)
        }
    }

    private func cropRect(anchor: CGPoint, pointer: CGPoint, bounds: CGRect, ratio: CGFloat?) -> CGRect {
        let point = CGPoint(x: min(max(pointer.x, bounds.minX), bounds.maxX), y: min(max(pointer.y, bounds.minY), bounds.maxY))
        let left = point.x < anchor.x, top = point.y < anchor.y
        var width = max(1, abs(point.x - anchor.x)), height = max(1, abs(point.y - anchor.y))
        if let ratio {
            if width / height > ratio { height = width / ratio } else { width = height * ratio }
        }
        let maxWidth = left ? anchor.x - bounds.minX : bounds.maxX - anchor.x
        let maxHeight = top ? anchor.y - bounds.minY : bounds.maxY - anchor.y
        let scale = min(1, maxWidth / width, maxHeight / height)
        width *= scale; height *= scale
        return CGRect(x: left ? anchor.x - width : anchor.x, y: top ? anchor.y - height : anchor.y, width: width, height: height)
    }
}

struct CropCorner: View {
    let left: Bool
    let top: Bool
    var body: some View {
        Path { path in
            let dx: CGFloat = left ? 1 : -1, dy: CGFloat = top ? 1 : -1
            path.move(to: CGPoint(x: 12, y: 12 + dy * 10))
            path.addLine(to: CGPoint(x: 12, y: 12))
            path.addLine(to: CGPoint(x: 12 + dx * 10, y: 12))
        }.stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .square))
    }
}
