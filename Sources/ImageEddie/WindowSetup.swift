import AppKit
import SwiftUI

struct WindowSetup: NSViewRepresentable {
    @ObservedObject var model: EditorModel
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window else { return }
            window.titlebarAppearsTransparent = true
            window.backgroundColor = NSColor(hex: "F7F8F5")
            window.tabbingMode = .disallowed
            context.coordinator.previous = window.delegate
            window.delegate = context.coordinator
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.window?.isDocumentEdited = model.isDirty
        nsView.window?.representedURL = model.asset?.fileURL
    }
    func makeCoordinator() -> CloseGuard { CloseGuard(model: model) }

    final class CloseGuard: NSObject, NSWindowDelegate {
        let model: EditorModel
        weak var previous: NSWindowDelegate?
        init(model: EditorModel) { self.model = model }
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            guard model.confirmDiscard() else { return false }
            // Closing was already confirmed; avoid a second application termination prompt.
            if model.isDirty { model.markDiscarded() }
            return previous?.windowShouldClose?(sender) ?? true
        }
        override func responds(to aSelector: Selector!) -> Bool { super.responds(to: aSelector) || (previous?.responds(to: aSelector) ?? false) }
        override func forwardingTarget(for aSelector: Selector!) -> Any? { previous }
    }
}
