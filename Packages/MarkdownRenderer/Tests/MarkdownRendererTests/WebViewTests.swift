import AppKit
import WebKit
import XCTest
@testable import MarkdownRenderer

/// Loads rendered pages in a real WKWebView. Set SNAPSHOT_DIR to also write PNG snapshots.
@MainActor
final class WebViewTests: XCTestCase {
    private final class LoadWaiter: NSObject, WKNavigationDelegate {
        var done: (() -> Void)?
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { done?() }
    }

    private func load(_ markdown: String, dark: Bool = false) async throws -> WKWebView {
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 1200), configuration: PreviewWebKit.makeConfiguration())
        webView.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let waiter = LoadWaiter()
        webView.navigationDelegate = waiter
        let html = MarkdownRenderer.renderPage(markdown: markdown, title: "test", baseURL: nil)
        await withCheckedContinuation { c in
            waiter.done = { c.resume() }
            webView.loadHTMLString(html, baseURL: nil)
        }
        _ = try await webView.callAsyncJavaScript("await window.tldrReady", contentWorld: .page)
        return webView
    }

    private func snapshot(_ webView: WKWebView, _ name: String) async throws {
        guard let dir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] else { return }
        let image = try await webView.takeSnapshot(configuration: nil)
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
    }

    func testMermaidRendersSVG() async throws {
        let md = """
        # Diagrams

        ```mermaid
        flowchart LR
          A[Markdown] --> B{Mermaid?}
          B -- yes --> C[SVG]
          B -- no --> D[HTML]
        ```

        ```mermaid
        sequenceDiagram
          Finder->>TLDR: space
          TLDR-->>Finder: preview
        ```

        ```mermaid
        this is not valid mermaid
        ```
        """
        for dark in [false, true] {
            let webView = try await load(md, dark: dark)
            let svgs = try await webView.callAsyncJavaScript(
                "return document.querySelectorAll('pre.mermaid svg').length", contentWorld: .page) as? Int
            let failed = try await webView.callAsyncJavaScript(
                "return document.querySelectorAll('pre.mermaid.mermaid-failed').length", contentWorld: .page) as? Int
            let error = try await webView.callAsyncJavaScript(
                "return document.querySelector('pre.mermaid-failed').dataset.error", contentWorld: .page) as? String
            XCTAssertEqual(svgs, 2)
            XCTAssertTrue(error?.isEmpty == false)
            XCTAssertEqual(failed, 1)
            try await snapshot(webView, dark ? "mermaid-dark.png" : "mermaid-light.png")
        }
    }

    func testInlineScriptInMarkdownIsBlocked() async throws {
        let webView = try await load("<script>document.title = 'pwned'</script>\n\n```mermaid\ngraph TD; A-->B\n```")
        let title = try await webView.callAsyncJavaScript("return document.title", contentWorld: .page) as? String
        XCTAssertEqual(title, "test")
    }
}
