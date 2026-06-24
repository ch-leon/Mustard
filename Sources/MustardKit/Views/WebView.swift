import SwiftUI
import WebKit

/// Loading / navigation state for the embedded web view, observed by the panel.
@MainActor
@Observable
final class WebViewModel {
    var isLoading = false
    var loadFailed = false
    var canGoBack = false
    var canGoForward = false
    weak var webView: WKWebView?

    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }
    func reload() { webView?.reload() }
}

/// `WKWebView` wrapped for SwiftUI. Uses the shared persistent website data store
/// so a sign-in (e.g. Jira/Shortcut SSO) survives across launches.
struct WebView: NSViewRepresentable {
    let url: URL
    let model: WebViewModel

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        model.webView = view
        context.coordinator.lastRequested = url
        view.load(URLRequest(url: url))
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        model.webView = view
        guard context.coordinator.lastRequested != url else { return }
        context.coordinator.lastRequested = url
        view.load(URLRequest(url: url))
    }

    func makeCoordinator() -> Coordinator { Coordinator(model) }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        let model: WebViewModel
        var lastRequested: URL?
        init(_ model: WebViewModel) { self.model = model }

        func webView(_ w: WKWebView, didStartProvisionalNavigation n: WKNavigation!) {
            model.isLoading = true
            model.loadFailed = false
        }
        func webView(_ w: WKWebView, didFinish n: WKNavigation!) {
            model.isLoading = false
            model.canGoBack = w.canGoBack
            model.canGoForward = w.canGoForward
        }
        func webView(_ w: WKWebView, didFail n: WKNavigation!, withError e: Error) {
            failed(w)
        }
        func webView(_ w: WKWebView, didFailProvisionalNavigation n: WKNavigation!, withError e: Error) {
            failed(w)
        }
        private func failed(_ w: WKWebView) {
            model.isLoading = false
            model.loadFailed = true
            model.canGoBack = w.canGoBack
            model.canGoForward = w.canGoForward
        }
    }
}
