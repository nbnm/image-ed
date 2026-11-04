import SwiftUI
import UniformTypeIdentifiers

struct EditorView: View {
    @ObservedObject var model: EditorModel
    @State private var dropTargeted = false
    @State private var resetConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.line).frame(height: 1)
            if model.asset != nil {
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        toolBar
                        CanvasView(model: model)
                    }
                    Rectangle().fill(Theme.line).frame(width: 1)
                    InspectorView(model: model).frame(width: 272)
                }
            } else {
                WelcomeView(model: model)
            }
        }
        .background(Theme.paper)
        .foregroundStyle(Theme.ink)
        .font(.system(size: 13))
        .frame(minWidth: 980, minHeight: 660)
        .ignoresSafeArea(.container, edges: .top)
        .preferredColorScheme(.light)
        .background(WindowSetup(model: model).frame(width: 0, height: 0))
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.accent, lineWidth: 3).padding(5)
                    .background(Theme.mint.opacity(0.5)).allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted, perform: model.acceptDrop)
        .overlay {
            if model.isLoading {
                ZStack {
                    Theme.paper.opacity(0.85)
                    VStack(spacing: 14) {
                        ProgressView().controlSize(.small)
                        Text("Preparing your image…").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    }
                }.transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            if let notice = model.notice {
                HStack(spacing: 9) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                    Text(notice).lineLimit(1)
                    if let url = model.lastExportURL, notice.hasPrefix("Exported") {
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                            .buttonStyle(.plain).foregroundStyle(Theme.accent).fontWeight(.semibold)
                    }
                }
                .font(.system(size: 12)).padding(.horizontal, 15).padding(.vertical, 12)
                .background(Theme.paper, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.line))
                .shadow(color: Theme.ink.opacity(0.08), radius: 12, y: 4)
                .padding(.bottom, 60)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.notice)
        .sheet(isPresented: $model.showExport) { ExportView(model: model) }
        .alert("Image error", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
        .confirmationDialog("Reset all edits?", isPresented: $resetConfirmation) {
            Button("Reset all edits", role: .destructive, action: model.resetAll)
        } message: { Text("Your original image will be restored. You can undo this.") }
    }

    private var header: some View {
        HStack(spacing: 12) {
            EddieMark(size: 27).accessibilityHidden(true)
            Text("Image-Eddie").font(.system(size: 17, weight: .semibold)).tracking(-0.5)
            Text("/").foregroundStyle(Theme.line)
            Text("Image editor").font(.system(size: 12)).foregroundStyle(Theme.secondary)
            Spacer()
            if let asset = model.asset {
                HStack(spacing: 7) {
                    Image(systemName: "photo").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    Text(asset.name).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                    if model.isDirty { Circle().fill(Theme.accent).frame(width: 5, height: 5).help("Edits haven’t been exported") }
                }.frame(maxWidth: 260)
                Spacer()
            }
            IconButton(symbol: "folder", help: "Open image · ⌘O", action: model.openPanel)
            Rectangle().fill(Theme.line).frame(width: 1, height: 19).padding(.horizontal, 3)
            HStack(spacing: 2) {
                IconButton(symbol: "arrow.uturn.backward", help: "Undo · ⌘Z", enabled: model.canUndo, action: model.undo)
                IconButton(symbol: "arrow.uturn.forward", help: "Redo · ⇧⌘Z", enabled: model.canRedo, action: model.redo)
            }
            Button { model.showExport = true } label: {
                HStack(spacing: 7) { Text("Export"); Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .semibold)) }
            }
            .buttonStyle(PrimaryButtonStyle(compact: true)).disabled(model.asset == nil)
            .help("Export image · ⇧⌘E")
        }
        .padding(.leading, 86).padding(.trailing, 20).frame(height: 58)
    }

    private var toolBar: some View {
        HStack {
            Text("TOOLS").font(.system(size: 9, weight: .semibold)).tracking(1.4).foregroundStyle(Theme.secondary)
            Spacer()
            HStack(spacing: 3) {
                ForEach(EditorTool.allCases) { tool in
                    Button { withAnimation(.easeOut(duration: 0.15)) { model.selectTool(tool) } } label: {
                        HStack(spacing: 7) {
                            Image(systemName: tool.symbol).font(.system(size: 13))
                            Text(tool.rawValue).font(.system(size: 12, weight: model.tool == tool ? .semibold : .medium))
                        }
                        .foregroundStyle(model.tool == tool ? Theme.ink : Theme.secondary)
                        .padding(.horizontal, 15).frame(height: 32)
                        .background(model.tool == tool ? Theme.mint : .clear, in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("\(tool.rawValue) tool")
                }
            }
            Spacer()
            IconButton(symbol: "arrow.counterclockwise", help: "Reset all edits", enabled: model.hasEdits) { resetConfirmation = true }
        }
        .padding(.horizontal, 22).frame(height: 57)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }
}

struct WelcomeView: View {
    @ObservedObject var model: EditorModel
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 22) {
                EddieMark(size: 82).padding(.bottom, 3)
                VStack(spacing: 10) {
                    Text("Open an image").font(.system(size: 29, weight: .semibold)).tracking(-0.9)
                    Text("Drop a PNG, JPEG, or SVG here to get started.")
                        .font(.system(size: 14)).foregroundStyle(Theme.secondary)
                }
                Button(action: model.openPanel) {
                    HStack(spacing: 20) { Text("Choose an image"); Text("⌘O").foregroundStyle(Color.white.opacity(0.6)).fontWeight(.regular) }
                }.buttonStyle(PrimaryButtonStyle()).padding(.top, 4)
                HStack(spacing: 22) {
                    Label("Text & images", systemImage: "photo.on.rectangle")
                    Label("Crop & resize", systemImage: "crop")
                    Label("Adjust color", systemImage: "slider.horizontal.3")
                }.font(.system(size: 11)).foregroundStyle(Theme.secondary).padding(.top, 8)
            }
            .frame(width: 540, height: 345)
            .background(Color.white.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 1, dash: [5, 5])))
            Button(action: model.openSample) {
                HStack(spacing: 11) {
                    Image(systemName: "mountain.2").font(.system(size: 19, weight: .light)).foregroundStyle(Theme.accent)
                        .frame(width: 44, height: 36).background(Theme.mint, in: RoundedRectangle(cornerRadius: 5))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Just looking around?").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.ink)
                        Text("Try the sample image").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    }
                    Image(systemName: "arrow.right").font(.system(size: 12)).foregroundStyle(Theme.secondary).padding(.leading, 22)
                }.padding(12)
            }.buttonStyle(.plain).padding(.top, 20)
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "lock").font(.system(size: 10))
                Text("Images are processed on your Mac.")
            }.font(.system(size: 11)).foregroundStyle(Theme.secondary).padding(.bottom, 25)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.canvas)
    }
}
