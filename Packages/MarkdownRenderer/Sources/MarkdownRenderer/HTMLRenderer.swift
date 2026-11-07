import Foundation
import Markdown

/// Walks a swift-markdown document and produces escaped, GitHub-flavoured HTML.
struct HTMLRenderer: MarkupWalker {
    var result = ""
    /// Maps an image source (as written in the markdown) to the `src` to emit, e.g. a data: URI.
    var resolveImage: (String) -> String?
    /// Set when the document contains a ```mermaid block, so the page knows to load Mermaid.
    private(set) var hasMermaid = false

    private var usedSlugs: [String: Int] = [:]
    private var tableAlignments: [Table.ColumnAlignment?] = []
    private var inTableHead = false
    private var cellIndex = 0

    init(resolveImage: @escaping (String) -> String?) {
        self.resolveImage = resolveImage
    }

    // MARK: Blocks

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
        if let alert = Alert(blockQuote) {
            result += "<div class=\"alert alert-\(alert.kind)\">\n<p class=\"alert-title\">\(alert.title)</p>\n"
            if !alert.remainder.isEmpty {
                // Text that followed the [!KIND] marker in the first paragraph.
                result += "<p>"
                for child in alert.remainder { visit(child) }
                result += "</p>\n"
            }
            for child in blockQuote.children.dropFirst() { visit(child) }
            result += "</div>\n"
        } else {
            result += "<blockquote>\n"
            descendInto(blockQuote)
            result += "</blockquote>\n"
        }
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        if codeBlock.language?.lowercased() == "mermaid" {
            hasMermaid = true
            result += "<pre class=\"mermaid\">\(escape(codeBlock.code))</pre>\n"
            return
        }
        let lang = codeBlock.language.map { " class=\"language-\(escapeAttribute($0))\"" } ?? ""
        result += "<pre><code\(lang)>\(escape(codeBlock.code))</code></pre>\n"
    }

    mutating func visitHeading(_ heading: Heading) {
        let slug = uniqueSlug(for: heading.plainText)
        result += "<h\(heading.level) id=\"\(slug)\"><a class=\"anchor\" href=\"#\(slug)\" aria-hidden=\"true\"></a>"
        descendInto(heading)
        result += "</h\(heading.level)>\n"
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
        result += "<hr>\n"
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) {
        result += html.rawHTML
    }

    mutating func visitParagraph(_ paragraph: Paragraph) {
        // Tight list items render their paragraphs without <p>, like GitHub.
        if let item = paragraph.parent as? ListItem, let list = item.parent, isTight(list) {
            descendInto(paragraph)
            result += "\n"
            return
        }
        result += "<p>"
        descendInto(paragraph)
        result += "</p>\n"
    }

    mutating func visitOrderedList(_ orderedList: OrderedList) {
        let start = orderedList.startIndex != 1 ? " start=\"\(orderedList.startIndex)\"" : ""
        result += "<ol\(start)>\n"
        descendInto(orderedList)
        result += "</ol>\n"
    }

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) {
        let isTaskList = unorderedList.listItems.contains { $0.checkbox != nil }
        result += isTaskList ? "<ul class=\"task-list\">\n" : "<ul>\n"
        descendInto(unorderedList)
        result += "</ul>\n"
    }

    mutating func visitListItem(_ listItem: ListItem) {
        if let checkbox = listItem.checkbox {
            result += "<li class=\"task-list-item\"><input type=\"checkbox\" disabled\(checkbox == .checked ? " checked" : "")> "
        } else {
            result += "<li>"
        }
        descendInto(listItem)
        result += "</li>\n"
    }

    mutating func visitTable(_ table: Table) {
        tableAlignments = table.columnAlignments
        result += "<table>\n"
        descendInto(table)
        result += "</table>\n"
    }

    mutating func visitTableHead(_ tableHead: Table.Head) {
        inTableHead = true
        cellIndex = 0
        result += "<thead>\n<tr>\n"
        descendInto(tableHead)
        result += "</tr>\n</thead>\n"
        inTableHead = false
    }

    mutating func visitTableBody(_ tableBody: Table.Body) {
        guard !tableBody.isEmpty else { return }
        result += "<tbody>\n"
        descendInto(tableBody)
        result += "</tbody>\n"
    }

    mutating func visitTableRow(_ tableRow: Table.Row) {
        cellIndex = 0
        result += "<tr>\n"
        descendInto(tableRow)
        result += "</tr>\n"
    }

    mutating func visitTableCell(_ tableCell: Table.Cell) {
        guard tableCell.colspan > 0, tableCell.rowspan > 0 else { return }
        let tag = inTableHead ? "th" : "td"
        var attrs = ""
        if cellIndex < tableAlignments.count, let alignment = tableAlignments[cellIndex] {
            attrs += " align=\"\(alignment)\""
        }
        if tableCell.colspan > 1 { attrs += " colspan=\"\(tableCell.colspan)\"" }
        if tableCell.rowspan > 1 { attrs += " rowspan=\"\(tableCell.rowspan)\"" }
        cellIndex += Int(tableCell.colspan)
        result += "<\(tag)\(attrs)>"
        descendInto(tableCell)
        result += "</\(tag)>\n"
    }

    // MARK: Inlines

    mutating func visitText(_ text: Markdown.Text) {
        result += escape(text.string)
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) {
        result += "<code>\(escape(inlineCode.code))</code>"
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) {
        wrap("em", emphasis)
    }

    mutating func visitStrong(_ strong: Strong) {
        wrap("strong", strong)
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) {
        wrap("del", strikethrough)
    }

    mutating func visitLink(_ link: Link) {
        result += "<a href=\"\(escapeAttribute(link.destination ?? ""))\""
        if let title = link.title, !title.isEmpty { result += " title=\"\(escapeAttribute(title))\"" }
        result += ">"
        descendInto(link)
        result += "</a>"
    }

    mutating func visitImage(_ image: Image) {
        let source = image.source ?? ""
        let src = resolveImage(source) ?? source
        result += "<img src=\"\(escapeAttribute(src))\" alt=\"\(escapeAttribute(image.plainText))\""
        if let title = image.title, !title.isEmpty { result += " title=\"\(escapeAttribute(title))\"" }
        result += ">"
    }

    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) {
        result += inlineHTML.rawHTML
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) {
        result += "<br>\n"
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) {
        result += "\n"
    }

    mutating func visitSymbolLink(_ symbolLink: SymbolLink) {
        result += "<code>\(escape(symbolLink.destination ?? ""))</code>"
    }

    // MARK: Helpers

    private mutating func wrap(_ tag: String, _ markup: Markup) {
        result += "<\(tag)>"
        descendInto(markup)
        result += "</\(tag)>"
    }

    private func isTight(_ list: Markup) -> Bool {
        // swift-markdown doesn't expose cmark's tight flag. A list is loose if a blank line
        // separates any two consecutive blocks, whether inside one item or across items.
        // Item ranges swallow trailing blank lines, so compare the blocks' own ranges.
        let blocks = list.children.flatMap { Array($0.children) }
        for (a, b) in zip(blocks, blocks.dropFirst()) {
            if let endA = endLine(of: a), let startB = b.range?.lowerBound.line, startB - endA > 1 {
                return false
            }
        }
        return true
    }

    private func endLine(of markup: Markup) -> Int? {
        if let last = markup.child(at: markup.childCount - 1), !(markup is Paragraph) {
            return endLine(of: last)
        }
        return markup.range?.upperBound.line
    }

    private mutating func uniqueSlug(for text: String) -> String {
        var slug = ""
        for scalar in text.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_" {
                slug.unicodeScalars.append(scalar)
            } else if scalar == " " {
                slug += "-"
            }
        }
        let count = usedSlugs[slug, default: 0]
        usedSlugs[slug] = count + 1
        return escapeAttribute(count == 0 ? slug : "\(slug)-\(count)")
    }
}

