#!/bin/bash
set -euo pipefail

# Xcode Cloud post-clone script
# Installs XcodeGen and generates the Xcode project so that
# Xcode Cloud can build the BlipAppStore scheme for MAS distribution.

echo "=== Blip: Xcode Cloud Post-Clone ==="

# Install XcodeGen via Homebrew
echo "Installing XcodeGen..."
brew install xcodegen

# Generate the Xcode project
echo "Generating Xcode project..."
cd "$CI_PRIMARY_REPOSITORY_PATH"
xcodegen generate

echo "=== Xcode project generated successfully ==="

# Generate app icon assets (needed for release builds)
if [ -f "Scripts/generate-assets.swift" ]; then
    echo "Generating app icon assets..."
    mkdir -p .build/assets
    swift Scripts/generate-assets.swift .build/assets

    # Copy generated icon into asset catalog if needed
    if [ -d ".build/assets/Blip.iconset" ]; then
        ICONSET_DIR="Blip/Resources/Assets.xcassets/AppIcon.appiconset"
        if [ -d "$ICONSET_DIR" ]; then
            cp .build/assets/Blip.iconset/*.png "$ICONSET_DIR/" 2>/dev/null || true
            echo "App icon assets updated."
        fi
    fi
fi

echo "=== Post-clone complete ==="
