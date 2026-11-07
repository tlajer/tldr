import XCTest
@testable import MarkdownRenderer

final class MarkdownRendererTests: XCTestCase {
    func testEscapesCodeAndText() {
        let html = MarkdownRenderer.renderBody(markdown: "a < b & c\n\n```html\n<div>\n```")
        XCTAssertTrue(html.contains("<p>a &lt; b &amp; c</p>"))
        XCTAssertTrue(html.contains("<pre><code class=\"language-html\">&lt;div&gt;\n</code></pre>"))
    }

    func testHeadingKeepsInlineFormattingAndGetsUniqueIds() {
        let html = MarkdownRenderer.renderBody(markdown: "# Hello *World*\n\n# Hello World")
        XCTAssertTrue(html.contains("<h1 id=\"hello-world\">"))
        XCTAssertTrue(html.contains("Hello <em>World</em></h1>"))
        XCTAssertTrue(html.contains("<h1 id=\"hello-world-1\">"))
    }

    func testGFMTableTaskListStrikethrough() {
        let md = "| a | b |\n|:--|--:|\n| 1 | 2 |\n\n- [x] done\n- [ ] todo\n\n~~gone~~"
        let html = MarkdownRenderer.renderBody(markdown: md)
        XCTAssertTrue(html.contains("<th align=\"left\">a</th>"))
        XCTAssertTrue(html.contains("<td align=\"right\">2</td>"))
        XCTAssertTrue(html.contains("<input type=\"checkbox\" disabled checked> done"))
        XCTAssertTrue(html.contains("<del>gone</del>"))
    }

    func testTightListHasNoParagraphs() {
        let html = MarkdownRenderer.renderBody(markdown: "- one\n- two")
        XCTAssertTrue(html.contains("<li>one\n</li>"))
        let loose = MarkdownRenderer.renderBody(markdown: "- one\n\n- two")
        XCTAssertTrue(loose.contains("<li><p>one</p>"))
    }

    func testAlert() {
        let html = MarkdownRenderer.renderBody(markdown: "> [!WARNING]\n> Be careful")
        XCTAssertTrue(html.contains("<div class=\"alert alert-warning\">"))
        XCTAssertTrue(html.contains("<p>Be careful</p>"))
    }

    func testFrontMatterIsSplitOff() {
        let (front, body) = MarkdownRenderer.splitFrontMatter("---\ntitle: x\n---\n# Hi")
        XCTAssertEqual(front, "title: x")
        XCTAssertEqual(body, "# Hi")
    }

    func testRelativeImageIsInlined() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: dir.appendingPathComponent("pic.png"))
        let html = MarkdownRenderer.renderBody(markdown: "![alt text](pic.png)", baseURL: dir)
        XCTAssertTrue(html.contains("src=\"data:image/png;base64,iVBORw==\""))
        XCTAssertTrue(html.contains("alt=\"alt text\""))
    }

    func testMermaidBlockLoadsScriptsOnlyWhenNeeded() {
        let page = MarkdownRenderer.renderPage(markdown: "```mermaid\ngraph TD; A-->B\n```", title: "t", baseURL: nil)
        XCTAssertTrue(page.contains("<pre class=\"mermaid\">graph TD; A--&gt;B\n</pre>"))
        XCTAssertTrue(page.contains("tldr-resource://local/mermaid.min.js"))
        let plain = MarkdownRenderer.renderPage(markdown: "# Hi", title: "t", baseURL: nil)
        XCTAssertFalse(plain.contains("mermaid.min.js"))
        XCTAssertTrue(plain.contains("Content-Security-Policy"))
    }
}
