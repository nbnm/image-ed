import SwiftUI

struct InspectorView: View {
    @ObservedObject var model: EditorModel
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    switch model.tool {
                    case .text: TextInspector(model: model)
                    case .image: ImageInspector(model: model)
                    case .crop: CropInspector(model: model)
                    case .resize: ResizeInspector(model: model)
                    case .color: ColorInspector(model: model)
                    }
                }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 7) {
                    Image(systemName: model.asset?.svg == nil ? "photo" : "square.stack.3d.up")
                        .font(.system(size: 11)).foregroundStyle(Theme.accent)
                    Text(model.asset?.svg == nil ? "Original image" : "Vector original")
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                }
                Text("\(model.asset?.width ?? 0) × \(model.asset?.height ?? 0) px · \(model.asset?.format ?? "")")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.secondary)
                Text("Your original file stays untouched.").font(.system(size: 10)).foregroundStyle(Theme.secondary)
            }
            .padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
        }.background(Theme.paper)
    }
}

struct TextInspector: View {
    @ObservedObject var model: EditorModel
    @FocusState private var textFocused: Bool
    var body: some View {
        InspectorHeading(title: "Add text", detail: "Place a label or note on your image.")
        Button(action: model.addText) {
            HStack { Image(systemName: "plus"); Text("Add text"); Spacer(); Text("⇧⌘T").foregroundStyle(Theme.secondary) }
                .frame(maxWidth: .infinity)
        }.buttonStyle(QuietButtonStyle())
        if let layer = model.currentText {
            VStack(alignment: .leading, spacing: 8) {
                FieldLabel(title: "Text")
                TextEditor(text: Binding(get: { model.currentText?.text ?? "" }, set: { value in model.updateText { $0.text = value } }))
                    .font(.system(size: 13)).scrollContentBackground(.hidden).padding(7)
                    .frame(height: 86).background(.white, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.line))
                    .focused($textFocused)
                    .accessibilityLabel("Text content")
            }
            VStack(alignment: .leading, spacing: 8) {
                FieldLabel(title: "Typeface")
                HStack(spacing: 8) {
                    Picker("Typeface", selection: Binding(get: { layer.fontName }, set: { value in model.updateText { $0.fontName = value } })) {
                        Text("System").tag("System")
                        Text("Helvetica Neue").tag("Helvetica Neue")
                        Text("Georgia").tag("Georgia")
                        Text("Menlo").tag("Menlo")
                    }.labelsHidden().controlSize(.large)
                    Button { model.updateText { $0.bold.toggle() } } label: {
                        Image(systemName: "bold").font(.system(size: 12, weight: .semibold)).frame(width: 31, height: 29)
                            .background(layer.bold ? Theme.mint : Color.white, in: RoundedRectangle(cornerRadius: 5))
                            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.line))
                    }.buttonStyle(.plain).help("Bold text").accessibilityLabel("Bold text")
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    FieldLabel(title: "Size")
                    Spacer()
                    Text("\(Int(layer.fontSize)) px").font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.secondary)
                }
                Slider(value: Binding(get: { Double(model.currentText?.fontSize ?? 48) }, set: { value in model.updateText { $0.fontSize = value } }),
                       in: 8...max(240, layer.fontSize), step: 1,
                       onEditingChanged: { editing in editing ? model.beginTransaction("Change text size") : model.endTransaction() })
                    .tint(Theme.accent).accessibilityLabel("Text size")
            }
            VStack(alignment: .leading, spacing: 9) {
                FieldLabel(title: "Background")
                HStack(spacing: 6) {
                    backgroundButton("White box", white: true, selected: layer.whiteBox)
                    backgroundButton("Transparent", white: false, selected: !layer.whiteBox)
                }
            }
            HStack {
                FieldLabel(title: "Text color")
                Spacer()
                ColorPicker("Text color", selection: Binding(get: { Color(nsColor: NSColor(hex: layer.color)) }, set: { value in
                    model.updateText { $0.color = NSColor(value).hex }
                }), supportsOpacity: false).labelsHidden()
            }
            Divider().overlay(Theme.line)
            HStack {
                Text("Drag text to position it.").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                Spacer()
                IconButton(symbol: "trash", help: "Delete selected text", action: model.removeText)
            }
        } else {
            VStack(alignment: .leading, spacing: 9) {
                Image(systemName: "text.cursor").font(.system(size: 27, weight: .ultraLight)).foregroundStyle(Theme.secondary.opacity(0.6))
                Text(model.state?.texts.isEmpty == true ? "No text yet" : "No text selected").font(.system(size: 12, weight: .medium))
                Text("Add text, then drag it anywhere on your image.")
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary).lineSpacing(3)
            }.padding(.top, 30)
        }
        if let texts = model.state?.texts, texts.count > 1 {
            VStack(alignment: .leading, spacing: 9) {
                FieldLabel(title: "Text layers")
                ForEach(texts.reversed()) { layer in
                    Button { model.selectedText = layer.id } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "textformat").font(.system(size: 11))
                            Text(layer.text.isEmpty ? "Empty text" : layer.text).lineLimit(1)
                            Spacer()
                            if model.selectedText == layer.id { Image(systemName: "checkmark").font(.system(size: 10)) }
                        }
                        .font(.system(size: 11)).padding(9)
                        .background(model.selectedText == layer.id ? Theme.mint : .clear, in: RoundedRectangle(cornerRadius: 5))
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func backgroundButton(_ title: String, white: Bool, selected: Bool) -> some View {
        Button { model.updateText { $0.whiteBox = white } } label: {
            VStack(spacing: 7) {
                ZStack {
                    if white { Color.white } else { Checkerboard() }
                    Text("Aa").font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.ink)
                }
                .frame(height: 37).clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(selected ? Theme.accent : Theme.line, lineWidth: selected ? 1.5 : 1))
                Text(title).font(.system(size: 10)).foregroundStyle(selected ? Theme.ink : Theme.secondary)
            }.frame(maxWidth: .infinity)
        }.buttonStyle(.plain)
    }
}

