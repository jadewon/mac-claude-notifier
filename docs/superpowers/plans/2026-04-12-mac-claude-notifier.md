# mac-claude-notifier Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship an open-source macOS native notification app for Claude Code that replaces osascript and the unmaintained terminal-notifier, with click-to-activate-terminal support.

**Architecture:** Single-file Swift app using UNUserNotificationCenter, built via Makefile with version injection into Info.plist. Shell hook script bridges Claude Code's stdin JSON to the app via temp file + `open -a`. GitHub Actions workflow publishes signed .zip to GitHub Releases on tag push.

**Tech Stack:** Swift 5+, AppKit, UserNotifications framework, Make, GitHub Actions

---

## File Structure

```
mac-claude-notifier/
├── Sources/
│   └── main.swift                    # App source (UNUserNotificationCenter + click handler)
├── Resources/
│   └── Info.plist.template           # Plist template with __VERSION__ placeholder
├── scripts/
│   └── notification.sh               # Claude Code hook script (stdin → temp file → open -a)
├── Makefile                          # build, install, clean, release targets
├── README.md                         # Full documentation
├── LICENSE                           # MIT license
├── .gitignore
└── .github/
    └── workflows/
        └── release.yml               # Tag push → build → GitHub Release
```

---

### Task 1: Initialize Git repo and project scaffolding

**Files:**
- Create: `.gitignore`
- Create: `LICENSE`

- [ ] **Step 1: Initialize git repo**

```bash
cd /Users/jadewon/Workspaces/jadewon.github.com/mac-claude-notifier
git init
```

- [ ] **Step 2: Create .gitignore**

```gitignore
# Build output
build/
*.app
*.zip
*.dmg

# macOS
.DS_Store
*.swp

# Xcode
*.xcodeproj
*.xcworkspace
xcuserdata/
DerivedData/
```

- [ ] **Step 3: Create MIT LICENSE**

Standard MIT license with `Copyright (c) 2026 jadewon`.

- [ ] **Step 4: Commit**

```bash
git add .gitignore LICENSE
git commit -m "init: project scaffolding"
```

---

### Task 2: Swift source — dynamic terminal activation

**Files:**
- Create: `Sources/main.swift`

Port the working code from `~/.claude/hooks/claude-notifier/main.swift` with these changes:
- Replace hardcoded iTerm2 bundle ID with `--activate <bundleID>` CLI argument
- Default to `com.apple.Terminal` if no `--activate` is provided
- Keep all existing notification logic (type-based title/sound, customTitle from transcript, 60s auto-exit)

- [ ] **Step 1: Create Sources/main.swift**

```swift
import Cocoa
import UserNotifications

// MARK: - Parse CLI arguments
var stdinJSON: [String: Any] = [:]
var activateBundleID = "com.apple.Terminal"

func parseArguments() {
    let args = CommandLine.arguments
    if let i = args.firstIndex(of: "--data"), i + 1 < args.count {
        let filePath = args[i + 1]
        if let data = FileManager.default.contents(atPath: filePath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            stdinJSON = json
        }
        try? FileManager.default.removeItem(atPath: filePath)
    }
    if let i = args.firstIndex(of: "--activate"), i + 1 < args.count {
        activateBundleID = args[i + 1]
    }
}

parseArguments()
let hasInput = !stdinJSON.isEmpty

// MARK: - App Delegate
class NotifierDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !hasInput {
            activateTerminal()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NSApp.terminate(nil) }
            return
        }

        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
            DispatchQueue.main.async { self.postNotification() }
        }
    }

    func readCustomTitle() -> String? {
        guard let transcriptPath = stdinJSON["transcript_path"] as? String else { return nil }
        guard let data = FileManager.default.contents(atPath: transcriptPath),
              let content = String(data: data, encoding: .utf8) else { return nil }
        for line in content.components(separatedBy: .newlines).reversed() {
            if line.contains("\"customTitle\""),
               let lineData = line.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
               let t = json["customTitle"] as? String, !t.isEmpty {
                return t
            }
        }
        return nil
    }

    func postNotification() {
        let message = stdinJSON["message"] as? String ?? "Done"
        let title = stdinJSON["title"] as? String
        let type = stdinJSON["notification_type"] as? String ?? "unknown"
        let cwd = stdinJSON["cwd"] as? String ?? ""

        let sessionLabel = readCustomTitle() ?? (cwd as NSString).lastPathComponent

        var notiTitle: String
        var soundName: String

        switch type {
        case "permission_prompt":  notiTitle = "🔐 Permission Required"; soundName = "Blow"
        case "idle_prompt":        notiTitle = "💤 Waiting for Input";    soundName = "Tink"
        case "auth_success":       notiTitle = "✅ Auth Complete";        soundName = "Glass"
        case "elicitation_dialog": notiTitle = "💬 Input Needed";         soundName = "Blow"
        default:                   notiTitle = "🤖 Claude Code";          soundName = "default"
        }

        var subtitle = title ?? ""
        if !sessionLabel.isEmpty {
            subtitle = subtitle.isEmpty ? "[\(sessionLabel)]" : "[\(sessionLabel)] \(subtitle)"
        }

        let content = UNMutableNotificationContent()
        content.title = notiTitle
        content.subtitle = subtitle
        content.body = message
        content.sound = UNNotificationSound(named: UNNotificationSoundName(soundName))

        let request = UNNotificationRequest(
            identifier: "claude-notification",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
                NSApp.terminate(nil)
            }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        activateTerminal()
        completionHandler()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NSApp.terminate(nil) }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func activateTerminal() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: activateBundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}

// MARK: - Main
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = NotifierDelegate()
app.delegate = delegate
app.run()
```

