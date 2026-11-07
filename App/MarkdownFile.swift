import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let markdown = UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
    static let jsonc = UTType(importedAs: "io.github.tlajer.tldr.jsonc", conformingTo: .json)
    static let jsonLines = UTType(importedAs: "io.github.tlajer.tldr.jsonl", conformingTo: .plainText)
    static let ndjson = UTType(importedAs: "public.ndjson", conformingTo: .plainText)
    static let xmlSource = UTType(importedAs: "io.github.tlajer.tldr.xml-source", conformingTo: .xml)
}

struct MarkdownFile: FileDocument {
    static let readableContentTypes: [UTType] = [.markdown, .json, .jsonc, .jsonLines, .ndjson, .xml, .xmlSource]

    var text: String

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = MarkdownFile.decode(data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        throw CocoaError(.fileWriteNoPermission)
    }

    static func decode(_ data: Data) -> String {
        String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
    }
}
