import SwiftUI

/// Breadcrumb of the document's path. Every folder is clickable:
///
/// - click: open in Finder (the file itself: reveal in Finder)
/// - ⌘-click: open in the terminal
/// - ⌥-click: open in the editor
/// - ⇧-click: copy the path
/// - right-click: everything else; drag: drop the path into a terminal or editor
struct PathBar: View {
    let location: FileLocation
    @State private var hovered: Int?
    @State private var toast: String?
    @State private var toastTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(location.segments) { segment in
                            if segment.id > 0, location.segments[segment.id - 1].name != "/" {
                                Text("/").foregroundStyle(.tertiary)
                            }
                            segmentButton(segment).id(segment.id)
                        }
                    }
                    .padding(.horizontal, 6)
                }
                .onAppear { proxy.scrollTo(location.segments.last?.id, anchor: .trailing) }
                .onChange(of: location) { proxy.scrollTo(location.segments.last?.id, anchor: .trailing) }
            }

            if let toast {
                Label(toast, systemImage: "checkmark")
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
            if let repo = location.repo {
                BranchBadge(repo: repo, location: location, notify: notify)
            }
        }
        .font(.system(size: 11.5, design: .monospaced))
        .lineLimit(1)
        .padding(.horizontal, 6)
        .frame(height: 26)
        .background(.bar)
    }

    private func segmentButton(_ segment: FileLocation.Segment) -> some View {
        Button {
            click(segment, modifiers: NSEvent.modifierFlags)
        } label: {
            Text(segment.name)
                .fontWeight(segment.isFile || segment.isRepoRoot ? .semibold : .regular)
                .foregroundStyle(color(for: segment))
                .padding(.horizontal, 3)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(hovered == segment.id ? Color.primary.opacity(0.1) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in hovered = inside ? segment.id : (hovered == segment.id ? nil : hovered) }
        .onDrag { NSItemProvider(object: segment.url as NSURL) }
        .help(tooltip(for: segment))
        .contextMenu { menu(for: segment) }
    }

    private func color(for segment: FileLocation.Segment) -> AnyShapeStyle {
        if segment.isFile { return AnyShapeStyle(.tint) }
        if location.repo != nil && !segment.isInRepo { return AnyShapeStyle(.secondary) }
        return AnyShapeStyle(.primary)
    }

    private func tooltip(for segment: FileLocation.Segment) -> String {
        let path = segment.url.path(percentEncoded: false).abbreviatingHome
        let terminal = ExternalApp.preferred(.terminal)?.name ?? "Terminal"
        let editor = ExternalApp.preferred(.editor)?.name ?? "editor"
        let finder = segment.isFile ? "reveal in Finder" : "Finder"
        return "\(path)\nclick \(finder) · ⌘ \(terminal) · ⌥ \(editor) · ⇧ copy path"
    }

    // MARK: Actions

    private func click(_ segment: FileLocation.Segment, modifiers: NSEvent.ModifierFlags) {
        let folder = segment.isFile ? location.directoryURL : segment.url
        if modifiers.contains(.shift) {
            copy(segment.url.path(percentEncoded: false), "path")
        } else if modifiers.contains(.command) {
            ExternalApp.preferred(.terminal)?.open(folder, as: .terminal)
        } else if modifiers.contains(.option) {
            ExternalApp.preferred(.editor)?.open(segment.url, as: .editor)
        } else if segment.isFile {
            NSWorkspace.shared.activateFileViewerSelecting([segment.url])
        } else {
            NSWorkspace.shared.open(segment.url)
        }
    }

    private func copy(_ string: String, _ what: String) {
        Pasteboard.copy(string)
        notify("copied \(what)")
    }

    private func notify(_ message: String) {
        toastTask?.cancel()
        withAnimation(.easeOut(duration: 0.15)) { toast = message }
        toastTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.3)) { toast = nil }
        }
    }

    @ViewBuilder
    private func menu(for segment: FileLocation.Segment) -> some View {
        let path = segment.url.path(percentEncoded: false)
        let folder = segment.isFile ? location.directoryURL : segment.url

        if segment.isFile {
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([segment.url]) }
        } else {
            Button("Open in Finder") { NSWorkspace.shared.open(segment.url) }
        }
        ForEach(ExternalApp.installed(.terminal)) { app in
            Button { app.open(folder, as: .terminal) } label: {
                Label { Text("Open \(segment.isFile ? "Folder " : "")in \(app.name)") } icon: { Image(nsImage: app.icon) }
            }
        }
        ForEach(ExternalApp.installed(.editor)) { app in
            Button { app.open(segment.url, as: .editor) } label: {
                Label { Text("Open in \(app.name)") } icon: { Image(nsImage: app.icon) }
            }
        }

        Divider()

        Button("Copy Path") { copy(path, "path") }
        Button("Copy ~ Path") { copy(path.abbreviatingHome, "~ path") }
        if let repo = location.repo, segment.isInRepo {
            let root = repo.root.path(percentEncoded: false).removingSuffix("/")
            let relative = segment.isRepoRoot ? "." : String(path.dropFirst(root.count + 1))
            Button("Copy Relative Path") { copy(relative, "relative path") }
        }
        if segment.isFile {
            Button("Copy File Name") { copy(segment.name, "file name") }
        } else {
            Button("Copy cd Command") { copy("cd \(path.abbreviatingHome.shellQuoted)", "cd command") }
        }
        if segment.isInRepo, let url = location.repo?.webURL(for: relativePath(of: segment)) {
            Divider()
            Button("Open on \(hostName(url))") { NSWorkspace.shared.open(url) }
            Button("Copy \(hostName(url)) Link") { copy(url.absoluteString, "link") }
        }
    }

    private func relativePath(of segment: FileLocation.Segment) -> String {
        guard let repo = location.repo, !segment.isRepoRoot else { return "" }
        let root = repo.root.path(percentEncoded: false).removingSuffix("/")
        return String(segment.url.path(percentEncoded: false).dropFirst(root.count + 1))
    }
}

