# TL;DR

Native macOS markdown viewer (`TLDR.app`): a standalone app for `.md` files plus a Quick Look extension
(select a file in Finder and press space).

- GitHub-flavoured markdown via Apple's [swift-markdown](https://github.com/swiftlang/swift-markdown)
  (cmark-gfm): tables, task lists, strikethrough, autolinks, GitHub alerts (`> [!NOTE]`)
- [Mermaid](https://mermaid.js.org) diagrams in ```` ```mermaid ```` blocks (bundled, works offline)
- Light/dark mode follows the system, diagrams included
- Relative images are inlined, YAML front matter is folded away
- App: live reload when the file changes on disk, zoom (⌘+ / ⌘- / ⌘0), print (⌘P),
  links to other `.md` files open in the app, web links open in the browser

## Build

Requires Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
make install   # build Release, copy to /Applications, register Quick Look extension
make default   # make it the default app for .md files
make test      # renderer unit tests
```

The Xcode project is generated from `project.yml` (`make project`); don't edit it by hand.

## Layout

- `Packages/MarkdownRenderer` — markdown → HTML page (shared by app and extension)
- `App/` — SwiftUI document-based viewer (WKWebView)
- `QuickLook/` — view-based Quick Look preview extension (sandboxed, WKWebView)

Note: Quick Look runs sandboxed and can only read the previewed file itself, so relative
images show in the app but not in the Quick Look preview.

Pages run under a Content-Security-Policy that only allows the bundled scripts
(served via the `tldr-resource:` scheme), so `<script>` in a markdown file never runs.
The Quick Look extension needs `network.client` because WebKit's content process
won't launch in a sandbox without it.

To update Mermaid (MIT licensed):

```sh
curl -fL https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js \
  -o Packages/MarkdownRenderer/Sources/MarkdownRenderer/Resources/mermaid.min.js
```

Debug log: `/usr/bin/log stream --level debug --predicate 'subsystem == "io.github.tlajer.tldr"'`
