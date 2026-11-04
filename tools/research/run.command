#!/bin/zsh
set -eu
RESEARCH_ROOT="${0:A:h:h:h}"
RESEARCH_BUILD="$RESEARCH_ROOT/.research-build"
RESEARCH_APP="$RESEARCH_BUILD/BuddyResearch.app"
mkdir -p "$RESEARCH_APP/Contents/MacOS" "$RESEARCH_ROOT/research-data"
export CLANG_MODULE_CACHE_PATH="$RESEARCH_BUILD/module-cache"
export BUDDY_RESEARCH_DATA="$RESEARCH_ROOT/research-data"
swiftc -swift-version 6 -parse-as-library \
  "$RESEARCH_ROOT/tools/research/ResearchConsole.swift" \
  "$RESEARCH_ROOT/DesktopBuddy/Core/Models/ForegroundActivitySnapshot.swift" \
  "$RESEARCH_ROOT/DesktopBuddy/Core/Protocols/ForegroundActivitySensing.swift" \
  "$RESEARCH_ROOT/DesktopBuddy/Core/Protocols/FullscreenSensing.swift" \
  "$RESEARCH_ROOT/DesktopBuddy/Core/DecisionEngine/FocusActivityTracker.swift" \
  "$RESEARCH_ROOT/DesktopBuddy/Core/DecisionEngine/FullscreenPresentationPolicy.swift" \
  "$RESEARCH_ROOT/DesktopBuddy/Platform/macOS/Activity/SystemForegroundActivitySensor.swift" \
  "$RESEARCH_ROOT/DesktopBuddy/Platform/macOS/Activity/ForegroundFullscreenSensor.swift" \
  -o "$RESEARCH_APP/Contents/MacOS/BuddyResearch"
cat > "$RESEARCH_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>BuddyResearch</string>
<key>CFBundleIdentifier</key><string>com.desktopbuddy.research</string>
<key>CFBundleName</key><string>Buddy Research</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
if [[ "${1:-}" != "--build-only" ]]; then
  exec "$RESEARCH_APP/Contents/MacOS/BuddyResearch"
fi
