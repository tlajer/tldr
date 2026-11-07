import Foundation
import OSLog
import UniformTypeIdentifiers
import WebKit

/// Shared WKWebView setup for the app and the Quick Look extension.
public enum PreviewWebKit {
    /// Bundled scripts are served from `tldr-resource://local/<file>`.
    static let scheme = "tldr-resource"
    static let logger = Logger(subsystem: "io.github.tlajer.tldr", category: "webview")

    public static func makeConfiguration() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(ResourceSchemeHandler(), forURLScheme: scheme)
        config.userContentController.add(MessageLogger(), name: "tldr")
        return config
    }

    static func resourceURL(_ name: String) -> String {
        "\(scheme)://local/\(name)"
    }
}

private final class ResourceSchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url,
              let file = Bundle.module.url(forResource: url.lastPathComponent, withExtension: nil),
              let data = try? Data(contentsOf: file) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let mime = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        task.didReceive(URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: "utf-8"))
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

/// Handles messages from page scripts: `{copy: text}` puts text on the pasteboard (the
/// async clipboard API isn't available to pages loaded with loadHTMLString); anything else is logged.
private final class MessageLogger: NSObject, WKScriptMessageHandler {
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        if let body = message.body as? [String: Any], let text = body["copy"] as? String {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            return
        }
        PreviewWebKit.logger.debug("\(String(describing: message.body), privacy: .public)")
    }
}
