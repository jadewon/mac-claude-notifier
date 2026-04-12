# mac-claude-notifier

Native macOS notifications for Claude Code. Click to jump back to your terminal.

## Why this exists

`osascript`'s `display notification` works but clicking always opens Script Editor — there is no way to configure a different click target. `terminal-notifier` was the standard alternative, but it has not had a release since 2017, relies on the deprecated `NSUserNotificationCenter` API, and is broken on macOS Sequoia and Apple Silicon.

This project is a lightweight replacement built on Apple's modern `UNUserNotificationCenter` API. It was built specifically for Claude Code hooks but works with any CLI that can pipe JSON to stdin.

## Comparison

| Feature | osascript | terminal-notifier | mac-claude-notifier |
|---|---|---|---|
| macOS API | AppleScript bridge | NSUserNotification (deprecated) | UNUserNotificationCenter |
| Click action | Opens Script Editor | Configurable (`-activate`) | Auto-detects terminal |
| Custom sound | Manual | Single sound | Per notification type |
| Session label | No | No | Session title or project name |
| Maintained | Apple built-in | Last release 2017 | Active |
| macOS Sequoia+ | Works (limited) | Broken | Works |
| Dock icon | No | Shows in Dock | No (background app) |

## Quick Start

**Option A — Homebrew**

```bash
brew tap jadewon/tap
brew install mac-claude-notifier
```

**Option B — Download from GitHub Releases**

```bash
# Download and unzip the latest release from GitHub Releases, then:
make install
```

**Option C — Build from source**

```bash
git clone https://github.com/jadewon/mac-claude-notifier.git
cd mac-claude-notifier
make install
```

**Add the hook to `~/.claude/settings.json`**

```json
{
  "hooks": {
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/notification.sh"
          }
        ]
      }
    ]
  }
}
```

If installed via Homebrew, check the path shown in `brew info mac-claude-notifier` and use it as the command value.

The first run will prompt for macOS notification permission — allow it.

## Configuration

**Environment variables**

| Variable | Description |
|---|---|
| `CLAUDE_NOTIFIER_ACTIVATE_APP` | Override the terminal bundle ID (e.g., `com.googlecode.iterm2`) |
| `CLAUDE_NOTIFIER_APP` | Override the app bundle path (default: `~/.claude/hooks/ClaudeNotifier.app`) |

**Auto-detected terminals**

The terminal is detected automatically from `$TERM_PROGRAM`.

| Terminal | TERM_PROGRAM | Bundle ID |
|---|---|---|
| iTerm2 | `iTerm.app` | `com.googlecode.iterm2` |
| Terminal.app | `Apple_Terminal` | `com.apple.Terminal` |
| Warp | `WarpTerminal` | `dev.warp.Warp-Stable` |
| VS Code | `vscode` | `com.microsoft.VSCode` |
| Ghostty | `ghostty` | `com.mitchellh.ghostty` |
| Alacritty | `alacritty` | `org.alacritty` |
| Hyper | `Hyper` | `co.zeit.hyper` |

**Notification types**

| Type | Title | Sound |
|---|---|---|
| `permission_prompt` | 🔐 Permission Required | Blow |
| `idle_prompt` | 💤 Waiting for Input | Tink |
| `auth_success` | ✅ Auth Complete | Glass |
| `elicitation_dialog` | 💬 Input Needed | Blow |
| (other) | 🤖 Claude Code | default |

## How it works

```
Claude Code event
  → Notification hook triggers notification.sh
    → Reads JSON from stdin, detects terminal via TERM_PROGRAM
      → Writes JSON to temp file (macOS `open` can't pipe stdin)
        → `open -a ClaudeNotifier.app --args --data /tmp/... --activate <bundleID>`
          → UNUserNotificationCenter posts native notification
            → Click → NSWorkspace activates your terminal
              → App auto-exits after 60s
```

The notification subtitle shows the session's `customTitle` (from the Claude Code transcript) if set, otherwise the project directory name.

## Requirements

- macOS 13 (Ventura) or later
- Swift 5.9+ (included with Xcode 15+)
- Claude Code

## License

MIT
