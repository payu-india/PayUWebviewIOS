#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# PayUWebviewIOS — GitHub (SPM) + CocoaPods release script
# Run from the repo root:  bash release.sh
# ─────────────────────────────────────────────────────────────────────────────

set -e

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_DIR"

VERSION="1.0.0"
PODSPEC="PayUWebView.podspec"

echo "▶ Repo: $REPO_DIR"
echo "▶ Version: $VERSION"
echo ""

# ── 1. Clear any stale git lock ───────────────────────────────────────────────
LOCK="$REPO_DIR/.git/index.lock"
if [ -f "$LOCK" ]; then
  echo "⚠️  Removing stale git lock file..."
  rm -f "$LOCK"
fi

# ── 2. Git identity ───────────────────────────────────────────────────────────
git config user.name  "PayU"
git config user.email "Integration@payu.in"

# ── 3. Stage only source + gitignore + podspec (skip Xcode user-data, DS_Store) ──
echo "▶ Staging files..."
git add Sources/PayUWebView/WebViewSDK.swift
git add .gitignore
git add PayUWebView.podspec
git status --short

# ── 4. Commit ─────────────────────────────────────────────────────────────────
echo ""
echo "▶ Committing..."
git commit -m "feat: append sdkInfo telemetry to payment POST body"

# ── 5. Tag for SPM + CocoaPods ────────────────────────────────────────────────
echo ""
echo "▶ Creating tag $VERSION..."
# Delete local tag if it already exists (re-release scenario)
git tag -d "$VERSION" 2>/dev/null || true
git tag -a "$VERSION" -m "Release $VERSION"

# ── 6. Push branch + tag to GitHub (SPM consumers resolve via the tag) ────────
echo ""
echo "▶ Pushing to GitHub..."
git push origin main
git push origin "$VERSION"

echo ""
echo "✅ GitHub push done. SPM consumers can now use:"
echo "   .package(url: \"https://github.com/payu-india/PayUWebviewIOS.git\", from: \"$VERSION\")"

# ── 7. CocoaPods trunk push ───────────────────────────────────────────────────
TRUNK_EMAIL="Integration@payu.in"

# Check whether a trunk session already exists for this email
echo ""
echo "▶ Checking CocoaPods trunk session for $TRUNK_EMAIL..."
if ! pod trunk me 2>&1 | grep -q "$TRUNK_EMAIL"; then
  echo ""
  echo "⚠️  No active trunk session found for $TRUNK_EMAIL."
  echo "    Run the following command, then check $TRUNK_EMAIL for the confirmation link:"
  echo ""
  echo "    pod trunk register $TRUNK_EMAIL 'PayU' --description='Release machine'"
  echo ""
  echo "    After confirming, re-run:  bash release.sh"
  echo "    (The script will skip the already-pushed git steps and go straight to pod push.)"
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
echo "   pod 'PayUWebView', '~> $VERSION'"
