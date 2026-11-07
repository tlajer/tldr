import SwiftUI
import WebKit
import MarkdownRenderer

struct DocumentView: View {
    @State private var viewer: Viewer
    @AppStorage("showPathBar") private var showPathBar = true

    init(initialText: String, fileURL: URL?) {
        _viewer = State(initialValue: Viewer(text: initialText, fileURL: fileURL))
    }

    var body: some View {
        VStack(spacing: 0) {
            if showPathBar, let location = viewer.location {
                PathBar(location: location)
                Divider()
            }
            MarkdownWebView(viewer: viewer)
        }
            .ignoresSafeArea(.container, edges: showPathBar && viewer.location != nil ? [] : .top)
            .focusedSceneValue(\.viewer, viewer)
            .onAppear { viewer.startWatching() }
            .onDisappear { viewer.stopWatching() }
            // Pick up branch switches made in a terminal while the app was in the background.
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                viewer.refreshLocation()
            }
    }
}

/// Holds one window's state: the current markdown, the web view, and the file watcher.
@Observable
final class Viewer {
    private(set) var html: String
    private(set) var location: FileLocation?
    private(set) var zoom: Double = UserDefaults.standard.object(forKey: "zoom") as? Double ?? 1

    let fileURL: URL?
    weak var webView: WKWebViewWithScroll?
    private var watcher: FileWatcher?

    init(text: String, fileURL: URL?) {
        self.fileURL = fileURL
        self.html = Viewer.render(text, fileURL: fileURL)
        self.location = fileURL.map(FileLocation.init)
    }

    func refreshLocation() {
        let newLocation = fileURL.map(FileLocation.init)
        if newLocation != location { location = newLocation }
    }

    static func render(_ text: String, fileURL: URL?) -> String {
        DocumentRenderer.renderPage(
            text: text,
            kind: DocumentKind(fileURL: fileURL),
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
        refreshLocation()
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
