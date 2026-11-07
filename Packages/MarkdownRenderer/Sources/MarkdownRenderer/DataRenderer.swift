import Foundation
import UniformTypeIdentifiers

/// What a file is rendered as, decided by its extension.
public enum DocumentKind: Equatable {
    case markdown
    case json(lines: Bool)
    case xml

    static let jsonExtensions: Set = ["json", "jsonc", "json5", "geojson", "topojson", "webmanifest", "har", "ipynb"]
    static let jsonLinesExtensions: Set = ["jsonl", "ndjson"]
    static let xmlExtensions: Set = ["xml", "xsd", "xsl", "xslt", "xaml", "rss", "atom", "opml", "gpx", "kml", "csproj", "fsproj", "vbproj", "resx", "storyboard", "xib", "xcscheme"]
    static let markdownExtensions: Set = ["md", "markdown", "mdown", "mkd", "mkdn", "mdwn", "mdtext"]

    /// The kind for a file the viewer can open, or nil for anything else.
    public init?(fileExtension ext: String) {
        let ext = ext.lowercased()
        if Self.markdownExtensions.contains(ext) { self = .markdown; return }
        if Self.jsonLinesExtensions.contains(ext) { self = .json(lines: true); return }
        if Self.jsonExtensions.contains(ext) { self = .json(lines: false); return }
        if Self.xmlExtensions.contains(ext) { self = .xml; return }
        guard let type = UTType(filenameExtension: ext) else { return nil }
        if type.conforms(to: .json) { self = .json(lines: false); return }
        if type.conforms(to: .xml) { self = .xml; return }
        return nil
    }

    /// Markdown unless the extension says otherwise (also for files without a URL).
    public init(fileURL: URL?) {
        self = fileURL.flatMap { DocumentKind(fileExtension: $0.pathExtension) } ?? .markdown
    }
}

public enum DocumentRenderer {
    /// Renders any supported file to a complete, self-contained HTML page.
    public static func renderPage(text: String, kind: DocumentKind, title: String, baseURL: URL?) -> String {
        switch kind {
        case .markdown: MarkdownRenderer.renderPage(markdown: text, title: title, baseURL: baseURL)
        case .json(let lines): DataRenderer.renderJSONPage(text, lines: lines, title: title)
        case .xml: DataRenderer.renderXMLPage(text, title: title)
        }
    }
}

/// JSON and XML as a foldable, syntax-coloured tree. Clicking a key copies its path
/// (jq for JSON, XPath for XML) and clicking a value copies the value; see data-view.js.
enum DataRenderer {
    /// Above this the tree is skipped and only the raw source is shown.
    static let maxTreeBytes = 15 * 1024 * 1024
    /// Documents with more nodes than this start folded below the second level.
    static let maxOpenNodes = 3000

    static func renderJSONPage(_ text: String, lines: Bool, title: String) -> String {
        let format = lines ? "JSON Lines" : "JSON"
        guard text.utf8.count <= maxTreeBytes else {
            return page(title: title, format: format, badges: [], meta: size(text), tree: nil, raw: text,
                        notice: "Large file: showing the source only.")
        }
        do {
            var badges: [String] = []
            let roots: [(JSONNode, Int?)]
            if lines {
                roots = try JSONParser.parseLines(text).enumerated().map { ($1, $0) }
            } else {
                let (value, lenient) = try JSONParser.parse(text)
                roots = [(value, nil)]
                if lenient { badges.append("comments / trailing commas") }
            }
            let count = roots.reduce(0) { $0 + $1.0.nodeCount }
            var html = JSONHTML(openDepth: count > maxOpenNodes ? 2 : .max)
            for (value, index) in roots {
                html.render(value, key: index.map(JSONHTML.Key.index), depth: 0, last: true)
            }
            let meta = (lines ? "\(roots.count.formatted()) records · " : "") + "\(count.formatted()) nodes · \(size(text))"
            return page(title: title, format: format, badges: badges, meta: meta, tree: html.out, raw: text)
        } catch let error as SourceError {
            return page(title: title, format: format, badges: [], meta: size(text), tree: nil, raw: text, error: error)
        } catch {
            return page(title: title, format: format, badges: [], meta: size(text), tree: nil, raw: text)
        }
    }

