# macOS App Rebuild Guide

This document explains how to rebuild the `ForeverDiaryMac.app` from scratch.

---

## Key Facts

| Item | Value |
|------|-------|
| Bundle ID | `com.foreverdiary.mac` |
| Signing Identity | `Apple Development: mr.kennethsolomon@gmail.com (XU4F3HX58C)` |
| Team ID | `CL4Z3C7CSV` |
| Deployment Target | macOS 14.0 |
| Output | `~/Desktop/ForeverDiaryMacBuild/ForeverDiaryMac.zip` |

**Verify signing identity is still valid before building:**
```bash
security find-identity -v -p codesigning
```

---

## Why the Source Files May Be Missing

`ForeverDiaryMac/` is **not committed to git**. The directory only exists locally. If you're on a new machine or the directory was deleted, you must recreate it before building.

The macOS target reuses shared code from:
- `ForeverDiary/Models/` — SwiftData models
- `ForeverDiary/Services/` — SyncService, APIClient, CognitoAuthService, etc.

It does NOT duplicate those files. Only the UI files in `ForeverDiaryMac/` are macOS-specific.

---

## Source File List

These 12 Swift files must exist in `ForeverDiaryMac/`:

```
ForeverDiaryMac/
├── App/
│   └── ForeverDiaryMacApp.swift       ← @main entry point
├── AppTheme.swift                     ← enum AppTheme (system/light/dark)
├── GoToTodayNotification.swift        ← Notification.Name.goToToday
├── ForeverDiaryMac.entitlements       ← sandbox + network entitlements
├── Assets.xcassets/
│   ├── AppIcon.appiconset/            ← PNG icons at all macOS sizes
│   └── AccentColor.colorset/
└── Views/
    ├── MainWindowView.swift           ← NavigationSplitView root
    ├── SyncStatusView.swift           ← iCloud sync status icon
    ├── Sidebar/
    │   └── CalendarSidebarView.swift  ← Year nav + month grid
    ├── Editor/
    │   ├── EntryEditorView.swift      ← Main diary editor
    │   └── CheckInSectionView.swift   ← Daily check-in toggles/fields
    ├── EntryList/
    │   └── EntryListView.swift        ← Entries list (sidebar)
    ├── Analytics/
    │   └── AnalyticsMacView.swift     ← Stub
    ├── Settings/
    │   └── SettingsMacView.swift      ← Account + habits settings
    └── Auth/
        └── SignInMacView.swift        ← Full auth flow
```

---

## Step 1: Recreate Source Files (if missing)

If `ForeverDiaryMac/` doesn't exist, tell Claude Code:

> "Recreate all ForeverDiaryMac source files and build the macOS app. The source files are listed in docs/macos-rebuild.md."

Claude Code has the full file contents in context from previous sessions (stored in `.claude/projects/`). Alternatively, the files were last successfully built and the source is committed to git — check `git log` first.

**If you need to recreate manually**, create the directories:
```bash
mkdir -p ForeverDiaryMac/App
mkdir -p ForeverDiaryMac/Views/{Editor,Sidebar,EntryList,Analytics,Settings,Auth}
mkdir -p ForeverDiaryMac/Assets.xcassets/AppIcon.appiconset
mkdir -p ForeverDiaryMac/Assets.xcassets/AccentColor.colorset
```

---

## Step 2: Generate Xcode Project

The project uses XcodeGen. Always run this after any source file changes:

```bash
cd /Users/kennethsolomon/Herd/forever-diary
xcodegen generate
```

Expected output ends with: `⚙️  Generated: ForeverDiary.xcodeproj`

If this fails with "missing source directory", the `ForeverDiaryMac/` directory is missing — go back to Step 1.

---

## Step 3: Archive

```bash
xcodebuild archive \
  -scheme ForeverDiaryMac \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath /tmp/ForeverDiaryMac.xcarchive \
  CODE_SIGN_IDENTITY="Apple Development: mr.kennethsolomon@gmail.com (XU4F3HX58C)" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM=CL4Z3C7CSV \
  2>&1 | tail -5
```

Expected: `** ARCHIVE SUCCEEDED **`

**Common failures:**
- `entitlements file not found` → `ForeverDiaryMac/ForeverDiaryMac.entitlements` is missing
- `no such module 'SwiftData'` → wrong deployment target or SDK; check `project.yml`
- `Code signing error` → run `security find-identity -v -p codesigning` to verify identity

---

## Step 4: Export

```bash
mkdir -p /tmp/ForeverDiaryMacExport

cat > /tmp/ExportOptions.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>development</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>Apple Development: mr.kennethsolomon@gmail.com (XU4F3HX58C)</string>
    <key>teamID</key>
    <string>CL4Z3C7CSV</string>
</dict>
</plist>
EOF

xcodebuild -exportArchive \
  -archivePath /tmp/ForeverDiaryMac.xcarchive \
  -exportOptionsPlist /tmp/ExportOptions.plist \
  -exportPath /tmp/ForeverDiaryMacExport \
  2>&1 | tail -5
```

