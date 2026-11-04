import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class EditorModel: ObservableObject {
    @Published private(set) var asset: ImageAsset?
    @Published private(set) var state: EditState?
    @Published private(set) var preview: NSImage?
    @Published private(set) var thumbnails: [ColorPreset: NSImage] = [:]
    @Published var tool: EditorTool = .text
    @Published var selectedText: UUID?
    @Published var selectedImage: UUID?
    @Published var cropRatio: CropRatio = .free
    @Published var cropSelection = CGRect.zero
    @Published var zoom: CGFloat = 0
    @Published var isLoading = false
    @Published var showExport = false
    @Published var error: String?
    @Published var notice: String?
    @Published var lastExportURL: URL?
    @Published private(set) var undoStack: [(String, EditState)] = []
    @Published private(set) var redoStack: [(String, EditState)] = []
    private var transaction: (String, EditState)?
    private var savedState: EditState?
    private var filteredCache: (String, CGImage)?
    private var noticeTask: Task<Void, Never>?

    var isDirty: Bool { state != savedState }
    var hasEdits: Bool {
        guard let asset else { return false }
        return state != EditState(crop: asset.bounds, width: asset.width, height: asset.height)
    }
    var currentText: TextLayer? { state?.texts.first { $0.id == selectedText } }
    var currentImage: ImageLayer? { state?.images.first { $0.id == selectedImage } }
    var canMoveImageForward: Bool { currentImage != nil && state?.images.last?.id != selectedImage }
    var canMoveImageBackward: Bool { currentImage != nil && state?.images.first?.id != selectedImage }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var cropAspect: CGFloat? {
        guard let state else { return nil }
        let outputRatio = CGFloat(state.width) / CGFloat(state.height)
        return cropRatio.value(original: outputRatio).map { $0 * state.crop.width / state.crop.height / outputRatio }
    }

    func markDiscarded() { savedState = state }

    func openPanel() {
        let panel = NSOpenPanel()
        panel.title = "Open image"
        panel.allowedContentTypes = [.png, .jpeg, .svg]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in self?.open(url) }
        }
    }

    func open(_ url: URL) {
        guard confirmDiscard() else { return }
        isLoading = true
        error = nil
        // Yield once so the loading state can paint before decoding a large file.
        Task { @MainActor in
            await Task.yield()
            do {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let asset = try ImageAsset.load(url)
                self.asset = asset
                let initial = EditState(crop: asset.bounds, width: asset.width, height: asset.height)
                state = initial
                savedState = initial
                selectedText = nil
                selectedImage = nil
                undoStack = []; redoStack = []; transaction = nil
                zoom = 0
                cropRatio = .free
                cropSelection = asset.bounds
                filteredCache = nil
                lastExportURL = nil
                refresh()
                makeThumbnails()
                NSDocumentController.shared.noteNewRecentDocumentURL(url)
            } catch { self.error = error.localizedDescription }
            isLoading = false
        }
    }

    func openSample() {
        let bundled = Bundle.main.url(forResource: "Sample", withExtension: "svg")
        let development = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources/Sample.svg")
        open(bundled ?? development)
    }

    func confirmDiscard() -> Bool {
        guard isDirty else { return true }
        let alert = NSAlert()
        alert.messageText = "Keep your edits?"
        alert.informativeText = "Export your image before closing it to keep your changes."
        alert.addButton(withTitle: "Keep editing")
        alert.addButton(withTitle: "Discard changes")
        alert.alertStyle = .warning
        return alert.runModal() == .alertSecondButtonReturn
    }

    func selectTool(_ next: EditorTool) {
        tool = next
        if next == .image, currentImage == nil { selectedImage = state?.images.last?.id }
        if next == .crop, let state { cropSelection = state.crop; cropRatio = .free }
    }

    func commit(_ name: String, _ change: (inout EditState) -> Void) {
        guard var next = state else { return }
        let previous = next
        change(&next)
        guard previous != next else { return }
        if transaction == nil { pushUndo(name, previous); redoStack = [] }
        state = next
        refresh()
    }

    func beginTransaction(_ name: String) {
        guard transaction == nil, let state else { return }
        transaction = (name, state)
    }

    func endTransaction() {
        guard let (name, previous) = transaction else { return }
        if previous != state { pushUndo(name, previous); redoStack = [] }
        transaction = nil
    }

    private func pushUndo(_ name: String, _ previous: EditState) {
        undoStack.append((name, previous))
        if undoStack.count > 60 { undoStack.removeFirst() }
    }

    func undo() {
        endTransaction()
        guard let (name, previous) = undoStack.popLast(), let state else { return }
        redoStack.append((name, state))
        self.state = previous
        reconcileSelection()
        refresh()
    }

    func redo() {
        guard let (name, next) = redoStack.popLast(), let state else { return }
        pushUndo(name, state)
        self.state = next
        reconcileSelection()
        refresh()
    }

    private func reconcileSelection() {
        if !(state?.texts.contains { $0.id == selectedText } ?? false) { selectedText = nil }
        if currentImage == nil { selectedImage = tool == .image ? state?.images.last?.id : nil }
        if let state { cropSelection = state.crop }
    }

    func resetAll() {
        guard let asset else { return }
        commit("Reset image") { $0 = EditState(crop: asset.bounds, width: asset.width, height: asset.height) }
        selectedText = nil
        selectedImage = nil
        cropSelection = asset.bounds
        zoom = 0
    }

    func addText() {
        guard let state else { return }
        var layer = TextLayer(x: state.crop.minX, y: state.crop.minY,
                              fontSize: max(12, min(240, state.crop.width * 0.055)))
        layer.x += max(0, (state.crop.width - layer.rect.width) / 2)
        layer.y += max(0, (state.crop.height - layer.rect.height) / 2)
        commit("Add text") { $0.texts.append(layer) }
        selectedText = layer.id
        selectedImage = nil
        tool = .text
    }

    func updateText(_ change: (inout TextLayer) -> Void) {
        guard let id = selectedText else { return }
        commit("Edit text") { state in
            guard let index = state.texts.firstIndex(where: { $0.id == id }) else { return }
            change(&state.texts[index])
        }
    }

    func removeText() {
        guard let id = selectedText else { return }
        commit("Delete text") { $0.texts.removeAll { $0.id == id } }
        selectedText = nil
    }

    func addImagesPanel() {
        guard asset != nil, !isLoading else { return }
        let panel = NSOpenPanel()
        panel.title = "Add image overlay"
        panel.prompt = "Add image"
        panel.allowedContentTypes = [.png, .jpeg, .svg]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            Task { @MainActor in self?.addImages(from: panel.urls) }
        }
    }

    func addImages(from urls: [URL]) {
        guard let mainImage = asset?.image, !isLoading, !urls.isEmpty else { return }
        isLoading = true
        Task { @MainActor in
            await Task.yield()
            defer { isLoading = false }
            guard self.asset?.image === mainImage else { return }
            do {
                let images = try urls.map { url in
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    return try ImageAsset.load(url)
                }
                addImages(images)
            } catch { self.error = error.localizedDescription }
        }
    }

    func addImages(_ images: [ImageAsset]) {
        guard let state, !images.isEmpty else { return }
        let layers = images.enumerated().map { index, image in
            let scale = min(1, state.crop.width * 0.45 / CGFloat(image.width), state.crop.height * 0.45 / CGFloat(image.height))
            let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
            let offset = CGFloat((state.images.count + index) % 5) * min(state.crop.width, state.crop.height) * 0.025
            let rect = CGRect(x: min(state.crop.maxX - size.width, state.crop.midX - size.width / 2 + offset),
                              y: min(state.crop.maxY - size.height, state.crop.midY - size.height / 2 + offset),
                              width: size.width, height: size.height)
            return ImageLayer(asset: image, rect: rect)
        }
        commit(layers.count == 1 ? "Add image overlay" : "Add image overlays") { $0.images.append(contentsOf: layers) }
        selectedImage = layers.last?.id
        selectedText = nil
        tool = .image
    }

    func updateImage(_ name: String = "Edit image overlay", _ change: (inout ImageLayer) -> Void) {
        guard let id = selectedImage else { return }
        commit(name) { state in
            guard let index = state.images.firstIndex(where: { $0.id == id }) else { return }
            change(&state.images[index])
        }
    }

    func setImageWidth(_ width: CGFloat) {
        guard let layer = currentImage, width.isFinite, width > 0 else { return }
        let height = layer.rect.height * width / layer.rect.width
        updateImage("Resize image overlay") {
            $0.rect = CGRect(x: layer.rect.midX - width / 2, y: layer.rect.midY - height / 2, width: width, height: height)
        }
    }

    func moveImage(forward: Bool) {
        guard let index = state?.images.firstIndex(where: { $0.id == selectedImage }), let count = state?.images.count else { return }
        let target = index + (forward ? 1 : -1)
        guard target >= 0, target < count else { return }
        commit("Reorder image overlay") { $0.images.swapAt(index, target) }
    }

    func removeImage() {
        guard let id = selectedImage else { return }
        commit("Delete image overlay") { $0.images.removeAll { $0.id == id } }
        selectedImage = state?.images.last?.id
    }

    func setCropRatio(_ ratio: CropRatio) {
        cropRatio = ratio
        guard let state, let value = cropAspect else { return }
        let center = CGPoint(x: cropSelection.midX, y: cropSelection.midY)
        var width = cropSelection.width
        var height = width / value
        if height > state.crop.height { height = state.crop.height; width = height * value }
        let x = min(max(center.x - width / 2, state.crop.minX), state.crop.maxX - width)
        let y = min(max(center.y - height / 2, state.crop.minY), state.crop.maxY - height)
        cropSelection = CGRect(x: x, y: y, width: width, height: height)
    }

    func applyCrop() {
        guard let state else { return }
        let selection = cropSelection.intersection(state.crop).integral.intersection(state.crop)
        guard selection.width >= 1, selection.height >= 1 else { return }
        commit("Crop image") {
            $0.width = max(1, Int((CGFloat(state.width) * selection.width / state.crop.width).rounded()))
            $0.height = max(1, Int((CGFloat(state.height) * selection.height / state.crop.height).rounded()))
            $0.crop = selection
        }
        cropSelection = selection
        zoom = 0
        notify("Crop applied")
    }

    func resize(width: Int, height: Int) {
        do {
            try ImageAsset.validateDimensions(width, height)
            commit("Resize image") { $0.width = width; $0.height = height }
            zoom = 0
            notify("Resized to \(width) × \(height) px")
        } catch { self.error = error.localizedDescription }
    }

    func resetColors() {
        commit("Reset color") { $0.preset = .original; $0.brightness = 0; $0.contrast = 1; $0.saturation = 1 }
    }

    func refresh() {
        guard let asset, let state else { return }
        do {
            let key = "\(state.preset)-\(state.brightness)-\(state.contrast)-\(state.saturation)"
            if filteredCache?.0 != key { filteredCache = (key, try ImageRenderer.filtered(asset.image, state: state)) }
            let rendered = try ImageRenderer.render(asset: asset, state: state, maxDimension: 1800, filteredImage: filteredCache?.1)
            preview = NSImage(cgImage: rendered, size: NSSize(width: state.width, height: state.height))
        } catch { self.error = error.localizedDescription }
    }

    private func makeThumbnails() {
        guard let asset else { return }
        var result: [ColorPreset: NSImage] = [:]
        for preset in ColorPreset.allCases {
            let state = EditState(crop: asset.bounds, width: asset.width, height: asset.height, preset: preset)
            if let image = try? ImageRenderer.render(asset: asset, state: state, maxDimension: 180) {
                result[preset] = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            }
        }
        thumbnails = result
    }

    func save(_ settings: ExportSettings) {
        guard let asset, let state else { return }
        let panel = NSSavePanel()
        panel.title = "Export image"
        panel.prompt = "Export"
        panel.allowedContentTypes = [settings.format.contentType]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = (asset.name as NSString).deletingPathExtension + "-edited." + settings.format.fileExtension
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                guard let self else { return }
                self.isLoading = true
                await Task.yield()
                do {
                    let data = try ImageRenderer.export(asset: asset, state: state, settings: settings)
                    try data.write(to: url, options: .atomic)
                    self.savedState = state
                    self.lastExportURL = url
                    self.notify("Exported \(url.lastPathComponent)")
                } catch { self.error = error.localizedDescription }
                self.isLoading = false
            }
        }
    }

    func notify(_ message: String) {
        noticeTask?.cancel()
        notice = message
        noticeTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled { withAnimation { notice = nil } }
        }
    }

    func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        let files = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !files.isEmpty else { return false }
        let addOverlays = asset != nil && tool == .image
        Task { @MainActor in
            var urls: [URL] = []
            for provider in files {
                let url: URL? = await withCheckedContinuation { continuation in
                    provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                        let url = (item as? URL) ?? (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                        continuation.resume(returning: url)
                    }
                }
                if let url { urls.append(url) }
            }
            if addOverlays { addImages(from: urls) }
            else if let first = urls.first { open(first) }
        }
        return true
    }
}
