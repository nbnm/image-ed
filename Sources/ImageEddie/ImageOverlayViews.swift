import SwiftUI

struct ImageInspector: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        InspectorHeading(title: "Add images", detail: "Place an image over your main image.")
        Button(action: model.addImagesPanel) {
            HStack { Image(systemName: "plus"); Text("Add image"); Spacer(); Text("⇧⌘I").foregroundStyle(Theme.secondary) }
                .frame(maxWidth: .infinity)
        }.buttonStyle(QuietButtonStyle())
        if let layer = model.currentImage, let state = model.state {
            HStack(spacing: 10) {
                ImageLayerThumbnail(layer: layer).frame(width: 43, height: 43)
                VStack(alignment: .leading, spacing: 5) {
                    Text(layer.asset.name).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                    Text("\(layer.asset.format) · \(layer.asset.width) × \(layer.asset.height) px")
                        .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                }
            }
            VStack(spacing: 9) {
                HStack {
                    FieldLabel(title: "Size")
                    Spacer()
                    let width = Int((layer.rect.width / state.crop.width * CGFloat(state.width)).rounded())
                    let height = Int((layer.rect.height / state.crop.height * CGFloat(state.height)).rounded())
                    Text("\(width) × \(height) px").font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.secondary)
                }
                let percentage = Double(layer.rect.width / state.crop.width * 100)
                Slider(value: Binding(get: { Double((model.currentImage?.rect.width ?? 1) / state.crop.width * 100) }, set: {
                    model.setImageWidth(state.crop.width * CGFloat($0) / 100)
                }), in: min(0.1, percentage)...max(200, percentage), onEditingChanged: { editing in
                    editing ? model.beginTransaction("Resize image overlay") : model.endTransaction()
                }).tint(Theme.accent).accessibilityLabel("Overlay size")
            }
            VStack(spacing: 9) {
                HStack {
                    FieldLabel(title: "Opacity")
                    Spacer()
                    Text("\(Int((layer.opacity * 100).rounded()))%")
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.secondary)
                }
                Slider(value: Binding(get: { model.currentImage?.opacity ?? 1 }, set: { value in
                    model.updateImage("Change overlay opacity") { $0.opacity = value }
                }), in: 0...1, onEditingChanged: { editing in
                    editing ? model.beginTransaction("Change overlay opacity") : model.endTransaction()
                }).tint(Theme.accent).accessibilityLabel("Overlay opacity")
            }
            HStack {
                FieldLabel(title: "Layer order")
                Spacer()
                IconButton(symbol: "arrow.down", help: "Move image backward", enabled: model.canMoveImageBackward) { model.moveImage(forward: false) }
                IconButton(symbol: "arrow.up", help: "Move image forward", enabled: model.canMoveImageForward) { model.moveImage(forward: true) }
                IconButton(symbol: "trash", help: "Delete image overlay", action: model.removeImage)
            }
            Text("Drag the image to move it. Drag a corner to resize it. Proportions stay linked.")
                .font(.system(size: 11)).foregroundStyle(Theme.secondary).lineSpacing(4)
        } else {
            VStack(alignment: .leading, spacing: 9) {
                Image(systemName: "photo.on.rectangle").font(.system(size: 27, weight: .ultraLight))
                    .foregroundStyle(Theme.secondary.opacity(0.6))
                Text(model.state?.images.isEmpty == true ? "No image overlays yet" : "No image selected")
                    .font(.system(size: 12, weight: .medium))
                Text("Add or drop a PNG, JPEG, or SVG, then drag it into place.")
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary).lineSpacing(3)
            }.padding(.top, 20)
        }
        if let layers = model.state?.images, !layers.isEmpty {
            Divider().overlay(Theme.line)
            VStack(alignment: .leading, spacing: 9) {
                FieldLabel(title: "Image layers")
                ForEach(layers.reversed()) { layer in
                    Button { model.selectedImage = layer.id } label: {
                        HStack(spacing: 8) {
                            ImageLayerThumbnail(layer: layer).frame(width: 27, height: 27)
                            Text(layer.asset.name).font(.system(size: 11)).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 4)
                            if model.selectedImage == layer.id { Image(systemName: "checkmark").font(.system(size: 10)) }
                        }
                        .padding(7).background(model.selectedImage == layer.id ? Theme.mint : .clear, in: RoundedRectangle(cornerRadius: 5))
                    }.buttonStyle(.plain).accessibilityLabel("Select overlay \(layer.asset.name)")
                }
                Text("Images sit above the original and below text.")
                    .font(.system(size: 10)).foregroundStyle(Theme.secondary).lineSpacing(3)
            }
        }
    }
}