struct CropInspector: View {
    @ObservedObject var model: EditorModel
    var body: some View {
        InspectorHeading(title: "Crop image", detail: "Choose the area you want to keep.")
        VStack(alignment: .leading, spacing: 10) {
            FieldLabel(title: "Aspect ratio")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 7) {
                ForEach(CropRatio.allCases) { ratio in
                    Button { model.setCropRatio(ratio) } label: {
                        Text(ratio.rawValue).font(.system(size: 11, weight: .medium))
                            .frame(maxWidth: .infinity).frame(height: 31)
                            .background(model.cropRatio == ratio ? Theme.mint : Color.white, in: RoundedRectangle(cornerRadius: 5))
                            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(model.cropRatio == ratio ? Theme.accent.opacity(0.5) : Theme.line))
                    }.buttonStyle(.plain)
                }
            }
        }
        VStack(alignment: .leading, spacing: 10) {
            FieldLabel(title: "Selection")
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(selectionWidth) × \(selectionHeight)").font(.system(size: 20, weight: .medium, design: .monospaced)).tracking(-0.8)
                Text("px").font(.system(size: 11)).foregroundStyle(Theme.secondary)
            }
        }.padding(.top, 3)
        VStack(spacing: 9) {
            Button(action: model.applyCrop) { Text("Apply crop").frame(maxWidth: .infinity) }
                .buttonStyle(PrimaryButtonStyle()).disabled(model.cropSelection.width < 1 || model.cropSelection.height < 1 || model.cropSelection == model.state?.crop)
            Button {
                if let state = model.state { model.cropSelection = state.crop; model.cropRatio = .free }
            } label: { Text("Reset selection").frame(maxWidth: .infinity) }
                .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.secondary).padding(.top, 4)
        }
        Text("Drag the corners to adjust your crop. Drag inside the frame to move it.")
            .font(.system(size: 11)).foregroundStyle(Theme.secondary).lineSpacing(4)
    }
    private var selectionWidth: Int {
        guard let state = model.state else { return 0 }
        return Int((model.cropSelection.width / state.crop.width * CGFloat(state.width)).rounded())
    }
    private var selectionHeight: Int {
        guard let state = model.state else { return 0 }
        return Int((model.cropSelection.height / state.crop.height * CGFloat(state.height)).rounded())
    }
}