Expected: `** EXPORT SUCCEEDED **`

---

## Step 5: Inject App Icon

The archive process may not embed the AppIcon correctly. This step ensures the icon appears in Finder and the Dock.

```bash
APP_PATH=$(find /tmp/ForeverDiaryMacExport -name "*.app" | head -1)
ICONSET=/tmp/ForeverDiaryMac.iconset
mkdir -p $ICONSET

# Copy PNG files from the built Assets.xcassets into iconset format
# Source PNGs are in ForeverDiaryMac/Assets.xcassets/AppIcon.appiconset/
ASSET_DIR=/Users/kennethsolomon/Herd/forever-diary/ForeverDiaryMac/Assets.xcassets/AppIcon.appiconset

cp "$ASSET_DIR/icon_16.png"   "$ICONSET/icon_16x16.png"
cp "$ASSET_DIR/icon_32.png"   "$ICONSET/icon_16x16@2x.png"
cp "$ASSET_DIR/icon_32.png"   "$ICONSET/icon_32x32.png"
cp "$ASSET_DIR/icon_64.png"   "$ICONSET/icon_32x32@2x.png"
cp "$ASSET_DIR/icon_128.png"  "$ICONSET/icon_128x128.png"
cp "$ASSET_DIR/icon_256.png"  "$ICONSET/icon_128x128@2x.png"
cp "$ASSET_DIR/icon_256.png"  "$ICONSET/icon_256x256.png"
cp "$ASSET_DIR/icon_512.png"  "$ICONSET/icon_256x256@2x.png"
cp "$ASSET_DIR/icon_512.png"  "$ICONSET/icon_512x512.png"
cp "$ASSET_DIR/icon_1024.png" "$ICONSET/icon_512x512@2x.png"

# Convert to .icns
iconutil -c icns "$ICONSET" -o /tmp/ForeverDiaryMac.icns

# Inject into app bundle
cp /tmp/ForeverDiaryMac.icns "$APP_PATH/Contents/Resources/ForeverDiaryMac.icns"

# Update Info.plist
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string ForeverDiaryMac" "$APP_PATH/Contents/Info.plist" 2>/dev/null || \
/usr/libexec/PlistBuddy -c "Set :CFBundleIconFile ForeverDiaryMac" "$APP_PATH/Contents/Info.plist"

# Re-sign after modifying the bundle
codesign --force --deep --sign "Apple Development: mr.kennethsolomon@gmail.com (XU4F3HX58C)" "$APP_PATH"
```

---

## Step 6: Package

```bash
mkdir -p ~/Desktop/ForeverDiaryMacBuild
cd /tmp/ForeverDiaryMacExport
zip -r ~/Desktop/ForeverDiaryMacBuild/ForeverDiaryMac.zip *.app
echo "Done: $(du -sh ~/Desktop/ForeverDiaryMacBuild/ForeverDiaryMac.zip)"
```

Expected output: around 700–900K.

---

## Quick Rebuild (All Steps)

If the source files already exist and you just need a fresh binary:

```bash
cd /Users/kennethsolomon/Herd/forever-diary

xcodegen generate && \
xcodebuild archive \
  -scheme ForeverDiaryMac \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath /tmp/ForeverDiaryMac.xcarchive \
  CODE_SIGN_IDENTITY="Apple Development: mr.kennethsolomon@gmail.com (XU4F3HX58C)" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM=CL4Z3C7CSV && \
mkdir -p /tmp/ForeverDiaryMacExport && \
xcodebuild -exportArchive \
  -archivePath /tmp/ForeverDiaryMac.xcarchive \
  -exportOptionsPlist /tmp/ExportOptions.plist \
  -exportPath /tmp/ForeverDiaryMacExport && \
APP_PATH=$(find /tmp/ForeverDiaryMacExport -name "*.app" | head -1) && \
cp /tmp/ForeverDiaryMac.icns "$APP_PATH/Contents/Resources/ForeverDiaryMac.icns" 2>/dev/null; \
codesign --force --deep --sign "Apple Development: mr.kennethsolomon@gmail.com (XU4F3HX58C)" "$APP_PATH" && \
cd /tmp/ForeverDiaryMacExport && \
zip -r ~/Desktop/ForeverDiaryMacBuild/ForeverDiaryMac.zip *.app
```

---

## Telling Claude Code to Rebuild

Just say:

> "Create a new macOS build"

Claude Code will:
1. Check if `ForeverDiaryMac/` exists (recreate if missing)
2. Run `xcodegen generate`
3. Archive + export
4. Inject icon + re-sign
5. Zip to `~/Desktop/ForeverDiaryMacBuild/ForeverDiaryMac.zip`

The full build pipeline takes about 2–5 minutes.

---

## Important: Commit the Source Files

The `ForeverDiaryMac/` directory should be committed to git so it doesn't need to be recreated each time. To commit:

```bash
git add ForeverDiaryMac/
git commit -m "chore: add ForeverDiaryMac source files"
```

The `.xcodeproj` and `DerivedData` should NOT be committed (already in `.gitignore`).