private struct ImageLayerThumbnail: View {
    let layer: ImageLayer
    var body: some View {
        ZStack {
            Checkerboard()
            Image(nsImage: NSImage(cgImage: layer.asset.image, size: .zero)).resizable().scaledToFit()
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.line))
        .accessibilityHidden(true)
    }
}

struct ImageSelection: View {
    @ObservedObject var model: EditorModel
    let layer: ImageLayer
    let displaySize: CGSize
    @State private var moveStart: CGRect?
    @State private var resizeStart: CGRect?

    var body: some View {
        if let state = model.state {
            let sx = displaySize.width / state.crop.width
            let sy = displaySize.height / state.crop.height
            let rect = CGRect(x: (layer.rect.minX - state.crop.minX) * sx, y: (layer.rect.minY - state.crop.minY) * sy,
                              width: layer.rect.width * sx, height: layer.rect.height * sy)
            let selected = model.selectedImage == layer.id
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Color.white.opacity(0.001))
                    .overlay {
                        if selected { Rectangle().strokeBorder(Theme.accent, lineWidth: 1) }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { model.selectedImage = layer.id }
                    .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .named("image-canvas")).onChanged { value in
                        if moveStart == nil {
                            moveStart = layer.rect
                            model.selectedImage = layer.id
                            model.beginTransaction("Move image overlay")
                        }
                        guard let start = moveStart else { return }
                        // Keep a small part visible while allowing overlays to cross an edge.
                        let visibleX = min(start.width, 12 / sx), visibleY = min(start.height, 12 / sy)
                        let x = min(max(start.minX + value.translation.width / sx, state.crop.minX - start.width + visibleX), state.crop.maxX - visibleX)
                        let y = min(max(start.minY + value.translation.height / sy, state.crop.minY - start.height + visibleY), state.crop.maxY - visibleY)
                        model.updateImage("Move image overlay") { $0.rect.origin = CGPoint(x: x, y: y) }
                    }.onEnded { _ in moveStart = nil; model.endTransaction() })
                if selected {
                    ForEach(0..<4) { corner in
                        let left = corner % 2 == 0, top = corner < 2
                        ZStack {
                            Rectangle().fill(Color.white.opacity(0.001))
                            Rectangle().fill(.white).frame(width: 7, height: 7)
                                .overlay(Rectangle().strokeBorder(Theme.accent, lineWidth: 1))
                        }
                        .frame(width: 24, height: 24).contentShape(Rectangle())
                        .position(x: left ? 0 : rect.width, y: top ? 0 : rect.height)
                        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("image-canvas")).onChanged { value in
                            if resizeStart == nil { resizeStart = layer.rect; model.beginTransaction("Resize image overlay") }
                            guard let start = resizeStart else { return }
                            let anchor = CGPoint(x: left ? start.maxX : start.minX, y: top ? start.maxY : start.minY)
                            let dx = value.translation.width / sx * (left ? -1 : 1)
                            let dy = value.translation.height / sy * (top ? -1 : 1)
                            let ratio = start.width / start.height
                            let width = min(max(state.crop.width * 4, start.width), max(1, start.width + dx, (start.height + dy) * ratio))
                            let height = width / ratio
                            let updated = CGRect(x: left ? anchor.x - width : anchor.x, y: top ? anchor.y - height : anchor.y,
                                                 width: width, height: height)
                            model.updateImage("Resize image overlay") { $0.rect = updated }
                        }.onEnded { _ in resizeStart = nil; model.endTransaction() })
                        .accessibilityLabel("Resize image overlay")
                    }
                }
            }
            .frame(width: max(1, rect.width), height: max(1, rect.height))
            .position(x: rect.midX, y: rect.midY)
            .help("Drag to move. Drag a corner to resize.")
            .accessibilityLabel("Image overlay: \(layer.asset.name)")
        }
    }
}
