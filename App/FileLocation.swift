import AppKit

/// Where a document lives on disk: its path broken into clickable segments, plus the git
/// repository (if any) that contains it.
struct FileLocation: Equatable {
    struct Segment: Identifiable, Equatable {
        let id: Int
        let name: String
        let url: URL
        let isFile: Bool
        let isInRepo: Bool
        let isRepoRoot: Bool
    }

    let fileURL: URL
    let segments: [Segment]
    let repo: GitRepo?

    init(fileURL: URL) {
        let fileURL = fileURL.standardizedFileURL
        let repo = GitRepo.find(containing: fileURL)
        self.fileURL = fileURL
        self.repo = repo

        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path(percentEncoded: false)
        let path = fileURL.path(percentEncoded: false)
        let repoRoot = repo.map { $0.root.path(percentEncoded: false).removingSuffix("/") }

        var segments: [Segment] = []
        var current: String
        var rest: Substring
        if path.hasPrefix(home.removingSuffix("/") + "/") {
            current = home.removingSuffix("/")
            rest = path.dropFirst(current.count + 1)
            segments.append(.init(id: 0, name: "~", url: URL(filePath: current, directoryHint: .isDirectory),
                                  isFile: false, isInRepo: current == repoRoot, isRepoRoot: current == repoRoot))
        } else {
            current = ""
            rest = path.dropFirst()
            segments.append(.init(id: 0, name: "/", url: URL(filePath: "/", directoryHint: .isDirectory),
                                  isFile: false, isInRepo: repoRoot == "", isRepoRoot: repoRoot == ""))
        }
        let parts = rest.split(separator: "/")
        for (i, part) in parts.enumerated() {
            current += "/" + part
            let isFile = i == parts.count - 1
            let isInRepo = repoRoot.map { current == $0 || current.hasPrefix($0 + "/") } ?? false
            segments.append(.init(id: i + 1, name: String(part),
                                  url: URL(filePath: current, directoryHint: isFile ? .notDirectory : .isDirectory),
                                  isFile: isFile, isInRepo: isInRepo, isRepoRoot: current == repoRoot))
        }
        self.segments = segments
    }

    var directoryURL: URL { fileURL.deletingLastPathComponent() }

    var absolutePath: String { fileURL.path(percentEncoded: false) }

    /// Path relative to the repository root, or just the file name outside a repository.
    var relativePath: String {
        guard let repo else { return fileURL.lastPathComponent }
        let root = repo.root.path(percentEncoded: false).removingSuffix("/")
        return String(absolutePath.dropFirst(root.count + 1))
    }

    /// The file on the repository's web host (GitHub, GitLab, …) at the current HEAD.
    var webURL: URL? { repo?.webURL(for: relativePath) }
}

/// A git repository found by walking up from a file. Reads `.git` directly rather than
/// shelling out to `git`, so it's instant and works without developer tools installed.
struct GitRepo: Equatable {
    let root: URL
    /// Branch name, or a short commit hash when HEAD is detached.
    let head: String
    let isDetached: Bool
    /// Web page of the repository, derived from the `origin` remote.
    let remoteURL: URL?

    static func find(containing url: URL) -> GitRepo? {
        // Walk path strings, not URLs: `URL.deletingLastPathComponent()` on "/" yields "/../"
        // rather than stopping, which loops forever for files outside a repository.
        let fm = FileManager.default
        var dir = (url.standardizedFileURL.path(percentEncoded: false) as NSString).deletingLastPathComponent
        for _ in 0..<256 {
            let dotGit = (dir as NSString).appendingPathComponent(".git")
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: dotGit, isDirectory: &isDir) {
                return GitRepo(root: URL(filePath: dir, directoryHint: .isDirectory),
                               dotGit: URL(filePath: dotGit), isDirectory: isDir.boolValue)
            }
            if dir == "/" || dir.isEmpty { return nil }
            dir = (dir as NSString).deletingLastPathComponent
        }
        return nil
    }

    private init?(root: URL, dotGit: URL, isDirectory: Bool) {
        // Worktrees and submodules have a `.git` file pointing at the real git directory.
        var gitDir = dotGit
        if !isDirectory {
            guard let contents = try? String(contentsOf: dotGit, encoding: .utf8),
                  let line = contents.split(separator: "\n").first(where: { $0.hasPrefix("gitdir:") })
            else { return nil }
            let target = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
            gitDir = URL(filePath: target, relativeTo: root).standardizedFileURL
        }
        // Linked worktrees keep their own HEAD but share config with the main repository.
        var commonDir = gitDir
        if let common = try? String(contentsOf: gitDir.appending(path: "commondir"), encoding: .utf8) {
            commonDir = URL(filePath: common.trimmingCharacters(in: .whitespacesAndNewlines), relativeTo: gitDir)
                .standardizedFileURL
        }

        let headFile = (try? String(contentsOf: gitDir.appending(path: "HEAD"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if headFile.hasPrefix("ref:") {
            let ref = headFile.dropFirst("ref:".count).trimmingCharacters(in: .whitespaces)
            head = ref.hasPrefix("refs/heads/") ? String(ref.dropFirst("refs/heads/".count)) : ref
            isDetached = false
        } else {
            head = String(headFile.prefix(7))
            isDetached = true
        }

        self.root = root
        let config = try? String(contentsOf: commonDir.appending(path: "config"), encoding: .utf8)
        remoteURL = config.flatMap(GitRepo.originURL).flatMap(GitRepo.webURL(forRemote:))
    }

    func webURL(for relativePath: String) -> URL? {
        guard let remoteURL, !head.isEmpty else { return nil }
        let host = remoteURL.host() ?? ""
        let blob = host.contains("gitlab") ? ["-", "blob"] : host.contains("bitbucket") ? ["src"] : ["blob"]
        var url = remoteURL
        for component in blob + head.split(separator: "/").map(String.init) + relativePath.split(separator: "/").map(String.init) {
            url.append(path: component)
        }
        return url
    }

    /// The `url` of `[remote "origin"]` in a git config file.
    static func originURL(inConfig config: String) -> String? {
        var inOrigin = false
        for raw in config.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                inOrigin = line.replacingOccurrences(of: " ", with: "") == "[remote\"origin\"]"
            } else if inOrigin, line.hasPrefix("url") {
                let parts = line.split(separator: "=", maxSplits: 1)
                if parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == "url" {
                    return parts[1].trimmingCharacters(in: .whitespaces)
                }
            }
        }
        return nil
    }

    /// Turns `git@github.com:org/repo.git`, `ssh://git@host/org/repo` or
    /// `https://user@host/org/repo.git` into `https://host/org/repo`.
    static func webURL(forRemote remote: String) -> URL? {
        var host: String
        var path: String
        if let url = URL(string: remote), let scheme = url.scheme, ["https", "http", "ssh", "git"].contains(scheme),
           let urlHost = url.host() {
            host = urlHost
            path = url.path(percentEncoded: false)
        } else if let colon = remote.firstIndex(of: ":"), !remote.contains("://") {
            // scp-style: [user@]host:path
            host = String(remote[..<colon])
            if let at = host.lastIndex(of: "@") { host = String(host[host.index(after: at)...]) }
            path = String(remote[remote.index(after: colon)...])
        } else {
            return nil
        }
        path = path.removingPrefix("/").removingSuffix("/")
        if path.hasSuffix(".git") { path = String(path.dropLast(4)) }
        guard !host.isEmpty, !path.isEmpty else { return nil }
        return URL(string: "https://\(host)/\(path)")
    }
}

