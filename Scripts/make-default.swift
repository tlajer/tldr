// Makes TL;DR the default app for markdown, JSON and XML (macOS may ask for confirmation).
// Usage: swift Scripts/make-default.swift /Applications/TLDR.app
// Keep the list in sync with FileTypeGroup in App/DefaultApp.swift.
import AppKit
import UniformTypeIdentifiers

let identifiers = [
    "net.daringfireball.markdown",
    "public.json", "io.github.tlajer.tldr.jsonc", "io.github.tlajer.tldr.jsonl", "public.ndjson",
    "public.xml", "io.github.tlajer.tldr.xml-source",
]
let app = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "/Applications/TLDR.app")

Task {
    var failed = false
    for id in identifiers {
        guard let type = UTType(id) else {
            print("✗ \(id): unknown type (run `make install` first so the app's types are registered)")
            failed = true
            continue
        }
        do {
            try await NSWorkspace.shared.setDefaultApplication(at: app, toOpen: type)
            print("✓ \(id) → \(app.lastPathComponent)")
        } catch {
            print("✗ \(id): \(error.localizedDescription)")
            failed = true
        }
    }
    exit(failed ? 1 : 0)
}
RunLoop.main.run()
