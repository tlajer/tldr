import SwiftUI
import WebKit
import MarkdownRenderer

final class WKWebViewWithScroll: WKWebView {
    /// Scroll offset captured before a reload, restored once the new page has loaded.
    var pendingScrollY: Double?
}

struct MarkdownWebView: NSViewRepresentable {
    let viewer: Viewer

    func makeCoordinator() -> Coordinator {
        Coordinator(viewer: viewer)
    }

    func makeNSView(context: Context) -> WKWebViewWithScroll {
        let config = PreviewWebKit.makeConfiguration()
        config.preferences.isElementFullscreenEnabled = false
        let webView = WKWebViewWithScroll(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = true
        viewer.webView = webView
        return webView
    }

    func updateNSView(_ webView: WKWebViewWithScroll, context: Context) {
        webView.pageZoom = viewer.zoom
        let coordinator = context.coordinator
        guard coordinator.loadedHTML != viewer.html else { return }
        let isFirstLoad = coordinator.loadedHTML == nil
        coordinator.loadedHTML = viewer.html
        let html = viewer.html
        let baseURL = viewer.fileURL?.deletingLastPathComponent()
        if isFirstLoad {
            webView.loadHTMLString(html, baseURL: baseURL)
        } else {
            webView.evaluateJavaScript("window.scrollY") { y, _ in
                webView.pendingScrollY = y as? Double
                webView.loadHTMLString(html, baseURL: baseURL)
            }
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let viewer: Viewer
        var loadedHTML: String?

        init(viewer: Viewer) {
            self.viewer = viewer
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let webView = webView as? WKWebViewWithScroll, let y = webView.pendingScrollY else { return }
            webView.pendingScrollY = nil
            // Mermaid diagrams render after load and change the page height; wait for them.
            webView.callAsyncJavaScript(
                "await window.tldrReady; window.scrollTo(0, y)", arguments: ["y": y],
                in: nil, in: .page, completionHandler: nil)
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard action.navigationType == .linkActivated, let url = action.request.url else { return .allow }

            // In-page anchors: scroll ourselves rather than navigating away from the rendered HTML.
            if let fragment = url.fragment, isSameDocument(url) {
                let id = fragment.removingPercentEncoding ?? fragment
                let js = "document.getElementById(\(jsString(id)))?.scrollIntoView({behavior: 'smooth'})"
                _ = try? await webView.evaluateJavaScript(js)
                return .cancel
            }

            if url.isFileURL, ["md", "markdown", "mdown", "mkd", "mkdn", "mdwn"].contains(url.pathExtension.lowercased()) {
                NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
            } else {
                NSWorkspace.shared.open(url)
            }
            return .cancel
        }

        private func isSameDocument(_ url: URL) -> Bool {
            guard let base = viewer.fileURL?.deletingLastPathComponent() else { return true }
            let path = url.path(percentEncoded: false)
            return path.isEmpty || path == base.path(percentEncoded: false) || path + "/" == base.path(percentEncoded: false)
        }

        private func jsString(_ s: String) -> String {
            let data = try? JSONSerialization.data(withJSONObject: [s])
            let array = data.flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
            return "\(array)[0]"
        }
    }
}