    static func renderXMLPage(_ text: String, title: String) -> String {
        guard text.utf8.count <= maxTreeBytes else {
            return page(title: title, format: "XML", badges: [], meta: size(text), tree: nil, raw: text,
                        notice: "Large file: showing the source only.")
        }
        // XMLParser reports where the document breaks; XMLDocument doesn't.
        let parser = XMLParser(data: Data(text.utf8))
        parser.shouldResolveExternalEntities = false
        guard parser.parse() else {
            let message = (parser.parserError as NSError?)?.localizedDescription ?? "Invalid XML"
            let error = SourceError(message: message.trimmingCharacters(in: .whitespacesAndNewlines),
                                    line: parser.lineNumber, column: parser.columnNumber)
            return page(title: title, format: "XML", badges: [], meta: size(text), tree: nil, raw: text, error: error)
        }
        guard let document = try? XMLDocument(xmlString: text, options: [.nodePreserveCDATA, .nodeLoadExternalEntitiesNever]) else {
            return page(title: title, format: "XML", badges: [], meta: size(text), tree: nil, raw: text)
        }
        let count = XMLHTML.count(document)
        var html = XMLHTML(openDepth: count > maxOpenNodes ? 2 : .max)
        if let declaration = text.drop(while: { $0 == "\u{FEFF}" }).split(separator: "\n", maxSplits: 1).first,
           declaration.hasPrefix("<?xml") {
            html.out += "<div class=\"n\"><span class=\"pi\">\(escape(String(declaration).trimmingCharacters(in: .whitespaces)))</span></div>"
        }
        for child in document.children ?? [] {
            html.render(child, depth: 0)
        }
        let root = document.rootElement()?.name.map { "<\($0)> · " } ?? ""
        return page(title: title, format: "XML", badges: [], meta: "\(root)\(count.formatted()) nodes · \(size(text))",
                    tree: html.out, raw: text)
    }

    // MARK: Page

    static func page(title: String, format: String, badges: [String], meta: String, tree: String?, raw: String,
                     error: SourceError? = nil, notice: String? = nil) -> String {
        var body = "<header class=\"bar\"><span class=\"badge\">\(escape(format))</span>"
        body += badges.map { "<span class=\"badge muted\">\(escape($0))</span>" }.joined()
        body += "<span class=\"meta\">\(escape(meta))</span><span class=\"spacer\"></span>"
        if tree != nil {
            body += """
            <button data-act="expand" title="Expand all (E) · fold to level: 1–9">Expand</button>\
            <button data-act="collapse" title="Collapse all (C)">Collapse</button>\
            <button data-act="raw" title="Toggle source (R)">Source</button>
            """
        }
        body += "</header>\n"
        if let error {
            body += """
            <div class="error"><strong>\(escape(format)) error</strong> on \
            <a href="#L\(error.line)">line \(error.line), column \(error.column)</a>: \(escape(error.message))</div>\n
            """
        }
        if let notice {
            body += "<div class=\"notice\">\(escape(notice))</div>\n"
        }
        if let tree {
            body += "<main class=\"tree\">\(tree)</main>\n"
        }
        body += rawHTML(raw, errorLine: error?.line, large: tree == nil && notice != nil) + "\n"
        if tree != nil {
            body += "<footer id=\"status\" data-hint=\"click key: copy path · click value: copy value · ⌥-click ▸: fold all inside\"></footer>\n"
        }
        let scripts = tree == nil ? [] : ["data-view.js"]
        return MarkdownRenderer.page(title: title, bodyClass: "data" + (tree == nil ? " show-raw" : ""),
                                     content: body, scripts: scripts)
    }

    /// The source with line numbers (one span per line, each linkable as #L<n>).
    static func rawHTML(_ text: String, errorLine: Int?, large: Bool) -> String {
        if large { return "<pre class=\"raw\"><code>\(escape(text))</code></pre>" }
        var out = "<pre class=\"raw\"><code>"
        for (i, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let n = i + 1
            let content = line.hasSuffix("\r") ? line.dropLast() : line
            out += "<span class=\"line\(n == errorLine ? " err" : "")\" id=\"L\(n)\">\(escape(String(content)))\n</span>"
        }
        return out + "</code></pre>"
    }