/// Apps a path can be handed to. The first installed one is the default; picking another
/// from a context menu or Settings makes it the default from then on.
struct ExternalApp: Identifiable, Hashable {
    enum Kind: String { case terminal, editor }

    let name: String
    let url: URL
    var id: String { name }

    private static let candidates: [Kind: [(name: String, bundleIDs: [String])]] = [
        .terminal: [
            ("Ghostty", ["com.mitchellh.ghostty"]),
            ("iTerm", ["com.googlecode.iterm2"]),
            ("Warp", ["dev.warp.Warp-Stable"]),
            ("Terminal", ["com.apple.Terminal"]),
        ],
        .editor: [
            ("Cursor", ["com.todesktop.230313mixed3cnvlo"]),
            ("Visual Studio Code", ["com.microsoft.VSCode"]),
            ("Windsurf", ["com.exafunction.windsurf"]),
            ("Zed", ["dev.zed.Zed"]),
            ("Sublime Text", ["com.sublimetext.4", "com.sublimetext.3"]),
            ("Nova", ["com.panic.Nova"]),
            ("BBEdit", ["com.barebones.bbedit"]),
            ("Xcode", ["com.apple.dt.Xcode"]),
        ],
    ]

    private static var cache: [Kind: [ExternalApp]] = [:]

    static func installed(_ kind: Kind) -> [ExternalApp] {
        if let cached = cache[kind] { return cached }
        let fm = FileManager.default
        let appDirs = ["/Applications", fm.homeDirectoryForCurrentUser.appending(path: "Applications").path(percentEncoded: false)]
        let apps = (candidates[kind] ?? []).compactMap { candidate -> ExternalApp? in
            for id in candidate.bundleIDs {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                    return ExternalApp(name: candidate.name, url: url)
                }
            }
            for dir in appDirs {
                let url = URL(filePath: dir).appending(path: candidate.name + ".app")
                if fm.fileExists(atPath: url.path(percentEncoded: false)) { return ExternalApp(name: candidate.name, url: url) }
            }
            return nil
        }
        cache[kind] = apps
        return apps
    }

    static func preferred(_ kind: Kind) -> ExternalApp? {
        let apps = installed(kind)
        let name = UserDefaults.standard.string(forKey: kind.rawValue)
        return apps.first { $0.name == name } ?? apps.first
    }

    func open(_ url: URL, as kind: Kind) {
        UserDefaults.standard.set(name, forKey: kind.rawValue)
        NSWorkspace.shared.open([url], withApplicationAt: self.url, configuration: NSWorkspace.OpenConfiguration())
    }

    var icon: NSImage {
        let image = NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
        image.size = NSSize(width: 16, height: 16)
        return image
    }
}

enum Pasteboard {
    static func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}

extension String {
    /// The path with the home directory abbreviated to `~`.
    var abbreviatingHome: String { (self as NSString).abbreviatingWithTildeInPath }

    /// Quoted for pasting into a POSIX shell.
    var shellQuoted: String {
        // Leave a leading `~/` outside the quotes so the shell still expands it.
        if hasPrefix("~/") { return "~/" + String(dropFirst(2)).shellQuoted }
        if !isEmpty && allSatisfy({ $0.isLetter || $0.isNumber || "/._-~+@%:,".contains($0) }) && !hasPrefix("~") { return self }
        return "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    func removingSuffix(_ suffix: String) -> String {
        hasSuffix(suffix) && count > suffix.count ? String(dropLast(suffix.count)) : self
    }

    func removingPrefix(_ prefix: String) -> String {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self
    }
}
