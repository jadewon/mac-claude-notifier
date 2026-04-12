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
    killall ClaudeNotifier 2>/dev/null

    TMPFILE=$(mktemp /tmp/claude-noti-XXXXXX)
    trap 'rm -f "$TMPFILE"' EXIT
    printf '%s' "$INPUT" > "$TMPFILE"

    BUNDLE_ID=$(resolve_terminal_bundle_id)
    open -a "$APP_BUNDLE" --args --data "$TMPFILE" --activate "$BUNDLE_ID" &
else
    # Fallback: osascript (click opens Script Editor)
    MESSAGE=$(echo "$INPUT" | jq -r '.message // "Done"')
    osascript - "$MESSAGE" <<'APPLESCRIPT'
on run argv
    display notification (item 1 of argv) with title "🤖 Claude Code"
end run
APPLESCRIPT
fi
