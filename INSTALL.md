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

## Step 3: Trigger first notification to register permission

Launching the app for the first time registers it with macOS and shows a permission prompt.

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

Tell the user:

> "A macOS permission prompt should appear. Please click **Allow**. If you don't see it, I'll help you enable it manually in System Settings."

## Step 4: Verify the notification was shown

Ask the user if they saw a notification banner. If YES — skip to Step 5.

If NO, the permission was likely denied or the prompt was missed. Check the logs:

```bash
/usr/bin/log show --predicate 'processImagePath CONTAINS "ClaudeNotifier" AND eventMessage CONTAINS "authorization"' --last 5m --style compact 2>/dev/null | tail -5
```

Look for `didGrant: 0 hasError: 1` — this means permission is denied.

**If permission is denied**, guide the user through System Settings:

> "Please open **System Settings → Notifications**, scroll to find **ClaudeNotifier**, and turn on **Allow notifications**. Set Alert style to **Banners** or **Alerts**."

You can open System Settings directly to the Notifications pane:

```bash
open "x-apple.systempreferences:com.apple.preference.notifications"
```

After the user confirms they enabled it, re-run the test notification from Step 3 to verify.

## Step 5: Verify click behavior

Ask the user to click the test notification and confirm that it activated their terminal app.

**If the user is on iTerm2**, the first click will also show an Automation permission prompt:

> "ClaudeNotifier" wants access to control "iTerm".

Tell the user:

> "Please click **OK** to allow this. It enables notifications to jump to the exact tab that triggered them. You can revoke it later in System Settings → Privacy & Security → Automation."

Without this permission, clicking still activates iTerm2 but does not switch tabs.

## Done

Report to the user:
- mac-claude-notifier is installed
- Notifications will auto-detect their terminal app
- They can customize the notification appearance (emoji, title, body, sound) by editing the `format_notification()` function at the top of the installed `notification.sh` — no rebuild required
- They can override the terminal target with the `CLAUDE_NOTIFIER_ACTIVATE_APP` environment variable (see README)
