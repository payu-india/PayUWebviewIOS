
import UIKit
import WebKit

public protocol PayUDelegate: AnyObject {
    func payUonSuccess(_ message: WKScriptMessage)
    func payUonFailure(_ message: WKScriptMessage)
    func payUonError(_ message: WKScriptMessage)
}

public class WebViewSDK: NSObject, WKNavigationDelegate, WKScriptMessageHandler, WKUIDelegate {
    public weak var webView: WKWebView?
    public weak var delegate: PayUDelegate?

    public init(webView: WKWebView) {
        self.webView = webView
        super.init()
        self.webView?.navigationDelegate = self
        self.webView?.uiDelegate = self
        self.webView?.configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        let userContentController = webView.configuration.userContentController
        userContentController.add(self, name: "observe")
    }

    public func load(urlString: String, postString: String) {
        guard let url = URL(string: urlString) else {
            print("Invalid URL string: \(urlString)")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = postString.data(using: .utf8)
        self.webView?.load(request)
    }

    deinit {
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "observe")
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript("sessionStorage.setItem('payuHandleIntent', 'true')") { _, error in
            if let error = error {
                print("Error setting session storage: \(error.localizedDescription)")
            } else {
                print("Successfully set value in session storage")
            }
        }
    }

    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if let url = navigationAction.request.url,
           !url.absoluteString.hasPrefix("http://"),
           !url.absoluteString.hasPrefix("https://") {
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
                decisionHandler(.cancel)
                return
            } else if url.absoluteString.contains("browser_fallback_url=") {
                let fallbackURLString = url.absoluteString.components(separatedBy: "browser_fallback_url=").last
                let fallbackURL = URL(string: fallbackURLString?.removingPercentEncoding ?? "")
                if fallbackURL != nil, url.absoluteString != fallbackURLString {
                    if url.absoluteString != fallbackURLString {
                        webView.load(URLRequest(url: fallbackURL!))
                        decisionHandler(.cancel)
                        return
                    }
                }
                decisionHandler(.allow)
                return
            }
        }
        decisionHandler(.allow)
    }

    public func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        DispatchQueue.main.async {
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
                completionHandler()
            }))
            Self.presentFromKeyWindow(alert) {
                completionHandler()
            }
        }
    }

    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        print(message.body)
        print(message.name)
        guard let body = message.body as? [String: Any] else { return }
        if body["onSuccess"] != nil {
            delegate?.payUonSuccess(message)
        } else if body["onFailure"] != nil {
            delegate?.payUonFailure(message)
        } else if body["onError"] != nil {
            delegate?.payUonError(message)
        }
    }

    public func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        DispatchQueue.main.async {
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
                completionHandler(true)
            }))
            alert.addAction(UIAlertAction(title: "Cancel", style: .default, handler: { _ in
                completionHandler(false)
            }))
            Self.presentFromKeyWindow(alert) {
                completionHandler(false)
            }
        }
    }

    private static func presentFromKeyWindow(_ alert: UIAlertController, onMissingWindow: @escaping () -> Void) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            onMissingWindow()
            return
        }
        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        top.present(alert, animated: true)
    }
}
