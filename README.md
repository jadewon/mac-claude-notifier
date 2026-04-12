# mac-claude-notifier

Native macOS notifications for Claude Code. Click to jump back to your terminal.

> **Using Claude Code?** Paste this URL and ask Claude to install it for you:
> `https://raw.githubusercontent.com/jadewon/mac-claude-notifier/main/INSTALL.md`

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

## Installation

### Option A — Homebrew (recommended)

```bash
brew tap jadewon/tap
brew install mac-claude-notifier
```

Then add the hook to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "/opt/homebrew/bin/notification.sh"
          }
        ]
      }
    ]
  }
}
```

> Intel Mac users: replace `/opt/homebrew` with `/usr/local`.

### Option B — Download pre-built release

1. Download the latest `.zip` from [GitHub Releases](https://github.com/jadewon/mac-claude-notifier/releases)
2. Unzip and run the installer:

```bash
unzip ClaudeNotifier-v*.zip
./install.sh
```

The installer copies `ClaudeNotifier.app` and `notification.sh` to `~/.claude/hooks/` and prints the settings.json configuration to add.

### Option C — Build from source

Requires Swift 5.9+ (included with Xcode 15+).

```bash
git clone https://github.com/jadewon/mac-claude-notifier.git
cd mac-claude-notifier
make install
```

Same as Option B — installs to `~/.claude/hooks/` and prints the hook configuration.

### Notification permission

The first notification triggers a macOS permission prompt. Click **Allow** to enable notifications.

## Customizing the notification

To change the emoji, title, body, or sound, edit the `format_notification()` function at the top of your installed `notification.sh` — no rebuild required. Saving the file is enough; the next notification picks up the change.

```bash
format_notification() {
    OUT_TITLE="🧑‍💼 인턴 개발자"
    OUT_BODY="작업을 끝냈어요"
    OUT_SOUND="Tink"

    if [ -n "$SESSION_LABEL" ]; then
        OUT_SUBTITLE="[$SESSION_LABEL]"
    fi
}
```

Available inputs inside the function:

| Variable | Description |
|---|---|
| `$NOTI_TYPE` | `permission_prompt`, `idle_prompt`, `auth_success`, `elicitation_dialog`, or other |
| `$NOTI_MESSAGE` | The message text from Claude Code |
| `$NOTI_TITLE` | The title text from Claude Code (may be empty) |
| `$SESSION_LABEL` | `customTitle` from the transcript, or the `cwd` folder name |

Outputs (set any or all):

| Variable | Description |
|---|---|
| `OUT_TITLE` | Top line of the notification |
| `OUT_SUBTITLE` | Second line (optional) |
| `OUT_BODY` | Main text |
| `OUT_SOUND` | macOS sound name (`Blow`, `Tink`, `Glass`, `Funk`, `Ping`, `Pop`, `Purr`, `Sosumi`, `Submarine`, `Basso`, `Bottle`, `Frog`, `Hero`, `Morse`) or `default` |

If `format_notification()` is absent, the Swift app falls back to `notification_type`-based built-in titles.

> `make install` preserves an existing `notification.sh`. Use `make install-force` to overwrite customizations with the latest version from the repo.

## Configuration

**Environment variables**

| Variable | Description |
|---|---|
| `CLAUDE_NOTIFIER_ACTIVATE_APP` | Override the terminal bundle ID (e.g., `com.googlecode.iterm2`) |
| `CLAUDE_NOTIFIER_APP` | Override the app bundle path |

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

**Default notification types (fallback)**

These apply only when `format_notification()` does not set values.

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

## Uninstall

```bash
# Homebrew
brew uninstall mac-claude-notifier
brew untap jadewon/tap

# Manual / source install
rm -rf ~/.claude/hooks/ClaudeNotifier.app ~/.claude/hooks/notification.sh
```

Then remove the `Notification` hook entry from `~/.claude/settings.json`. Optionally revoke notification permission in System Settings → Notifications → ClaudeNotifier.

## Requirements

- macOS 13 (Ventura) or later
- Claude Code
- Swift 5.9+ (only for building from source)

## License

MIT
