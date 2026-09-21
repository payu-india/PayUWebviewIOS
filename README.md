# PayUWebView

PayUWebView is an iOS SDK wrapper around `WKWebView` to open PayU checkout and handle payment callbacks.

## Installation

### Swift Package Manager (SPM)

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/payu-intrepos/PayUWebView-iOS.git", from: "1.0.0")
]
```

Or in Xcode:
1. Go to **File → Add Package Dependencies...**
2. Enter: `https://github.com/payu-intrepos/PayUWebView-iOS.git`
3. Select version `1.0.0` or later

### CocoaPods

Add to your `Podfile`:

```ruby
pod 'PayUWebView', '~> 1.0'
```

Then run:

```bash
pod install
```

### XCFramework (Manual)

1. Download `PayUWebView.xcframework` from releases
2. Drag it into your Xcode project
3. Select **Embed & Sign** in target settings

## Usage

```swift
import PayUWebView
import WebKit

class ViewController: UIViewController, PayUDelegate {
    var webViewManager: WebViewSDK?
    @IBOutlet weak var webView: WKWebView!

    override func viewDidLoad() {
        super.viewDidLoad()
        webViewManager = WebViewSDK(webView: webView)
        webViewManager?.delegate = self
        webViewManager?.load(urlString: "https://secure.payu.in/_payment", postString: "your_post_params")
    }

    func payUonSuccess(_ message: WKScriptMessage) {
        print("Payment Success: \(message.body)")
    }

    func payUonFailure(_ message: WKScriptMessage) {
        print("Payment Failed: \(message.body)")
    }

    func payUonError(_ message: WKScriptMessage) {
        print("Payment Error: \(message.body)")
    }
}
```

## Requirements

- iOS 13.0+
- Swift 5.0+
- Xcode 14.0+

## Release Checklist

1. Update version in `Package.swift`, `PayUWebView.podspec`
2. Tag the version in git: `git tag 1.0.0 && git push --tags`
3. Validate CocoaPods: `pod lib lint PayUWebView.podspec --allow-warnings`
4. Push to CocoaPods: `pod trunk push PayUWebView.podspec --allow-warnings`

## License

Copyright (c) PayU. All rights reserved.
