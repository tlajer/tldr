import Foundation
import Markdown
import UniformTypeIdentifiers

public enum MarkdownRenderer {
    /// Images larger than this are left as file references instead of being inlined.
    static let maxInlineImageBytes = 20 * 1024 * 1024

    /// Renders markdown to a complete, self-contained HTML page.
    ///
    /// - Parameters:
    ///   - baseURL: The directory of the markdown file. Relative image paths are resolved
    ///     against it and inlined as data: URIs, so the page works without file access.
    ///   - inlineImages: When false, relative images are emitted as absolute file URLs instead.
    public static func renderPage(markdown: String, title: String, baseURL: URL?, inlineImages: Bool = true) -> String {
        let (frontMatter, body) = splitFrontMatter(markdown)
        var html = ""
        if let frontMatter {
            html += "<details class=\"front-matter\"><summary>Front matter</summary><pre><code>\(escape(frontMatter))</code></pre></details>\n"
        }
        let rendered = render(markdown: body, baseURL: baseURL, inlineImages: inlineImages)
        html += rendered.html
        let scripts = rendered.hasMermaid ? ["mermaid.min.js", "mermaid-init.js"] : []
        return page(title: title, bodyClass: nil, content: "<article class=\"markdown-body\">\n\(html)\n</article>", scripts: scripts)
    }

    /// The HTML shell shared by every kind of document. `scripts` are bundled resources.
    static func page(title: String, bodyClass: String?, content: String, scripts: [String]) -> String {
        let scriptTags = scripts
            .map { "<script src=\"\(PreviewWebKit.resourceURL($0))\"></script>" }
            .joined(separator: "\n")
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="color-scheme" content="light dark">
        <meta http-equiv="Content-Security-Policy" content="\(contentSecurityPolicy)">
        <title>\(escape(title))</title>
        <style>\(Stylesheet.css)</style>
        </head>
        <body\(bodyClass.map { " class=\"\($0)\"" } ?? "")>
        \(content)
        \(scriptTags)
        </body>
        </html>
        """
    }

    /// Only bundled scripts may run; markdown files can contain raw HTML, including <script>.
    static let contentSecurityPolicy =
        "default-src 'none'; script-src \(PreviewWebKit.scheme):; style-src 'unsafe-inline'; img-src * data: blob:; font-src * data:"

    /// Renders markdown to an HTML fragment (no <html>/<head>).
    public static func renderBody(markdown: String, baseURL: URL? = nil, inlineImages: Bool = true) -> String {
        render(markdown: markdown, baseURL: baseURL, inlineImages: inlineImages).html
    }

    static func render(markdown: String, baseURL: URL?, inlineImages: Bool) -> (html: String, hasMermaid: Bool) {
        let document = Document(parsing: markdown)
        var renderer = HTMLRenderer { source in
            resolveImage(source, baseURL: baseURL, inline: inlineImages)
        }
        renderer.visit(document)
        return (renderer.result, renderer.hasMermaid)
    }

    static func splitFrontMatter(_ markdown: String) -> (String?, String) {
        guard markdown.hasPrefix("---\n") || markdown.hasPrefix("---\r\n") else { return (nil, markdown) }
        let lines = markdown.components(separatedBy: .newlines)
        guard let end = lines.dropFirst().firstIndex(where: { $0 == "---" || $0 == "..." }) else {
            return (nil, markdown)
        }
        let front = lines[1..<end].joined(separator: "\n")
        let body = lines[(end + 1)...].joined(separator: "\n")
        return (front, body)
    }

    static func resolveImage(_ source: String, baseURL: URL?, inline: Bool) -> String? {
        guard let baseURL, !source.isEmpty,
              URL(string: source)?.scheme == nil || source.hasPrefix("file:") else { return nil }
        let path = source.removingPercentEncoding ?? source
        let fileURL = source.hasPrefix("file:")
            ? URL(string: source)!
            : (path.hasPrefix("/") ? URL(fileURLWithPath: path) : baseURL.appendingPathComponent(path))
        guard inline else { return fileURL.absoluteString }
        guard let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= maxInlineImageBytes,
              let data = try? Data(contentsOf: fileURL) else { return nil }
        let mime = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        return "data:\(mime);base64,\(data.base64EncodedString())"
    }
}
