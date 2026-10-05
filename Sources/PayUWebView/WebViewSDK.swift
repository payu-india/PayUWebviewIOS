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
    /// Return `nil` to let the SDK handle it internally with a default full-screen modal.
    func payUCreateChildWebView(configuration: WKWebViewConfiguration) -> WKWebView?

    /// Called when a child window executes `window.close()`.
    /// Dismiss or pop the view controller you presented in `payUCreateChildWebView`.
    /// If you rely on the SDK's internal fallback, this is a no-op — the SDK dismisses it.
    func payUChildWebViewDidClose()

    /// Fired as the web view loads content (progress is 0.0 → 1.0).
    /// Use this to drive a `UIProgressView` or similar indicator.
    func payULoadingProgress(_ progress: Double)
}

// Default implementations — all extra methods are optional for the host app.
public extension PayUDelegate {
    func payUCreateChildWebView(configuration: WKWebViewConfiguration) -> WKWebView? { nil }
    func payUChildWebViewDidClose() {}
    func payULoadingProgress(_ progress: Double) {}
}

// MARK: - WebViewSDK

public class WebViewSDK: NSObject {

    // MARK: - Public Properties

    public weak var webView: WKWebView?
    public weak var delegate: PayUDelegate?

    // MARK: - Private

    private var progressObservation: NSKeyValueObservation?
    /// Tracks the internally-presented child view controller so we can dismiss it on window.close()
    private weak var internalChildNavController: UINavigationController?

    // MARK: - Init

    public init(webView: WKWebView) {
        self.webView = webView
        super.init()

        // Assign delegates
        webView.navigationDelegate = self
        webView.uiDelegate = self

        // Required for payment gateway pages that open popups (window.open triggers createWebViewWith)
        webView.configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        // Some bank OTP pages embed inline media
        webView.configuration.allowsInlineMediaPlayback = true

        // Register the PayU JS bridge ("observe" messages carry success/failure/error)
        webView.configuration.userContentController.add(self, name: "observe")

        // Inject window.open interceptor at document-start (runs before any page script):
        //   • about:blank or empty URL → let through so WebKit handles POST-based bank popups
        //     via createWebViewWith (the standard PayU netbanking pattern)
        //   • plain URL opens → navigate in the same frame to avoid orphan windows
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
        let sdkInfo = "[{\"platform\":\"ios\",\"name\":\"WebViewSDK\",\"version\":\"1.0.0\"}]"
        let encodedSdkInfo = sdkInfo.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? sdkInfo
        let fullPostString = postString + "&sdkInfo=\(encodedSdkInfo)"
        request.httpBody = fullPostString.data(using: .utf8)
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
            Self.presentAlert(alert) { completionHandler() }
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
            Self.presentAlert(alert) { completionHandler(false) }
        }
    }

    // MARK: Child window creation (netbanking / bank OTP)

    /// PayU netbanking pattern:
    ///   1. Payment page JS calls `window.open('about:blank', 'bankWindow')`
    ///   2. WebKit calls this delegate
    ///   3. We ask the host app to supply a child WKWebView (using WebKit's configuration).
    ///      If the host returns nil, the SDK falls back to an internal full-screen modal.
    ///   4. WebKit loads the bank page (including POST body) into the returned WKWebView.
    public func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        // 1. Ask the host app first
        if let hostProvidedView = delegate?.payUCreateChildWebView(configuration: configuration) {
            return hostProvidedView
        }

        // 2. Fallback: SDK presents an internal full-screen modal with the child web view.
        //    We MUST use the exact `configuration` WebKit provides — it carries the opener's
        //    browsing context, session cookies, and POST payload.
        let childVC = PayUChildWebViewController(configuration: configuration)
        childVC.onClose = { [weak self] in
            self?.internalChildNavController?.dismiss(animated: true)
            self?.internalChildNavController = nil
        }

        let nav = UINavigationController(rootViewController: childVC)
        nav.modalPresentationStyle = .fullScreen
        internalChildNavController = nav

        DispatchQueue.main.async {
            Self.topViewController()?.present(nav, animated: true)
        }

        return childVC.webView
    }

    /// Called when JavaScript in the child window calls `window.close()`.
    public func webViewDidClose(_ webView: WKWebView) {
        // Notify host app (in case it presented its own child VC)
        delegate?.payUChildWebViewDidClose()

        // Dismiss the SDK's internal modal if it was used
        internalChildNavController?.dismiss(animated: true)
        internalChildNavController = nil
    }

    // MARK: - Private helpers

    /// Present an alert on the topmost view controller.
    private static func presentAlert(
        _ alert: UIAlertController,
        onMissingWindow: @escaping () -> Void
    ) {
        guard let top = topViewController() else {
            onMissingWindow()
            return
        }
        top.present(alert, animated: true)
    }

    /// Walk the view hierarchy to find the topmost presented view controller.
    private static func topViewController() -> UIViewController? {
        guard
            let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
            let root = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else { return nil }

        var top = root
        while let presented = top.presentedViewController { top = presented }
        return top
    }
}

// MARK: - PayUChildWebViewController (internal fallback for child windows)

/// A lightweight view controller used internally by WebViewSDK to host a
/// netbanking / bank OTP child window when the host app doesn't implement
/// `payUCreateChildWebView`. Not intended for direct use.
private class PayUChildWebViewController: UIViewController {

    // The WKWebView returned to WebKit — created with WebKit's own configuration
    // so it inherits the opener's context, cookies, and POST payload.
    let webView: WKWebView

    var onClose: (() -> Void)?

    private var progressView: UIProgressView!
    private var progressObservation: NSKeyValueObservation?

    init(configuration: WKWebViewConfiguration) {
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupWebView()
        setupNavigationBar()
    }

    private func setupWebView() {
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)

        progressView = UIProgressView(progressViewStyle: .default)
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.tintColor = UIColor(red: 0.18, green: 0.49, blue: 0.86, alpha: 1.0)
        view.addSubview(progressView)

        NSLayoutConstraint.activate([
            progressView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progressView.heightAnchor.constraint(equalToConstant: 2),

            webView.topAnchor.constraint(equalTo: progressView.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] _, change in
            guard let self, let progress = change.newValue else { return }
            self.progressView.setProgress(Float(progress), animated: true)
            self.progressView.isHidden = progress >= 1.0
        }
    }

    private func setupNavigationBar() {
        navigationController?.navigationBar.tintColor = UIColor(red: 0.18, green: 0.49, blue: 0.86, alpha: 1.0)
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "xmark"),
            style: .plain,
            target: self,
            action: #selector(closeTapped)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "arrow.clockwise"),
            style: .plain,
            target: self,
            action: #selector(refreshTapped)
        )
    }

    @objc private func closeTapped() {
        onClose?()
    }

    @objc private func refreshTapped() {
        webView.reload()
    }

    deinit {
        progressObservation?.invalidate()
    }
}
