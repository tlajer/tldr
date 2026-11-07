// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MarkdownRenderer",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MarkdownRenderer", targets: ["MarkdownRenderer"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.5.0"),
    ],
    targets: [
        .target(
            name: "MarkdownRenderer",
            dependencies: [.product(name: "Markdown", package: "swift-markdown")],
            resources: [.copy("Resources/mermaid.min.js"), .copy("Resources/mermaid-init.js"), .copy("Resources/data-view.js")]
        ),
        .testTarget(name: "MarkdownRendererTests", dependencies: ["MarkdownRenderer"]),
    ]
)
