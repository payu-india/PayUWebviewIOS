#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# PayUIndia-Webview — GitHub (SPM) + CocoaPods release script
# Run from the repo root:  bash release.sh
# ─────────────────────────────────────────────────────────────────────────────

set -e

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_DIR"

VERSION="1.0.2"
PODSPEC="PayUIndia-Webview.podspec"
TRUNK_EMAIL="integration@payu.in"

echo "▶ Repo:    $REPO_DIR"
echo "▶ Pod:     PayUIndia-Webview"
echo "▶ Version: $VERSION"
echo "▶ Trunk:   $TRUNK_EMAIL"
echo ""

# ── 1. Clear any stale git lock ───────────────────────────────────────────────
LOCK="$REPO_DIR/.git/index.lock"
if [ -f "$LOCK" ]; then
  echo "⚠️  Removing stale git lock file..."
  rm -f "$LOCK"
fi

# ── 2. Git identity ───────────────────────────────────────────────────────────
git config user.name  "PayU"
git config user.email "$TRUNK_EMAIL"

# ── 3. Stage files ────────────────────────────────────────────────────────────
echo "▶ Staging files..."
git add Sources/PayUWebView/WebViewSDK.swift
git add Sources/PayUWebView/PayUWebView.h
git add .gitignore
git add Package.swift
git add PayUIndia-Webview.podspec
git add release.sh
git status --short

# ── 4. Commit ─────────────────────────────────────────────────────────────────
echo ""
echo "▶ Committing..."
if git diff --cached --quiet; then
  echo "   Nothing new to commit — working tree is clean."
else
  git commit -m "chore: release PayUIndia-Webview $VERSION"
fi

# ── 5. Tag for SPM + CocoaPods ────────────────────────────────────────────────
echo ""
echo "▶ Creating tag $VERSION..."
git tag -d "$VERSION" 2>/dev/null || true          # remove local tag if re-releasing
git tag -a "$VERSION" -m "Release $VERSION"

# ── 6. Push branch + tag to GitHub ───────────────────────────────────────────
echo ""
echo "▶ Pushing to GitHub..."
git push origin main
git push origin "$VERSION"

echo ""
echo "✅ GitHub push done. SPM consumers can now use:"
echo "   .package(url: \"https://github.com/payu-india/PayUWebviewIOS.git\", from: \"$VERSION\")"
echo "   // then in your target: .product(name: \"PayUIndiaWebview\", package: \"PayUIndiaWebview\")"

# ── 7. CocoaPods trunk push ───────────────────────────────────────────────────
echo ""
echo "▶ Checking CocoaPods trunk session for $TRUNK_EMAIL..."
if ! pod trunk me 2>&1 | grep -qi "$TRUNK_EMAIL"; then
  echo ""
  echo "⚠️  No active trunk session found for $TRUNK_EMAIL."
  echo "    Register with:"
  echo ""
  echo "    pod trunk register $TRUNK_EMAIL 'PayU' --description='Release machine'"
  echo ""
  echo "    Open the confirmation link sent to $TRUNK_EMAIL, then re-run: bash release.sh"
  echo "    (Git steps above are already done — the script will skip to the pod push.)"
  exit 1
fi

echo ""
echo "▶ Linting podspec..."
pod spec lint "$PODSPEC" --allow-warnings

echo ""
echo "▶ Pushing to CocoaPods trunk as $TRUNK_EMAIL..."
pod trunk push "$PODSPEC" --allow-warnings

echo ""
echo "✅ CocoaPods release done. Consumers can now use:"
echo "   pod 'PayUIndia-Webview', '~> $VERSION'"