- [ ] **Step 2: Commit**

```bash
git add Sources/main.swift
git commit -m "feat: add Swift source with dynamic terminal activation"
```

---

### Task 3: Info.plist template and Makefile

**Files:**
- Create: `Resources/Info.plist.template`
- Create: `Makefile`

- [ ] **Step 1: Create Info.plist.template**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.jadewon.claude-notifier</string>
    <key>CFBundleName</key>
    <string>ClaudeNotifier</string>
    <key>CFBundleExecutable</key>
    <string>ClaudeNotifier</string>
    <key>CFBundleVersion</key>
    <string>__VERSION__</string>
    <key>CFBundleShortVersionString</key>
    <string>__VERSION__</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
```

- [ ] **Step 2: Create Makefile**

```makefile
VERSION ?= 0.1.0
APP_NAME = ClaudeNotifier
BUILD_DIR = build
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app
INSTALL_DIR = $(HOME)/.claude/hooks

.PHONY: build install clean release

build:
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@sed 's/__VERSION__/$(VERSION)/g' Resources/Info.plist.template > $(APP_BUNDLE)/Contents/Info.plist
	@swiftc Sources/main.swift \
		-o $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME) \
		-framework Cocoa \
		-framework UserNotifications \
		-O
	@codesign --force --sign - $(APP_BUNDLE)
	@echo "Built $(APP_BUNDLE) (v$(VERSION))"

install: build
	@mkdir -p $(INSTALL_DIR)
	@rm -rf $(INSTALL_DIR)/$(APP_NAME).app
	@cp -R $(APP_BUNDLE) $(INSTALL_DIR)/
	@cp scripts/notification.sh $(INSTALL_DIR)/notification.sh
	@chmod +x $(INSTALL_DIR)/notification.sh
	@echo "Installed to $(INSTALL_DIR)"
	@echo ""
	@echo "Add this to your ~/.claude/settings.json hooks.Notification:"
	@echo '  {"matcher":"","hooks":[{"type":"command","command":"$(INSTALL_DIR)/notification.sh"}]}'

clean:
	@rm -rf $(BUILD_DIR)

release: build
	@cd $(BUILD_DIR) && zip -r $(APP_NAME)-v$(VERSION)-macOS.zip $(APP_NAME).app
	@echo "Created $(BUILD_DIR)/$(APP_NAME)-v$(VERSION)-macOS.zip"
```

- [ ] **Step 3: Commit**

```bash
git add Resources/Info.plist.template Makefile
git commit -m "feat: add Info.plist template and Makefile with version injection"
```

---

### Task 4: Hook script with terminal auto-detection

**Files:**
- Create: `scripts/notification.sh`

- [ ] **Step 1: Create scripts/notification.sh**

```bash
#!/bin/bash
# Claude Code notification hook — pipes stdin JSON to ClaudeNotifier.app
# https://github.com/jadewon/mac-claude-notifier

APP_BUNDLE="${CLAUDE_NOTIFIER_APP:-$HOME/.claude/hooks/ClaudeNotifier.app}"
INPUT=$(cat)

# Resolve terminal bundle ID: env override > TERM_PROGRAM auto-detect > default
resolve_terminal_bundle_id() {
    if [ -n "$CLAUDE_NOTIFIER_ACTIVATE_APP" ]; then
        echo "$CLAUDE_NOTIFIER_ACTIVATE_APP"
        return
    fi

    case "${TERM_PROGRAM:-}" in
        iTerm.app)       echo "com.googlecode.iterm2" ;;
        Apple_Terminal)  echo "com.apple.Terminal" ;;
        WarpTerminal)    echo "dev.warp.Warp-Stable" ;;
        vscode)          echo "com.microsoft.VSCode" ;;
        Hyper)           echo "co.zeit.hyper" ;;
        alacritty)       echo "org.alacritty" ;;
        ghostty)         echo "com.mitchellh.ghostty" ;;
        *)               echo "com.apple.Terminal" ;;
    esac
}

if [ -d "$APP_BUNDLE" ]; then
    pkill -f "ClaudeNotifier" 2>/dev/null

    TMPFILE=$(mktemp /tmp/claude-noti-XXXXXX)
    printf '%s' "$INPUT" > "$TMPFILE"

    BUNDLE_ID=$(resolve_terminal_bundle_id)
    open -a "$APP_BUNDLE" --args --data "$TMPFILE" --activate "$BUNDLE_ID" &
