import SwiftUI

@main
struct TLDRApp: App {
    var body: some Scene {
        DocumentGroup(viewing: MarkdownFile.self) { file in
            DocumentView(initialText: file.document.text, fileURL: file.fileURL)
                .frame(minWidth: 480, minHeight: 360)
        }
        .defaultSize(width: 900, height: 1000)
        .commands {
            ViewerCommands()
        }

        Settings {
            SettingsView()
        }
    }
}

struct ViewerCommands: Commands {
    @FocusedValue(\.viewer) private var viewer
    @AppStorage("showPathBar") private var showPathBar = true

    private var location: FileLocation? { viewer?.location }

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button("Actual Size") { viewer?.setZoom(1) }
                .keyboardShortcut("0")
            Button("Zoom In") { viewer?.setZoom((viewer?.zoom ?? 1) + 0.1) }
                .keyboardShortcut("+")
            Button("Zoom Out") { viewer?.setZoom((viewer?.zoom ?? 1) - 0.1) }
                .keyboardShortcut("-")
            Divider()
            Button("Reload") { viewer?.reload() }
                .keyboardShortcut("r")
            Divider()
            Button(showPathBar ? "Hide Path Bar" : "Show Path Bar") { showPathBar.toggle() }
                .keyboardShortcut("p", modifiers: [.command, .option])
        }
        CommandMenu("Go") {
            Button("Copy Path") { location.map { Pasteboard.copy($0.absolutePath) } }
                .keyboardShortcut("c", modifiers: [.command, .option])
            Button("Copy Relative Path") { location.map { Pasteboard.copy($0.relativePath) } }
                .keyboardShortcut("c", modifiers: [.command, .option, .shift])
            Button("Copy cd Command") {
                location.map { Pasteboard.copy("cd \($0.directoryURL.path(percentEncoded: false).abbreviatingHome.removingSuffix("/").shellQuoted)") }
            }
            Divider()
            Button("Reveal in Finder") { location.map { NSWorkspace.shared.activateFileViewerSelecting([$0.fileURL]) } }
                .keyboardShortcut("r", modifiers: [.command, .option])
            Button("Open Folder in \(ExternalApp.preferred(.terminal)?.name ?? "Terminal")") {
                if let location { ExternalApp.preferred(.terminal)?.open(location.directoryURL, as: .terminal) }
            }
            .keyboardShortcut("t", modifiers: [.command, .option])
            .disabled(ExternalApp.preferred(.terminal) == nil)
            Button("Open in \(ExternalApp.preferred(.editor)?.name ?? "Editor")") {
                if let location { ExternalApp.preferred(.editor)?.open(location.fileURL, as: .editor) }
            }
            .keyboardShortcut("e", modifiers: [.command, .option])
            .disabled(ExternalApp.preferred(.editor) == nil)
            if let repo = location?.repo {
                Button("Open Repository in \(ExternalApp.preferred(.editor)?.name ?? "Editor")") {
                    ExternalApp.preferred(.editor)?.open(repo.root, as: .editor)
                }
                .keyboardShortcut("e", modifiers: [.command, .option, .shift])
                .disabled(ExternalApp.preferred(.editor) == nil)
            }
            Divider()
            Button("Open on \(location?.webURL.map(hostName) ?? "Web")") { location?.webURL.map { NSWorkspace.shared.open($0) } }
                .keyboardShortcut("g", modifiers: [.command, .option])
                .disabled(location?.webURL == nil)
            Button("Copy \(location?.webURL.map(hostName) ?? "Web") Link") { location?.webURL.map { Pasteboard.copy($0.absoluteString) } }
                .keyboardShortcut("g", modifiers: [.command, .option, .shift])
                .disabled(location?.webURL == nil)
        }
        CommandGroup(replacing: .printItem) {
            Button("Print…") { viewer?.print() }
                .keyboardShortcut("p")
                .disabled(viewer == nil)
        }
    }
}

struct SettingsView: View {
    @AppStorage("terminal") private var terminal = ExternalApp.preferred(.terminal)?.name ?? ""
    @AppStorage("editor") private var editor = ExternalApp.preferred(.editor)?.name ?? ""
    @AppStorage("showPathBar") private var showPathBar = true

    var body: some View {
        Form {
            Toggle("Show path bar", isOn: $showPathBar)
            picker("Terminal (⌘-click):", selection: $terminal, apps: ExternalApp.installed(.terminal))
            picker("Editor (⌥-click):", selection: $editor, apps: ExternalApp.installed(.editor))

            Section("Default app") {
                ForEach(FileTypeGroup.allCases) { group in
                    DefaultAppRow(group: group)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func picker(_ title: String, selection: Binding<String>, apps: [ExternalApp]) -> some View {
        Picker(title, selection: selection) {
            ForEach(apps) { app in
                Label { Text(app.name) } icon: { Image(nsImage: app.icon) }.tag(app.name)
            }
        }
        .disabled(apps.isEmpty)
    }
}

/// Shows whether TL;DR opens a group of file types on double-click, with a button to make it so.
private struct DefaultAppRow: View {
    let group: FileTypeGroup
    @State private var isDefault = false
    @State private var currentApp: String?
    @State private var error: String?

    var body: some View {
        LabeledContent {
            if isDefault {
                Label("Default", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Make Default") {
                    Task {
                        do {
                            try await group.makeDefault()
                            error = nil
                        } catch {
                            self.error = error.localizedDescription
                        }
                        refresh()
                    }
                }
            }
        } label: {
            Text(group.rawValue)
            Text(error ?? currentApp.map { "\(group.extensions) · opens in \($0)" } ?? group.extensions)
                .foregroundStyle(error == nil ? Color.secondary : Color.red)
        }
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }

    private func refresh() {
        isDefault = group.isDefault
        currentApp = group.currentApp
    }
}