    static func size(_ text: String) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(text.utf8.count), countStyle: .file)
    }
}

private struct JSONHTML {
    enum Key {
        case name(String)
        case index(Int)
    }

    let openDepth: Int
    var out = ""

    init(openDepth: Int) {
        self.openDepth = openDepth
    }

    mutating func render(_ node: JSONNode, key: Key?, depth: Int, last: Bool) {
        let comma = last ? "" : "<span class=\"p\">,</span>"
        var attrs = ""
        var label = ""
        switch key {
        case .name(let name):
            attrs = " data-k=\"\(escapeAttribute(name))\""
            label = "<span class=\"k\">\(escape(quoted(name)))</span><span class=\"p\">: </span>"
        case .index(let index):
            attrs = " data-i=\"\(index)\""
            label = "<span class=\"i\">\(index)</span>"
        case nil:
            break
        }

        switch node {
        case .object(let members) where !members.isEmpty:
            open(attrs, depth: depth, label: label, brackets: ("{", "}"), summary: count(members.count, "key"), comma: comma)
            for (i, member) in members.enumerated() {
                render(member.value, key: .name(member.key), depth: depth + 1, last: i == members.count - 1)
            }
            close("}", comma: comma)
        case .array(let items) where !items.isEmpty:
            open(attrs, depth: depth, label: label, brackets: ("[", "]"), summary: count(items.count, "item"), comma: comma)
            for (i, item) in items.enumerated() {
                render(item, key: .index(i), depth: depth + 1, last: i == items.count - 1)
            }
            close("]", comma: comma)
        default:
            out += "<div class=\"n\"\(attrs)>\(label)\(scalar(node))\(comma)</div>"
        }
    }

    private mutating func open(_ attrs: String, depth: Int, label: String, brackets: (String, String), summary: String, comma: String) {
        out += "<details class=\"n\" data-d=\"\(depth)\"\(attrs)\(depth < openDepth ? " open" : "")><summary>\(label)"
        out += "<span class=\"p\">\(brackets.0)</span><span class=\"sum\"> \(summary) <span class=\"p\">\(brackets.1)</span>\(comma)</span>"
        out += "</summary><div class=\"ch\">"
    }

    private mutating func close(_ bracket: String, comma: String) {
        out += "</div><div class=\"end\"><span class=\"p\">\(bracket)</span>\(comma)</div></details>"
    }

    private func scalar(_ node: JSONNode) -> String {
        switch node {
        case .string(let s):
            let shown = escape(quoted(s))
            if (s.hasPrefix("https://") || s.hasPrefix("http://")), !s.contains(where: \.isWhitespace), URL(string: s) != nil {
                return "<span class=\"s\"><a href=\"\(escapeAttribute(s))\">\(shown)</a></span>"
            }
            return "<span class=\"s\">\(shown)</span>"
        case .number(let n): return "<span class=\"num\">\(escape(n))</span>"
        case .bool(let b): return "<span class=\"bool\">\(b)</span>"
        case .null: return "<span class=\"null\">null</span>"
        case .object: return "<span class=\"p\">{}</span>"
        case .array: return "<span class=\"p\">[]</span>"
        }
    }

    private func count(_ n: Int, _ noun: String) -> String {
        "<span class=\"c\">\(n.formatted()) \(noun)\(n == 1 ? "" : "s")</span>"
    }

    /// A JSON string literal, so it can be copied back out with JSON.parse.
    private func quoted(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            case _ where scalar.value < 0x20 || scalar.value == 0x2028 || scalar.value == 0x2029:
                out += String(format: "\\u%04X", scalar.value)
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }
}

private struct XMLHTML {
    let openDepth: Int
    var out = ""

    /// Elements whose only content is text up to this length stay on one line.
    static let inlineTextLimit = 120

    init(openDepth: Int) {
        self.openDepth = openDepth
    }

    static func count(_ node: XMLNode) -> Int {
        (node.children ?? []).reduce(1) { $0 + count($1) }
    }

