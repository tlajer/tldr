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
        try await load(html: MarkdownRenderer.renderPage(markdown: markdown, title: "test", baseURL: nil), dark: dark)
    }

    private func load(html: String, dark: Bool = false) async throws -> WKWebView {
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 1200), configuration: PreviewWebKit.makeConfiguration())
        webView.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let waiter = LoadWaiter()
        webView.navigationDelegate = waiter
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

    func testDataTreeCopiesPathsAndFolds() async throws {
        let json = """
        {
          // settings
          "name": "tldr",
          "homepage": "https://github.com/tlajer/tldr",
          "version": 1.0,
          "private": true,
          "scripts": { "build": "make build", "test-all": "make test" },
          "files": [ { "path": "App/PathBar.swift", "lines": 214 }, { "path": "README.md", "lines": null } ],
        }
        """
        let pasteboard = NSPasteboard.general.string(forType: .string)
        defer {
            NSPasteboard.general.clearContents()
            if let pasteboard { NSPasteboard.general.setString(pasteboard, forType: .string) }
        }
        for dark in [false, true] {
            let webView = try await load(html: DataRenderer.renderJSONPage(json, lines: false, title: "package.json"), dark: dark)
            try await snapshot(webView, dark ? "json-dark.png" : "json-light.png")
            let status = try await webView.callAsyncJavaScript("""
                const key = [...document.querySelectorAll('.k')].find(k => k.textContent === '"test-all"');
                key.click();
                return document.getElementById('status').textContent
                """, contentWorld: .page) as? String
            XCTAssertEqual(status, #"copied path: .scripts["test-all"]"#)
            let index = try await webView.callAsyncJavaScript("""
                document.querySelectorAll('[data-k="files"] > .ch > .n')[1].querySelector('.k').click();
                return document.getElementById('status').textContent
                """, contentWorld: .page) as? String
            XCTAssertEqual(index, "copied path: .files[1].path")
            try await Task.sleep(for: .milliseconds(50))
            XCTAssertEqual(NSPasteboard.general.string(forType: .string), ".files[1].path")
            let open = try await webView.callAsyncJavaScript("""
                document.dispatchEvent(new KeyboardEvent('keydown', {key: '1'}));
                return document.querySelectorAll('details[open]').length
                """, contentWorld: .page) as? Int
            XCTAssertEqual(open, 1)
        }

        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!-- Maven-style config -->
        <project xmlns="http://maven.apache.org/POM/4.0.0">
          <name>tldr</name>
          <dependencies>
            <dependency scope="test"><artifactId>junit</artifactId></dependency>
            <dependency><artifactId>swift-markdown</artifactId><version>0.5.0</version></dependency>
          </dependencies>
          <description><![CDATA[Uses <markdown> & more]]></description>
        </project>
        """
        let webView = try await load(html: DataRenderer.renderXMLPage(xml, title: "pom.xml"), dark: true)
        try await snapshot(webView, "xml-dark.png")
        let xpath = try await webView.callAsyncJavaScript("""
            document.querySelectorAll('[data-t="dependency"]')[0].querySelector('.a').click();
            return document.getElementById('status').textContent
            """, contentWorld: .page) as? String
        XCTAssertEqual(xpath, "copied path: /project/dependencies/dependency[1]/@scope")

        let broken = try await load(html: DataRenderer.renderJSONPage("{\n  \"a\": 1\n  \"b\": 2\n}", lines: false, title: "bad.json"))
        try await snapshot(broken, "json-error.png")
    }
}
