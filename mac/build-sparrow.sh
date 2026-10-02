#!/bin/bash
# Builds Sparrow, installs it into /Applications and opens it.
# The full log is saved to build.log next to this script.
cd "$(dirname "$0")" || exit 1
LOG="build.log"
echo "🐦 Building Sparrow… (this takes 1–2 minutes)"
xcodebuild -project Sparrow.xcodeproj -scheme NotchBuddy -configuration Release \
  -derivedDataPath "$HOME/sparrow-build" \
  CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" PROVISIONING_PROFILE_SPECIFIER="" \
  build > "$LOG" 2>&1
if grep -q "BUILD SUCCEEDED" "$LOG"; then
  pkill -x Sparrow 2>/dev/null; pkill -x Coucou 2>/dev/null; sleep 1
  rm -rf /Applications/Sparrow.app
  cp -R "$HOME/sparrow-build/Build/Products/Release/Sparrow.app" /Applications/ && open /Applications/Sparrow.app
  echo "✅ Sparrow is installed in Applications and running."
else
  echo "❌ Build failed. Tell Claude — the details are in build.log."
  grep -E "error:" "$LOG" | head -20
fi
