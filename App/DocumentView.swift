import SwiftUI
import WebKit
import MarkdownRenderer

struct DocumentView: View {
    @State private var viewer: Viewer

    init(initialText: String, fileURL: URL?) {
        _viewer = State(initialValue: Viewer(text: initialText, fileURL: fileURL))
    }

    var body: some View {
        MarkdownWebView(viewer: viewer)
            .ignoresSafeArea(.container, edges: .top)
            .focusedSceneValue(\.viewer, viewer)
            .onAppear { viewer.startWatching() }
            .onDisappear { viewer.stopWatching() }
    }
}

/// Holds one window's state: the current markdown, the web view, and the file watcher.
@Observable
final class Viewer {
    private(set) var html: String
    private(set) var zoom: Double = UserDefaults.standard.object(forKey: "zoom") as? Double ?? 1

    let fileURL: URL?
    weak var webView: WKWebViewWithScroll?
    private var watcher: FileWatcher?

    init(text: String, fileURL: URL?) {
        self.fileURL = fileURL
        self.html = Viewer.render(text, fileURL: fileURL)
    }

    static func render(_ text: String, fileURL: URL?) -> String {
        MarkdownRenderer.renderPage(
            markdown: text,
            title: fileURL?.lastPathComponent ?? "Markdown",
            baseURL: fileURL?.deletingLastPathComponent()
        )
    }

    func startWatching() {
        guard let fileURL, watcher == nil else { return }
        watcher = FileWatcher(url: fileURL) { [weak self] in self?.reload() }
    }

    func stopWatching() {
        watcher = nil
    }

    func reload() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        let newHTML = Viewer.render(MarkdownFile.decode(data), fileURL: fileURL)
        if newHTML != html { html = newHTML }
    }

    func setZoom(_ value: Double) {
        zoom = min(max(value, 0.5), 3)
        UserDefaults.standard.set(zoom, forKey: "zoom")
    }

    func print() {
        guard let webView, let window = webView.window else { return }
        let info = NSPrintInfo.shared
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        let operation = webView.printOperation(with: info)
        operation.view?.frame = webView.bounds
        operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }
}

extension FocusedValues {
    @Entry var viewer: Viewer?
}
