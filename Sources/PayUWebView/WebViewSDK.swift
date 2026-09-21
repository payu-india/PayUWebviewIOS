import UIKit
import WebKit

// MARK: - PayUDelegate

public protocol PayUDelegate: AnyObject {

    // MARK: Payment result callbacks (via PayU JS bridge)

    func payUonSuccess(_ message: WKScriptMessage)
    func payUonFailure(_ message: WKScriptMessage)
    func payUonError(_ message: WKScriptMessage)

    // MARK: Child-window support (netbanking / bank OTP popups)

    /// Called when a payment page calls `window.open(...)` to open a bank popup
    /// (e.g. netbanking redirect, OTP page).
    ///
    /// Your implementation must:
    ///   1. Create a `WKWebView` using **exactly** the `configuration` provided
    ///      — do NOT create a new `WKWebViewConfiguration`. WebKit puts the opener
    ///      context, cookies, and POST payload inside that configuration.
    ///   2. Present the web view in your UI (push/present a new view controller).
    ///   3. Return the created `WKWebView` so WebKit can load the bank page into it.
    ///
    /// Return `nil` to block the popup. Default: returns nil.
    func payUCreateChildWebView(configuration: WKWebViewConfiguration) -> WKWebView?

    /// Called when a child window executes `window.close()`.
    /// Dismiss or pop the view controller you presented in `payUCreateChildWebView`.
    /// Default: no-op.
    func payUChildWebViewDidClose()

    /// Fired as the web view loads content (progress is 0.0 → 1.0).
    /// Use this to drive a `UIProgressView` or similar indicator.
    /// Default: no-op.
    func payULoadingProgress(_ progress: Double)
}

// Default implementations — all three extra methods are optional for the host app.
public extension PayUDelegate {
    func payUCreateChildWebView(configuration: WKWebViewConfiguration) -> WKWebView? { nil }
    func payUChildWebViewDidClose() {}
    func payULoadingProgress(_ progress: Double) {}
}

// MARK: - WebViewSDK

public class WebViewSDK: NSObject, WKNavigationDelegate, WKScriptMessageHandler, WKUIDelegate {

    // MARK: - Public Properties

    public weak var webView: WKWebView?
    public weak var delegate: PayUDelegate?

    // MARK: - Private

    private var progressObservation: NSKeyValueObservation?

    // MARK: - Init

    public init(webView: WKWebView) {
        self.webView = webView
        super.init()

        // Assign delegates
        webView.navigationDelegate = self
        webView.uiDelegate = self

        // Required for payment gateway pages that open popups
        webView.configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        // Some bank OTP pages embed inline media
        webView.configuration.allowsInlineMediaPlayback = true

        // Register the PayU JS bridge ("observe" messages carry success/failure/error)
        webView.configuration.userContentController.add(self, name: "observe")

        // Inject window.open interceptor at document-start (runs before any page script):
        //   • Plain URL opens  → redirect in the same frame (no orphan window)
        //   • about:blank opens → let through so WebKit can POST form data into a child
        //     window via createWebViewWith (the netbanking pattern)
        let windowOpenScript = WKUserScript(
            source: """
            (function() {
                var _open = window.open.bind(window);
                window.open = function(url, target, features) {
                    if (!url || url === '' || url === 'about:blank') {
                        return _open(url, target, features);
                    }
                    window.location.href = url;
                };
            })();
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        webView.configuration.userContentController.addUserScript(windowOpenScript)

        // Forward loading progress to the delegate
        progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] _, change in
            guard let self, let progress = change.newValue else { return }
            self.delegate?.payULoadingProgress(progress)
        }
    }

    // MARK: - Public API

    /// Load the PayU payment page using an HTTP POST request.
    /// - Parameters:
    ///   - urlString: The PayU endpoint (e.g. `https://secure.payu.in/_payment`)
    ///   - postString: URL-encoded POST body containing all transaction parameters
    public func load(urlString: String, postString: String) {
        guard let url = URL(string: urlString) else {
            print("[PayUWebView] Invalid URL: \(urlString)")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = postString.data(using: .utf8)
        webView?.load(request)
    }

    // MARK: - Deinit

    deinit {
        progressObservation?.invalidate()
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "observe")
    }
}

// MARK: - WKNavigationDelegate

extension WebViewSDK: WKNavigationDelegate {

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Tell the PayU checkout page this is a handled webview (not a raw browser tab).
        // This enables intent-based deep-link handling on the PayU side.
        webView.evaluateJavaScript("sessionStorage.setItem('payuHandleIntent', 'true')") { _, error in
            if let error = error {
                print("[PayUWebView] sessionStorage error: \(error.localizedDescription)")
            }
        }
    }

    public func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        print("[PayUWebView] Navigation failed: \(error.localizedDescription)")
    }

    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        let scheme = url.scheme?.lowercased() ?? ""

        // Allow all standard web traffic.
        // IMPORTANT: Never reconstruct a URLRequest from just a URL — that strips
        // the POST body and breaks bank redirect chains (netbanking pattern).
        if ["https", "http", "about", "blob"].contains(scheme) {
            decisionHandler(.allow)
            return
        }

        // Hand off UPI / deep-link / app-switch URLs to the system
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
            decisionHandler(.cancel)
            return
        }

        // Intent URLs may carry a browser_fallback_url for devices without the target app
        if let fallbackRaw = url.absoluteString.components(separatedBy: "browser_fallback_url=").last,
           let decoded = fallbackRaw.removingPercentEncoding,
           let fallbackURL = URL(string: decoded),
           fallbackURL.absoluteString != url.absoluteString {
            webView.load(URLRequest(url: fallbackURL))
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }
}

// MARK: - WKScriptMessageHandler (PayU JS bridge)

extension WebViewSDK: WKScriptMessageHandler {

    public func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any] else { return }
        if body["onSuccess"] != nil {
            delegate?.payUonSuccess(message)
        } else if body["onFailure"] != nil {
            delegate?.payUonFailure(message)
        } else if body["onError"] != nil {
            delegate?.payUonError(message)
        }
    }
}

// MARK: - WKUIDelegate (JS dialogs + child windows)

extension WebViewSDK: WKUIDelegate {

    // MARK: JavaScript alert

    public func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        DispatchQueue.main.async {
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
            Self.presentFromKeyWindow(alert) { completionHandler() }
        }
    }

    // MARK: JavaScript confirm

    public func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        DispatchQueue.main.async {
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
            Self.presentFromKeyWindow(alert) { completionHandler(false) }
        }
    }

    // MARK: Child window creation (netbanking / bank OTP)

    /// PayU netbanking pattern:
    ///   1. Payment page JS calls `window.open('about:blank', 'bankWindow')`
    ///   2. WebKit calls this delegate method
    ///   3. We ask the host app to create a `WKWebView` using WebKit's configuration
    ///      (it carries the opener context, cookies, and POST payload)
    ///   4. The host presents that view; we return it so WebKit loads the bank page into it
    public func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        return delegate?.payUCreateChildWebView(configuration: configuration)
    }

    /// Called when JavaScript in the child window calls `window.close()`.
    /// The host app should dismiss/pop the view controller it presented.
    public func webViewDidClose(_ webView: WKWebView) {
        delegate?.payUChildWebViewDidClose()
    }

    // MARK: - Private helpers

    private static func presentFromKeyWindow(
        _ alert: UIAlertController,
        onMissingWindow: @escaping () -> Void
    ) {
        guard
            let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
            let root = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else {
            onMissingWindow()
            return
        }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        top.present(alert, animated: true)
    }
}