func hostName(_ url: URL) -> String {
    let host = url.host() ?? ""
    if host.contains("github") { return "GitHub" }
    if host.contains("gitlab") { return "GitLab" }
    if host.contains("bitbucket") { return "Bitbucket" }
    return host
}

private struct BranchBadge: View {
    let repo: GitRepo
    let location: FileLocation
    let notify: (String) -> Void

    var body: some View {
        Button {
            if NSEvent.modifierFlags.contains(.command), let url = location.webURL {
                NSWorkspace.shared.open(url)
            } else {
                Pasteboard.copy(repo.head)
                notify("copied branch")
            }
        } label: {
            Label(repo.head, systemImage: repo.isDetached ? "smallcircle.filled.circle" : "arrow.triangle.branch")
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.primary.opacity(0.08)))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help(help)
        .contextMenu {
            Button("Copy Branch Name") { Pasteboard.copy(repo.head); notify("copied branch") }
            if let url = location.webURL {
                Button("Open File on \(hostName(url))") { NSWorkspace.shared.open(url) }
                Button("Copy \(hostName(url)) Link") { Pasteboard.copy(url.absoluteString); notify("copied link") }
            }
            if let remote = repo.remoteURL {
                Button("Open Repository on \(hostName(remote))") { NSWorkspace.shared.open(remote) }
            }
        }
    }

    private var help: String {
        var lines = [(repo.isDetached ? "detached HEAD " : "branch ") + repo.head,
                     "repo " + repo.root.path(percentEncoded: false).abbreviatingHome.removingSuffix("/")]
        lines.append(location.webURL.map { "click copy · ⌘ open on \(hostName($0))" } ?? "click copy branch name")
        return lines.joined(separator: "\n")
    }
}