struct ResizeInspector: View {
    @ObservedObject var model: EditorModel
    @State private var width = 1
    @State private var height = 1
    @State private var locked = true
    var body: some View {
        InspectorHeading(title: "Resize image", detail: "Set the dimensions for your image.")
        HStack(alignment: .bottom, spacing: 8) {
            dimensionField("Width", value: Binding(get: { width }, set: { value in
                width = value
                if locked { height = max(1, Int((Double(value) / ratio).rounded())) }
            }))
            Image(systemName: "multiply").font(.system(size: 9)).foregroundStyle(Theme.secondary).frame(height: 34)
            dimensionField("Height", value: Binding(get: { height }, set: { value in
                height = value
                if locked { width = max(1, Int((Double(value) * ratio).rounded())) }
            }))
        }
        Toggle(isOn: $locked) {
            Label("Keep proportions", systemImage: locked ? "lock" : "lock.open")
                .font(.system(size: 11)).foregroundStyle(Theme.secondary)
        }.toggleStyle(.checkbox).tint(Theme.accent)
        VStack(alignment: .leading, spacing: 10) {
            FieldLabel(title: "Quick scale")
            HStack(spacing: 6) {
                ForEach([50, 100, 200], id: \.self) { percentage in
                    Button {
                        guard let state = model.state else { return }
                        width = max(1, state.width * percentage / 100)
                        height = max(1, state.height * percentage / 100)
                    } label: {
                        Text("\(percentage)%").frame(maxWidth: .infinity)
                    }.buttonStyle(QuietButtonStyle())
                }
            }
        }
        Button { model.resize(width: width, height: height) } label: { Text("Apply size").frame(maxWidth: .infinity) }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(width < 1 || height < 1 || (width == model.state?.width && height == model.state?.height))
        if model.asset?.svg != nil {
            Label { Text("SVG artwork stays sharp at any size.").lineSpacing(4) } icon: { Image(systemName: "square.stack.3d.up").font(.system(size: 12)) }
                .font(.system(size: 11)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
        } else if width > (model.asset?.width ?? width) {
            Text("Enlarging a raster image may make it look softer.").font(.system(size: 11)).foregroundStyle(Theme.secondary).lineSpacing(4)
        }
        Text("Current size: \(model.state?.width ?? 0) × \(model.state?.height ?? 0) px")
            .font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.secondary)
            .onAppear(perform: sync)
            .onChange(of: model.state?.width) { _, _ in sync() }
            .onChange(of: model.state?.height) { _, _ in sync() }
    }
    private var ratio: Double { Double(model.state?.width ?? 1) / Double(model.state?.height ?? 1) }
    private func sync() { width = model.state?.width ?? 1; height = model.state?.height ?? 1 }
    private func dimensionField(_ title: String, value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(title: title)
            HStack(spacing: 3) {
                TextField(title, value: value, format: .number.grouping(.never)).textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced)).accessibilityLabel("\(title) in pixels")
                Text("px").font(.system(size: 10)).foregroundStyle(Theme.secondary)
            }.padding(.horizontal, 10).frame(height: 36)
                .background(.white, in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.line))
        }
    }
}

struct ColorInspector: View {
    @ObservedObject var model: EditorModel
    var body: some View {
        InspectorHeading(title: "Adjust color", detail: "Choose a filter or adjust the colors.")
        VStack(alignment: .leading, spacing: 10) {
            FieldLabel(title: "Filters")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 9), GridItem(.flexible(), spacing: 9)], spacing: 14) {
                ForEach(ColorPreset.allCases) { preset in
                    Button { model.commit("Change filter") { $0.preset = preset } } label: {
                        VStack(spacing: 7) {
                            ZStack(alignment: .bottomTrailing) {
                                if let image = model.thumbnails[preset] {
                                    Image(nsImage: image).resizable().scaledToFill().frame(height: 68).clipped()
                                } else { Theme.canvas.frame(height: 68) }
                                if model.state?.preset == preset {
                                    Image(systemName: "checkmark.circle.fill").font(.system(size: 13)).foregroundStyle(.white, Theme.accent)
                                        .padding(5)
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(model.state?.preset == preset ? Theme.accent : Theme.line,
                                                                                   lineWidth: model.state?.preset == preset ? 2 : 1))
                            Text(preset.rawValue).font(.system(size: 10, weight: model.state?.preset == preset ? .semibold : .regular))
                                .foregroundStyle(model.state?.preset == preset ? Theme.ink : Theme.secondary)
                        }
                    }.buttonStyle(.plain).accessibilityLabel("\(preset.rawValue) filter")
                }
            }
        }
        Divider().overlay(Theme.line)
        VStack(spacing: 20) {
            adjustment("Brightness", keyPath: \.brightness, range: -0.5...0.5, neutral: 0)
            adjustment("Contrast", keyPath: \.contrast, range: 0.5...1.5, neutral: 1)
            adjustment("Saturation", keyPath: \.saturation, range: 0...2, neutral: 1)
        }
        Button("Reset color", action: model.resetColors).buttonStyle(.plain)
            .font(.system(size: 11)).foregroundStyle(Theme.secondary)
    }

    private func adjustment(_ title: String, keyPath: WritableKeyPath<EditState, Double>, range: ClosedRange<Double>, neutral: Double) -> some View {
        VStack(spacing: 8) {
            HStack {
                FieldLabel(title: title)
                Spacer()
                let value = Int((((model.state?[keyPath: keyPath] ?? neutral) - neutral) * 100).rounded())
                Text(value > 0 ? "+\(value)" : "\(value)").font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.secondary)
            }
            Slider(value: Binding(get: { model.state?[keyPath: keyPath] ?? neutral }, set: { value in
                model.commit("Adjust \(title.lowercased())") { $0[keyPath: keyPath] = value }
            }), in: range, onEditingChanged: { editing in editing ? model.beginTransaction("Adjust \(title.lowercased())") : model.endTransaction() })
                .tint(Theme.accent).accessibilityLabel(title)
        }
    }
}
