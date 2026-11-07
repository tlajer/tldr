import XCTest
@testable import MarkdownRenderer

final class DataRendererTests: XCTestCase {
    func testJSONKeepsKeyOrderAndNumberText() throws {
        let (value, lenient) = try JSONParser.parse(#"{"z": 1, "a": 1.50, "big": 12345678901234567890, "e": -2E+3}"#)
        XCTAssertFalse(lenient)
        XCTAssertEqual(value, .object([
            .init(key: "z", value: .number("1")),
            .init(key: "a", value: .number("1.50")),
            .init(key: "big", value: .number("12345678901234567890")),
            .init(key: "e", value: .number("-2E+3")),
        ]))
    }

    func testJSONStringEscapes() throws {
        let (value, _) = try JSONParser.parse(#"["a\"b\\c\n", "\u00e6\ud83d\ude00", "/\/"]"#)
        XCTAssertEqual(value, .array([.string("a\"b\\c\n"), .string("æ😀"), .string("//")]))
    }

    func testJSONCommentsAndTrailingCommas() throws {
        let text = """
        {
          // compiler options
          "strict": true, /* block */
          "paths": ["a", "b",],
        }
        """
        let (value, lenient) = try JSONParser.parse(text)
        XCTAssertTrue(lenient)
        XCTAssertEqual(value, .object([
            .init(key: "strict", value: .bool(true)),
            .init(key: "paths", value: .array([.string("a"), .string("b")])),
        ]))
    }

    func testJSONErrorsPointAtLineAndColumn() {
        XCTAssertThrowsError(try JSONParser.parse("{\n  \"a\": 1\n  \"b\": 2\n}")) { error in
            XCTAssertEqual(error as? SourceError,
                           SourceError(message: "Expected ',' or '}' in object, found '\"'", line: 3, column: 3))
        }
        XCTAssertThrowsError(try JSONParser.parse("[1, 2")) { error in
            XCTAssertEqual((error as? SourceError)?.line, 1)
        }
        XCTAssertThrowsError(try JSONParser.parse("{\"æø\": tru}")) { error in
            XCTAssertEqual((error as? SourceError)?.column, 8)
        }
        for bad in ["01", "1.", "-", "\"\\x\"", "\"abc", "{} {}", "[1,,2]", "nul", "/* open"] {
            XCTAssertThrowsError(try JSONParser.parse(bad), bad)
        }
    }

    func testJSONLinesReportsTheFailingLine() throws {
        XCTAssertEqual(try JSONParser.parseLines("{\"a\":1}\n\n[2]\n").count, 2)
        XCTAssertThrowsError(try JSONParser.parseLines("{}\n{}\n{oops}")) { error in
            XCTAssertEqual((error as? SourceError)?.line, 3)
        }
    }

    func testJSONPageRendersTree() {
        let page = DataRenderer.renderJSONPage(#"{"name": "tldr", "url": "https://x.dk", "tags": [true, null]}"#, lines: false, title: "t")
        XCTAssertTrue(page.contains("data-view.js"))
        XCTAssertTrue(page.contains(#"<div class="n" data-k="name"><span class="k">&quot;name&quot;</span>"#)
                      || page.contains(#"<div class="n" data-k="name"><span class="k">"name"</span>"#))
        XCTAssertTrue(page.contains(#"<a href="https://x.dk">"#))
        XCTAssertTrue(page.contains(#"data-k="tags" open>"#))
        XCTAssertTrue(page.contains(#"<div class="n" data-i="1"><span class="i">1</span><span class="null">null</span></div>"#))
        XCTAssertTrue(page.contains("2 items"))
        XCTAssertTrue(page.contains(#"<body class="data">"#))
    }

    func testInvalidJSONShowsErrorAndSource() {
        let page = DataRenderer.renderJSONPage("{\n\"a\": <script>\n}", lines: false, title: "t")
        XCTAssertTrue(page.contains(##"<a href="#L2">line 2, column 6</a>"##))
        XCTAssertTrue(page.contains(#"<span class="line err" id="L2">&quot;a&quot;: &lt;script&gt;"#)
                      || page.contains(#"<span class="line err" id="L2">"a": &lt;script&gt;"#))
        XCTAssertTrue(page.contains(#"class="data show-raw""#))
        XCTAssertFalse(page.contains("<script>\n"))
    }

    func testBigDocumentsStartFolded() {
        let items = (0..<4000).map { "{\"id\": \($0)}" }.joined(separator: ",")
        let page = DataRenderer.renderJSONPage("{\"items\": [\(items)]}", lines: false, title: "t")
        XCTAssertTrue(page.contains(#"data-d="1" data-k="items" open>"#))
        XCTAssertTrue(page.contains(#"data-d="2" data-i="0">"#))
    }

    func testXMLPageRendersTree() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!-- config -->
        <root xmlns:x="urn:x" version="2">
          <item id="a">first</item>
          <item id="b"><![CDATA[<raw>]]></item>
          <empty/>
        </root>
        """
        let page = DataRenderer.renderXMLPage(xml, title: "t")
        XCTAssertTrue(page.contains(#"<span class="pi">&lt;?xml version="1.0" encoding="UTF-8"?&gt;</span>"#))
        XCTAssertTrue(page.contains(#"<span class="com">&lt;!-- config --&gt;</span>"#))
        XCTAssertTrue(page.contains(#"data-a="xmlns:x""#))
        XCTAssertTrue(page.contains(#"<div class="n" data-t="item" data-x="1">"#))
        XCTAssertTrue(page.contains(#"<span class="txt">first</span>"#))
        XCTAssertTrue(page.contains(#"<span class="txt">&lt;raw&gt;</span>"#))
        XCTAssertTrue(page.contains(#"<div class="n" data-t="empty"><span class="p">&lt;</span><span class="t">empty</span><span class="p">/&gt;</span></div>"#))
        XCTAssertTrue(page.contains("&lt;root&gt; · "))
    }

    func testInvalidXMLShowsLine() {
        let page = DataRenderer.renderXMLPage("<a>\n  <b>\n</a>", title: "t")
        XCTAssertTrue(page.contains("XML error</strong> on <a href=\"#L3\">line 3"))
    }

    func testDocumentKind() {
        XCTAssertEqual(DocumentKind(fileExtension: "MD"), .markdown)
        XCTAssertEqual(DocumentKind(fileExtension: "json"), .json(lines: false))
        XCTAssertEqual(DocumentKind(fileExtension: "jsonc"), .json(lines: false))
        XCTAssertEqual(DocumentKind(fileExtension: "ndjson"), .json(lines: true))
        XCTAssertEqual(DocumentKind(fileExtension: "xml"), .xml)
        XCTAssertEqual(DocumentKind(fileExtension: "storyboard"), .xml)
        XCTAssertNil(DocumentKind(fileExtension: "png"))
        XCTAssertEqual(DocumentKind(fileURL: nil), .markdown)
    }
}