    mutating func render(_ node: XMLNode, depth: Int) {
        switch node.kind {
        case .element:
            guard let element = node as? XMLElement else { return }
            renderElement(element, depth: depth)
        case .text:
            let xml = node.xmlString
            if xml.hasPrefix("<![CDATA[") {
                out += "<div class=\"n\"><span class=\"p\">&lt;![CDATA[</span><span class=\"txt\">\(escape(node.stringValue ?? ""))</span><span class=\"p\">]]&gt;</span></div>"
            } else if let text = node.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                out += "<div class=\"n\"><span class=\"txt\">\(escape(text))</span></div>"
            }
        case .comment:
            out += "<div class=\"n\"><span class=\"com\">&lt;!--\(escape(node.stringValue ?? ""))--&gt;</span></div>"
        case .processingInstruction:
            out += "<div class=\"n\"><span class=\"pi\">\(escape(node.xmlString))</span></div>"
        case .DTDKind:
            out += "<div class=\"n\"><span class=\"pi\">\(escape(node.xmlString.trimmingCharacters(in: .whitespacesAndNewlines)))</span></div>"
        default:
            break
        }
    }

    private mutating func renderElement(_ element: XMLElement, depth: Int) {
        let name = element.name ?? ""
        var attrs = " data-t=\"\(escapeAttribute(name))\""
        if let index = siblingIndex(of: element) { attrs += " data-x=\"\(index)\"" }

        let tagOpen = "<span class=\"p\">&lt;</span><span class=\"t\">\(escape(name))</span>\(attributes(of: element))"
        let tagClose = "<span class=\"p\">&lt;/</span><span class=\"t\">\(escape(name))</span><span class=\"p\">&gt;</span>"
        let children = (element.children ?? []).filter { child in
            child.kind != .text || child.xmlString.hasPrefix("<![CDATA[")
                || !(child.stringValue ?? "").allSatisfy(\.isWhitespace)
        }

        if children.isEmpty {
            out += "<div class=\"n\"\(attrs)>\(tagOpen)<span class=\"p\">/&gt;</span></div>"
        } else if children.count == 1, let text = children[0].stringValue, children[0].kind == .text,
                  !children[0].xmlString.hasPrefix("<![CDATA["), text.count <= Self.inlineTextLimit, !text.contains("\n") {
            out += "<div class=\"n\"\(attrs)>\(tagOpen)<span class=\"p\">&gt;</span><span class=\"txt\">\(escape(text))</span>\(tagClose)</div>"
        } else {
            let elements = children.filter { $0.kind == .element }.count
            let summary = elements > 0 ? "\(elements.formatted()) element\(elements == 1 ? "" : "s")" : "text"
            out += "<details class=\"n\" data-d=\"\(depth)\"\(attrs)\(depth < openDepth ? " open" : "")><summary>"
            out += "\(tagOpen)<span class=\"p\">&gt;</span><span class=\"sum\"> <span class=\"c\">\(summary)</span> \(tagClose)</span>"
            out += "</summary><div class=\"ch\">"
            for child in children { render(child, depth: depth + 1) }
            out += "</div><div class=\"end\">\(tagClose)</div></details>"
        }
    }

    private func attributes(of element: XMLElement) -> String {
        var out = ""
        for ns in element.namespaces ?? [] {
            let prefix = ns.name ?? ""
            out += attribute(prefix.isEmpty ? "xmlns" : "xmlns:\(prefix)", ns.stringValue ?? "")
        }
        for attr in element.attributes ?? [] {
            out += attribute(attr.name ?? "", attr.stringValue ?? "")
        }
        return out
    }

    private func attribute(_ name: String, _ value: String) -> String {
        " <span class=\"a\" data-a=\"\(escapeAttribute(name))\">\(escape(name))</span><span class=\"p\">=\"</span>"
            + "<span class=\"v\">\(escape(value))</span><span class=\"p\">\"</span>"
    }

    /// 1-based position among same-named siblings, only when there's more than one (XPath style).
    private func siblingIndex(of element: XMLElement) -> Int? {
        guard let siblings = element.parent?.children?.filter({ $0.kind == .element && $0.name == element.name }),
              siblings.count > 1 else { return nil }
        return siblings.firstIndex { $0 === element }.map { $0 + 1 }
    }
}
