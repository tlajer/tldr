import Cocoa
import Quartz
import WebKit
import MarkdownRenderer

/// View-based preview (rather than data-based) so the page can run Mermaid's JavaScript.
final class PreviewViewController: NSViewController, QLPreviewingController, WKNavigationDelegate {
    private var webView: WKWebView!
    private var loaded: CheckedContinuation<Void, Never>?

    override var nibName: NSNib.Name? { nil }

    override func loadView() {
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 1100), configuration: PreviewWebKit.makeConfiguration())
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        view = webView
        preferredContentSize = webView.frame.size
    }

    func preparePreviewOfFile(at url: URL) async throws {
        let data = try Data(contentsOf: url)
        let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        let html = MarkdownRenderer.renderPage(
            markdown: text,
            title: url.lastPathComponent,
            baseURL: url.deletingLastPathComponent()
        )
        _ = view
        await withCheckedContinuation { continuation in
            loaded = continuation
            webView.loadHTMLString(html, baseURL: url.deletingLastPathComponent())
        }
        // Show the preview once diagrams are drawn, so it doesn't jump.
        _ = try? await webView.callAsyncJavaScript("await window.tldrReady", contentWorld: .page)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finishLoading()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finishLoading()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finishLoading()
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard action.navigationType == .linkActivated, let url = action.request.url else { return .allow }
        if let fragment = url.fragment, url.scheme == "file" {
            let id = fragment.removingPercentEncoding ?? fragment
            _ = try? await webView.callAsyncJavaScript(
                "document.getElementById(id)?.scrollIntoView({behavior: 'smooth'})",
                arguments: ["id": id], contentWorld: .page)
        } else {
            NSWorkspace.shared.open(url)
        }
        return .cancel
    }

    private func finishLoading() {
        loaded?.resume()
        loaded = nil
    }
}
