# LLM Installation Guide for mac-claude-notifier

> This document is designed for LLM agents (Claude Code, etc.) to read and execute autonomously. If you are a human, see the [README](README.md) for manual installation.

## Prerequisites Check

```bash
# Verify macOS
uname -s  # Must be "Darwin"

# Verify Swift
swiftc --version  # Must be 5.9+
```

If Swift is not available, the user needs Xcode Command Line Tools: `xcode-select --install`

## Step 1: Install

Choose ONE method:

### Method A: Homebrew (preferred)

```bash
brew tap jadewon/tap
brew install mac-claude-notifier
```

After install, get the notification script path:
```bash
NOTIFICATION_SH="$(brew --prefix)/bin/notification.sh"
```

Skip to Step 2.

### Method B: Build from source

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

Read the user's `~/.claude/settings.json`. If the `hooks.Notification` array does not already contain a reference to `notification.sh`, add it.

### If hooks.Notification does not exist:

Add this to the `hooks` object in `~/.claude/settings.json`:

```json
"Notification": [
  {
    "matcher": "",
    "hooks": [
      {
        "type": "command",
        "command": "<NOTIFICATION_SH path from Step 1>"
      }
    ]
  }
]
```

### If hooks.Notification already exists:

Check if any existing hook command references `notification.sh` or `ClaudeNotifier`. If so, update it to the new path. If not, append to the hooks array.

## Step 3: Grant notification permission

The first notification will trigger a macOS permission prompt. Tell the user:

> "The first notification will ask for macOS permission. When you see the prompt, click Allow."

To trigger the permission prompt immediately:

```bash
TMPFILE=$(mktemp /tmp/claude-noti-XXXXXX)
printf '{"message":"mac-claude-notifier installed successfully","notification_type":"unknown","cwd":"%s","title":"Setup Complete"}' "$PWD" > "$TMPFILE"

# For Homebrew install:
open -a "$(brew --prefix)/ClaudeNotifier.app" --args --data "$TMPFILE"

# For source install:
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
- They can customize behavior with environment variables (see README)
