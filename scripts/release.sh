#!/usr/bin/env bash
set -e

VERSION=$1
CHANGELOG=$2

if [ -z "$VERSION" ]; then
  echo "Usage: ./scripts/release.sh <version> [changelog]"
  echo "Example: ./scripts/release.sh 1.0.1 'Google Drive auto sync & improvements'"
  exit 1
fi

if [ -z "$CHANGELOG" ]; then
  CHANGELOG="Version $VERSION release with latest performance improvements and updates."
fi

echo "======================================"
echo "🚀 Releasing Aegis v$VERSION"
echo "======================================"

# 1. Update version in pubspec.yaml
CURRENT_BUILD=$(grep -E '^version: ' pubspec.yaml | sed -E 's/.*\\+([0-9]+)/\\1/')
NEW_BUILD=$((CURRENT_BUILD + 1))
sed -i '' -E "s/^version: .*/version: $VERSION+$NEW_BUILD/" pubspec.yaml
echo "✅ Updated pubspec.yaml to version: $VERSION+$NEW_BUILD"

# 2. Build release APK
echo "🔨 Building release APK..."
~/.flutter/bin/flutter build apk --release
echo "✅ Release APK compiled: build/app/outputs/flutter-apk/app-release.apk"

# 3. Create tag and GitHub release
echo "📦 Uploading release to GitHub (RiyanshSingh/Aegis)..."
/opt/homebrew/bin/gh release create "v$VERSION" "build/app/outputs/flutter-apk/app-release.apk" \
  --title "Aegis v$VERSION" \
  --notes "$CHANGELOG"

echo "======================================"
echo "🎉 Update successfully published to GitHub!"
echo "Users will now automatically see the update prompt when opening the app!"
echo "======================================"
