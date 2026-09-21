#!/bin/bash

set -e

FRAMEWORK_NAME="PayUWebView"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${PROJECT_DIR}/build"
OUTPUT_DIR="${PROJECT_DIR}/output"

echo "🔨 Building ${FRAMEWORK_NAME}.xcframework..."
echo "Project directory: ${PROJECT_DIR}"

# Clean previous builds
rm -rf "${BUILD_DIR}"
rm -rf "${OUTPUT_DIR}"
mkdir -p "${BUILD_DIR}"
mkdir -p "${OUTPUT_DIR}"

# Build for iOS Device (arm64)
echo "📱 Building for iOS Device (arm64)..."
xcodebuild archive \
    -project "${PROJECT_DIR}/${FRAMEWORK_NAME}.xcodeproj" \
    -scheme "${FRAMEWORK_NAME}" \
    -destination "generic/platform=iOS" \
    -archivePath "${BUILD_DIR}/${FRAMEWORK_NAME}-iOS.xcarchive" \
    SKIP_INSTALL=NO \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
    ONLY_ACTIVE_ARCH=NO \
    | xcpretty || xcodebuild archive \
    -project "${PROJECT_DIR}/${FRAMEWORK_NAME}.xcodeproj" \
    -scheme "${FRAMEWORK_NAME}" \
    -destination "generic/platform=iOS" \
    -archivePath "${BUILD_DIR}/${FRAMEWORK_NAME}-iOS.xcarchive" \
    SKIP_INSTALL=NO \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
    ONLY_ACTIVE_ARCH=NO

# Build for iOS Simulator (arm64 + x86_64)
echo "🖥️  Building for iOS Simulator (arm64 + x86_64)..."
xcodebuild archive \
    -project "${PROJECT_DIR}/${FRAMEWORK_NAME}.xcodeproj" \
    -scheme "${FRAMEWORK_NAME}" \
    -destination "generic/platform=iOS Simulator" \
    -archivePath "${BUILD_DIR}/${FRAMEWORK_NAME}-Simulator.xcarchive" \
    SKIP_INSTALL=NO \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
    ONLY_ACTIVE_ARCH=NO \
    | xcpretty || xcodebuild archive \
    -project "${PROJECT_DIR}/${FRAMEWORK_NAME}.xcodeproj" \
    -scheme "${FRAMEWORK_NAME}" \
    -destination "generic/platform=iOS Simulator" \
    -archivePath "${BUILD_DIR}/${FRAMEWORK_NAME}-Simulator.xcarchive" \
    SKIP_INSTALL=NO \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
    ONLY_ACTIVE_ARCH=NO

# Create XCFramework
echo "📦 Creating XCFramework..."
xcodebuild -create-xcframework \
    -framework "${BUILD_DIR}/${FRAMEWORK_NAME}-iOS.xcarchive/Products/Library/Frameworks/${FRAMEWORK_NAME}.framework" \
    -framework "${BUILD_DIR}/${FRAMEWORK_NAME}-Simulator.xcarchive/Products/Library/Frameworks/${FRAMEWORK_NAME}.framework" \
    -output "${OUTPUT_DIR}/${FRAMEWORK_NAME}.xcframework"

# Clean up build artifacts
rm -rf "${BUILD_DIR}"

echo ""
echo "✅ Successfully created ${FRAMEWORK_NAME}.xcframework"
echo "📍 Location: ${OUTPUT_DIR}/${FRAMEWORK_NAME}.xcframework"
echo ""
echo "To use in another project:"
echo "  1. Drag ${FRAMEWORK_NAME}.xcframework into your Xcode project"
echo "  2. Ensure 'Embed & Sign' is selected in Frameworks settings"
