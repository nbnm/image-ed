import SwiftUI
import AppKit

@main
struct ImageEddieApp: App {
    @StateObject private var editor = EditorModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Image-Eddie", id: "editor") {
            EditorView(model: editor)
                .onAppear { delegate.editor = editor }
                .onOpenURL { editor.open($0) }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1220, height: 800)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Image…", action: editor.openPanel).keyboardShortcut("o")
                Button("Open Sample", action: editor.openSample)
                Divider()
                Button("Export…") { editor.showExport = true }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(editor.asset == nil)
            }
            CommandGroup(replacing: .undoRedo) {
                Button(editor.undoStack.last.map { "Undo \($0.0)" } ?? "Undo", action: editor.undo)
                    .keyboardShortcut("z").disabled(!editor.canUndo)
                Button(editor.redoStack.last.map { "Redo \($0.0)" } ?? "Redo", action: editor.redo)
                    .keyboardShortcut("z", modifiers: [.command, .shift]).disabled(!editor.canRedo)
            }
            CommandMenu("Image") {
                ForEach(EditorTool.allCases) { tool in
                    Button(tool.rawValue) { editor.selectTool(tool) }.disabled(editor.asset == nil)
                }
                Divider()
                Button("Add Text", action: editor.addText).keyboardShortcut("t", modifiers: [.command, .shift]).disabled(editor.asset == nil)
                Button("Add Image Overlay…", action: editor.addImagesPanel).keyboardShortcut("i", modifiers: [.command, .shift]).disabled(editor.asset == nil)
                Button("Reset All Edits", action: editor.resetAll).disabled(!editor.hasEdits)
            }
            CommandGroup(after: .toolbar) {
                Button("Fit Image") { editor.zoom = 0 }.keyboardShortcut("0")
                Button("Actual Size") { editor.zoom = 1 }.keyboardShortcut("1")
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var editor: EditorModel?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        if let iconURL = Bundle.main.url(forResource: "ImageEddie", withExtension: "icns"), let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        (editor?.confirmDiscard() ?? true) ? .terminateNow : .terminateCancel
    }
}
