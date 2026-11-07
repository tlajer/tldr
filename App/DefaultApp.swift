import AppKit
import UniformTypeIdentifiers

/// The file types TL;DR can be the default app for, grouped the way people think of them.
/// Keep in sync with the `default` target in the Makefile.
enum FileTypeGroup: String, CaseIterable, Identifiable {
    case markdown = "Markdown"
    case json = "JSON"
    case xml = "XML"

    var id: String { rawValue }

    var types: [UTType] {
        switch self {
        case .markdown: [.markdown]
        case .json: [.json, .jsonc, .jsonLines, .ndjson]
        case .xml: [.xml, .xmlSource]
        }
    }

    var extensions: String {
        switch self {
        case .markdown: ".md .markdown"
        case .json: ".json .jsonc .jsonl .ndjson …"
        case .xml: ".xml .xsd .xslt .csproj …"
        }
    }

    /// True when TL;DR opens every type in the group on double-click.
    var isDefault: Bool {
        types.allSatisfy { type in
            NSWorkspace.shared.urlForApplication(toOpen: type)?.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
        }
    }

    /// The app that opens the group's main type now, when it isn't TL;DR.
    var currentApp: String? {
        guard let url = NSWorkspace.shared.urlForApplication(toOpen: types[0]),
              url.standardizedFileURL != Bundle.main.bundleURL.standardizedFileURL else { return nil }
        return FileManager.default.displayName(atPath: url.path(percentEncoded: false)).replacingOccurrences(of: ".app", with: "")
    }

    /// Makes TL;DR the default for every type in the group. macOS may ask the user to confirm.
    func makeDefault() async throws {
        for type in types {
            try await NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: type)
        }
    }
}
