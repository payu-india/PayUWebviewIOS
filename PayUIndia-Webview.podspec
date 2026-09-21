Pod::Spec.new do |s|
  s.name             = 'PayUIndia-Webview'
  s.version          = '1.0.0'
  s.summary          = 'PayU checkout webview SDK for iOS apps.'
  s.description      = <<-DESC
PayUIndia-Webview provides a wrapper around WKWebView to simplify opening
PayU checkout, handling redirect flows, and capturing success/failure/error
callbacks in merchant iOS applications.
  DESC
  s.homepage         = 'https://github.com/payu-india/PayUWebviewIOS'
  s.license          = { :type => 'MIT', :text => 'Copyright (c) 2026 PayU. All rights reserved.' }
  s.author           = { 'PayU' => 'rishabh.jaiswal@payu.in' }
  s.source           = { :git => 'https://github.com/payu-india/PayUWebviewIOS.git', :tag => s.version.to_s }
  s.ios.deployment_target = '13.0'
  s.swift_versions   = ['5.0']

  s.source_files     = 'Sources/PayUWebView/**/*.{h,swift}'

  s.frameworks       = 'UIKit', 'WebKit'
  s.requires_arc     = true
end
