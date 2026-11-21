import SwiftUI
import WebKit

/// macOS 15 needs a small bridge for local HTML Help; no scripting or remote navigation.
struct LocalHelpWebView: NSViewRepresentable {
    let url: URL
    func makeCoordinator() -> Adapter { Adapter(url: url) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.navigationDelegate = context.coordinator
        web.allowsMagnification = true
        web.setAccessibilityLabel(String(localized: "BrainDump Help"))
        web.setAccessibilityIdentifier("help.content")
        web.loadFileURL(url, allowingReadAccessTo: url)
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) { /* Preserve reading position and focus. */ }

    static func dismantleNSView(_ web: WKWebView, coordinator: Adapter) {
        web.stopLoading()
        web.navigationDelegate = nil
    }

    final class Adapter: NSObject, WKNavigationDelegate {
        let url: URL
        init(url: URL) { self.url = url }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let target = action.request.url, target.isFileURL,
                  target.standardizedFileURL.path == url.standardizedFileURL.path else { return .cancel }
            return .allow
        }
    }
}
