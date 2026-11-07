import SwiftUI

@main
struct TLDRApp: App {
    var body: some Scene {
        DocumentGroup(viewing: MarkdownFile.self) { file in
            DocumentView(initialText: file.document.text, fileURL: file.fileURL)
                .frame(minWidth: 480, minHeight: 360)
        }
        .defaultSize(width: 900, height: 1000)
        .commands {
            ViewerCommands()
        }
    }
}

struct ViewerCommands: Commands {
    @FocusedValue(\.viewer) private var viewer

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button("Actual Size") { viewer?.setZoom(1) }
                .keyboardShortcut("0")
            Button("Zoom In") { viewer?.setZoom((viewer?.zoom ?? 1) + 0.1) }
                .keyboardShortcut("+")
            Button("Zoom Out") { viewer?.setZoom((viewer?.zoom ?? 1) - 0.1) }
                .keyboardShortcut("-")
            Divider()
            Button("Reload") { viewer?.reload() }
                .keyboardShortcut("r")
        }
        CommandGroup(replacing: .printItem) {
            Button("Print…") { viewer?.print() }
                .keyboardShortcut("p")
                .disabled(viewer == nil)
        }
    }
}