/// GitHub-style alerts: `> [!NOTE]`, `> [!TIP]`, `> [!IMPORTANT]`, `> [!WARNING]`, `> [!CAUTION]`.
private struct Alert {
    let kind: String
    let title: String
    /// Inline nodes in the first paragraph after the marker (and its line break).
    let remainder: [Markup]

    init?(_ blockQuote: BlockQuote) {
        guard let first = blockQuote.child(at: 0) as? Paragraph,
              let marker = first.child(at: 0) as? Markdown.Text else { return nil }
        let raw = marker.string.trimmingCharacters(in: .whitespaces)
        let kinds = ["NOTE": "Note", "TIP": "Tip", "IMPORTANT": "Important", "WARNING": "Warning", "CAUTION": "Caution"]
        guard raw.hasPrefix("[!"), raw.hasSuffix("]"),
              let title = kinds[String(raw.dropFirst(2).dropLast()).uppercased()] else { return nil }
        self.kind = title.lowercased()
        self.title = title
        var rest = Array(first.children.dropFirst())
        if let head = rest.first, head is SoftBreak || head is LineBreak { rest.removeFirst() }
        self.remainder = rest
    }
}

func escape(_ string: String) -> String {
    var out = ""
    out.reserveCapacity(string.utf8.count)
    for ch in string {
        switch ch {
        case "&": out += "&amp;"
        case "<": out += "&lt;"
        case ">": out += "&gt;"
        default: out.append(ch)
        }
    }
    return out
}

func escapeAttribute(_ string: String) -> String {
    escape(string).replacingOccurrences(of: "\"", with: "&quot;")
}
