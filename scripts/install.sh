#!/bin/bash
# Standalone installer for mac-claude-notifier
# Works with both Release zip downloads and source builds
set -e

INSTALL_DIR="$HOME/.claude/hooks"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Find ClaudeNotifier.app (in current dir, build dir, or script's parent dir)
APP_SOURCE=""
for candidate in \
    "$SCRIPT_DIR/ClaudeNotifier.app" \
    "$SCRIPT_DIR/../build/ClaudeNotifier.app" \
    "./ClaudeNotifier.app" \
    "./build/ClaudeNotifier.app"; do
    if [ -d "$candidate" ]; then
        APP_SOURCE="$candidate"
        break
    fi
done

if [ -z "$APP_SOURCE" ]; then
    echo "Error: ClaudeNotifier.app not found."
    echo "Run this script from the directory containing ClaudeNotifier.app."
    exit 1
fi

# Find notification.sh
HOOK_SOURCE=""
for candidate in \
    "$SCRIPT_DIR/notification.sh" \
    "$SCRIPT_DIR/../scripts/notification.sh" \
    "./scripts/notification.sh" \
    "./notification.sh"; do
    if [ -f "$candidate" ]; then
        HOOK_SOURCE="$candidate"
        break
    fi
done

if [ -z "$HOOK_SOURCE" ]; then
    echo "Error: notification.sh not found."
    exit 1
fi

# Install
mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_DIR/ClaudeNotifier.app"
cp -R "$APP_SOURCE" "$INSTALL_DIR/"
cp "$HOOK_SOURCE" "$INSTALL_DIR/notification.sh"
chmod +x "$INSTALL_DIR/notification.sh"

echo "Installed to $INSTALL_DIR"
echo ""
echo "Add this to your ~/.claude/settings.json (merge into existing hooks if needed):"
echo ""
echo '  "Notification": ['
echo '    {'
echo '      "matcher": "",'
echo '      "hooks": ['
echo '        {'
echo '          "type": "command",'
echo "          \"command\": \"$INSTALL_DIR/notification.sh\""
echo '        }'
echo '      ]'
echo '    }'
echo '  ]'
echo ""
echo "First run will prompt for macOS notification permission."