else
    # Fallback: osascript (click opens Script Editor)
    MESSAGE=$(echo "$INPUT" | jq -r '.message // "Done"')
    osascript -e "display notification \"$MESSAGE\" with title \"🤖 Claude Code\""
fi
```

- [ ] **Step 2: Commit**

```bash
git add scripts/notification.sh
git commit -m "feat: add hook script with terminal auto-detection"
```

---

### Task 5: README.md

**Files:**
- Create: `README.md`

- [ ] **Step 1: Create README.md**

Full README with these sections:

1. **Title + tagline**: "Native macOS notifications for Claude Code. Click to jump back to your terminal."
2. **Why**: terminal-notifier is unmaintained (last release 2017, uses deprecated NSUserNotificationCenter, broken on Apple Silicon/Sequoia). osascript works but click opens Script Editor. This project uses the modern UNUserNotificationCenter API.
3. **Comparison table**:

| Feature | osascript | terminal-notifier | mac-claude-notifier |
|---|---|---|---|
| macOS native API | AppleScript bridge | NSUserNotification (deprecated) | UNUserNotificationCenter |
| Click → your terminal | Script Editor opens | Configurable (`-activate`) | Auto-detects terminal |
| Custom sound per type | Manual | Single sound | Per notification type |
| Session/project label | No | No | customTitle or cwd |
| Maintained | Apple built-in | Last release 2017 | Active |
| macOS Sequoia+ | Works (limited) | Broken | Works |
| Dock icon | No | Yes | No (LSUIElement) |

4. **Quick Start** (download release zip, `make install`, add hook to settings.json)
5. **Build from source** (`make build`, `make install`)
6. **Configuration**: env vars (`CLAUDE_NOTIFIER_ACTIVATE_APP`, `CLAUDE_NOTIFIER_APP`), TERM_PROGRAM mapping table, notification type → title/sound mapping table
7. **How it works**: architecture diagram (Claude Code → hook → notification.sh → temp file → open -a → ClaudeNotifier.app → UNUserNotificationCenter → click → NSWorkspace activate terminal)
8. **Requirements**: macOS 13+, Swift 5.9+, Claude Code
9. **License**: MIT

See full content in Step 1 code block below.

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add README with install guide and comparison table"
```

---

### Task 6: GitHub Actions release workflow

**Files:**
- Create: `.github/workflows/release.yml`

- [ ] **Step 1: Create .github/workflows/release.yml**

```yaml
name: Release

on:
  push:
    tags:
      - 'v*'

permissions:
  contents: write

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4

      - name: Extract version from tag
        id: version
        run: echo "VERSION=${GITHUB_REF_NAME#v}" >> $GITHUB_OUTPUT

      - name: Build
        run: make build VERSION=${{ steps.version.outputs.VERSION }}

      - name: Package
        run: make release VERSION=${{ steps.version.outputs.VERSION }}

      - name: Create GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          files: build/ClaudeNotifier-v${{ steps.version.outputs.VERSION }}-macOS.zip
          generate_release_notes: true
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "ci: add GitHub Actions release workflow"
```

---

### Task 7: Build verification and local install test

- [ ] **Step 1: Run build**

```bash
cd /Users/jadewon/Workspaces/jadewon.github.com/mac-claude-notifier
make build
```

Expected: `Built build/ClaudeNotifier.app (v0.1.0)`

- [ ] **Step 2: Verify app bundle structure**

```bash
ls -R build/ClaudeNotifier.app/Contents/
cat build/ClaudeNotifier.app/Contents/Info.plist | grep -A1 CFBundleVersion
```

Expected: Version shows `0.1.0`, binary exists in `MacOS/ClaudeNotifier`

- [ ] **Step 3: Test notification**

```bash
TMPFILE=$(mktemp /tmp/claude-noti-XXXXXX)
printf '{"message":"Build test","notification_type":"idle_prompt","cwd":"/tmp/test-project","title":"Test"}' > "$TMPFILE"
open -a build/ClaudeNotifier.app --args --data "$TMPFILE" --activate com.googlecode.iterm2
```

Expected: Notification banner appears with "💤 Waiting for Input", subtitle "[test-project] Test", body "Build test"

- [ ] **Step 4: Run make install**

```bash
make install
```

Expected: Files copied to `~/.claude/hooks/`, prints settings.json hook config

- [ ] **Step 5: Final commit and tag**

```bash
git add -A
git commit -m "chore: verify build and ready for v0.1.0"
git tag v0.1.0
```

---

### Task 8: Update personal hook to use installed version

- [ ] **Step 1: Verify ~/.claude/hooks/notification.sh points to the new script**

The `make install` from Task 7 already replaced the hook script. Verify it works by checking that `~/.claude/settings.json` Notification hook still points to `~/.claude/hooks/notification.sh`.

- [ ] **Step 2: Clean up old source files**

```bash
rm -rf ~/.claude/hooks/claude-notifier/
```

The source now lives in the open-source repo. The installed `.app` and `notification.sh` in `~/.claude/hooks/` are the only runtime files needed.
