# LLM Installation Guide for mac-claude-notifier

> This document is designed for LLM agents (Claude Code, etc.) to read and execute autonomously. If you are a human, see the [README](README.md) for manual installation.

## Prerequisites

```bash
uname -s  # Must be "Darwin"
```

## Step 1: Install

Choose ONE method. Try them in order — use the first one that works.

### Method A: Homebrew

```bash
brew tap jadewon/tap
brew install mac-claude-notifier
```

The notification script path is:
```bash
NOTIFICATION_SH="$(brew --prefix)/bin/notification.sh"
```

The app bundle path is:
```bash
APP_BUNDLE="$(brew --prefix)/ClaudeNotifier.app"
```

### Method B: Download pre-built release (no Swift/Xcode required)

```bash
cd /tmp
curl -sL "https://github.com/jadewon/mac-claude-notifier/releases/latest/download/ClaudeNotifier-v0.1.0-macOS.zip" -o claude-notifier.zip
unzip -o claude-notifier.zip -d claude-notifier
cd claude-notifier
./install.sh
rm -rf /tmp/claude-notifier /tmp/claude-notifier.zip
```

The notification script path is:
```bash
NOTIFICATION_SH="$HOME/.claude/hooks/notification.sh"
```

### Method C: Build from source (requires Swift 5.9+)

```bash
cd /tmp
git clone https://github.com/jadewon/mac-claude-notifier.git
cd mac-claude-notifier
make install
rm -rf /tmp/mac-claude-notifier
```

The notification script path is:
```bash
NOTIFICATION_SH="$HOME/.claude/hooks/notification.sh"
```

## Step 2: Configure Claude Code hook

Read the user's `~/.claude/settings.json`.

**Important:** The `command` value must be an absolute path. Do NOT use `~` — it does not expand in JSON.

### If hooks.Notification does not exist:

Add this to the `hooks` object in `~/.claude/settings.json`:

```json
"Notification": [
  {
    "matcher": "",
    "hooks": [
      {
        "type": "command",
        "command": "<absolute path to notification.sh from Step 1>"
      }
    ]
  }
]
```

For Method A (Homebrew), resolve the path first:
```bash
echo "$(brew --prefix)/bin/notification.sh"
```

For Methods B and C, the path is `$HOME/.claude/hooks/notification.sh` (expand `$HOME` to the actual home directory).

### If hooks.Notification already exists:

Check if any existing hook command references `notification.sh` or `ClaudeNotifier`. If so, update it to the new path. If not, append to the hooks array.

## Step 3: Grant notification permission

The first notification triggers a macOS permission prompt. Tell the user:

> "The first notification will ask for macOS permission. When you see the prompt, click Allow."

To trigger the permission prompt now:

```bash
TMPFILE=$(mktemp /tmp/claude-noti-XXXXXX)
printf '{"message":"mac-claude-notifier installed successfully","notification_type":"unknown","cwd":"%s","title":"Setup Complete"}' "$PWD" > "$TMPFILE"
```

Then open the app (use the path from Step 1):

```bash
# Method A (Homebrew):
open -a "$(brew --prefix)/ClaudeNotifier.app" --args --data "$TMPFILE"

# Methods B and C:
open -a "$HOME/.claude/hooks/ClaudeNotifier.app" --args --data "$TMPFILE"
```

## Step 4: Verify

After the user grants permission, confirm:
- A notification banner appeared
- Clicking the notification activated their terminal app

## Done

Report to the user:
- mac-claude-notifier is installed
- Notifications will auto-detect their terminal app
- They can customize the notification appearance (emoji, title, body, sound) by editing the `format_notification()` function at the top of the installed `notification.sh` — no rebuild required
- They can override the terminal target with the `CLAUDE_NOTIFIER_ACTIVATE_APP` environment variable (see README)
