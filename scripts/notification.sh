#!/bin/bash
# Claude Code notification hook — pipes stdin JSON to ClaudeNotifier.app
# https://github.com/jadewon/mac-claude-notifier
#
# CUSTOMIZATION:
# Edit the `format_notification` function below to change emoji, title, sound, etc.
# No recompilation needed — just save this file and the next notification uses it.
# If you comment out format_notification entirely, the Swift app's built-in
# notification_type-based defaults will be used as a fallback.

APP_BUNDLE="${CLAUDE_NOTIFIER_APP:-$HOME/.claude/hooks/ClaudeNotifier.app}"
INPUT=$(cat)

# Walk a process tree upward looking for a *.app/Contents/MacOS/* executable,
# then read its CFBundleIdentifier. Echoes the bundle ID and returns 0 on hit.
# Skips background-only apps (LSUIElement / LSBackgroundOnly = 1/true): they
# have no window to bring forward, so keep walking toward the real UI app.
_walk_to_bundle_id() {
    local pid="$1"
    local exe app bid key flag skip
    while [ -n "$pid" ] && [ "$pid" != "1" ]; do
        exe=$(ps -o comm= -p "$pid" 2>/dev/null)
        case "$exe" in
            *.app/Contents/MacOS/*)
                app="${exe%/Contents/MacOS/*}"
                skip=0
                for key in LSUIElement LSBackgroundOnly; do
                    flag=$(defaults read "$app/Contents/Info" "$key" 2>/dev/null)
                    case "$flag" in
                        1|[Tt][Rr][Uu][Ee]|[Yy][Ee][Ss]) skip=1 ;;
                    esac
                done
                if [ "$skip" = "1" ]; then
                    pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
                    continue
                fi
                bid=$(defaults read "$app/Contents/Info" CFBundleIdentifier 2>/dev/null)
                if [ -n "$bid" ]; then
                    echo "$bid"
                    return 0
                fi
                ;;
        esac
        pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    done
    return 1
}

# Resolve the terminal bundle ID. Strategy:
#   1. CLAUDE_NOTIFIER_ACTIVATE_APP env override
#   2. Walk parent process tree from this hook (works for cmux, Superset,
#      ghostty, iTerm, Terminal.app, ...). Robust against $TERM_PROGRAM
#      spoofing — Superset claims "kitty", cmux claims "ghostty".
#      Background-only helper apps (LSUIElement / LSBackgroundOnly) are
#      skipped, e.g. Herdr's "Herdr Core" helper (dev.herdr.core).
#   3. Inside tmux, the hook's parents detour to a detached server. Use the
#      tmux client PID and walk from there.
#   4. $__CFBundleIdentifier, which LaunchServices sets to the launching app's
#      bundle ID and children inherit. Covers terminals whose shells run under
#      a detached helper re-parented to launchd, so the UI app is not an
#      ancestor (Herdr: shells under "Herdr Core", env says dev.herdr.app).
#   5. Legacy $TERM_PROGRAM mapping as last-resort fallback.
resolve_terminal_bundle_id() {
    if [ -n "$CLAUDE_NOTIFIER_ACTIVATE_APP" ]; then
        echo "$CLAUDE_NOTIFIER_ACTIVATE_APP"
        return
    fi

    _walk_to_bundle_id "$$" && return

    if [ -n "${TMUX:-}" ] && command -v tmux >/dev/null 2>&1; then
        local cpid
        cpid=$(tmux list-clients -F '#{client_pid}' 2>/dev/null | head -1)
        [ -n "$cpid" ] && _walk_to_bundle_id "$cpid" && return
    fi

    if [ -n "${__CFBundleIdentifier:-}" ]; then
        echo "$__CFBundleIdentifier"
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

# -----------------------------------------------------------------------------
# CUSTOMIZE HERE
# -----------------------------------------------------------------------------
# Decide the notification's title, subtitle, body, and sound based on the
# Claude Code event. Edit freely — no rebuild required.
#
# Inputs (read-only, populated by the caller below):
#   $NOTI_TYPE     — "permission_prompt", "idle_prompt", "auth_success",
#                    "elicitation_dialog", or other
#   $NOTI_MESSAGE  — the message text from Claude Code
#   $NOTI_TITLE    — the title text from Claude Code (may be empty)
#   $SESSION_LABEL — customTitle from transcript, or the cwd folder name
#
# Outputs (set these — they become CLI args to the Swift app):
#   $OUT_TITLE     — top line of the notification
#   $OUT_SUBTITLE  — second line (optional)
#   $OUT_BODY      — main text
#   $OUT_SOUND     — macOS system sound name (Blow, Tink, Glass, Funk, Ping,
#                    Pop, Purr, Sosumi, Submarine, Basso, Bottle, Frog, Hero,
#                    Morse) or "default"
#
# Tip: Sound names are from /System/Library/Sounds/. Try them in Finder.

format_notification() {
    # Default: pick emoji based on message content (Claude Code only sends
    # idle_prompt in practice, so type-based branching is rarely useful).
    case "$NOTI_MESSAGE" in
        *"waiting for your input"*)
            OUT_TITLE="💤 대기 중"
            OUT_SOUND="Tink"
            ;;
        *"permission"*|*"approve"*)
            OUT_TITLE="🔐 권한 요청"
            OUT_SOUND="Blow"
            ;;
        *"error"*|*"failed"*)
            OUT_TITLE="❌ 오류"
            OUT_SOUND="Basso"
            ;;
        *"complete"*|*"done"*|*"finished"*)
            OUT_TITLE="✅ 완료"
            OUT_SOUND="Glass"
            ;;
        *)
            OUT_TITLE="🤖 Claude Code"
            OUT_SOUND="default"
            ;;
    esac

    # Subtitle: session label (customTitle or cwd folder name)
    if [ -n "$SESSION_LABEL" ]; then
        OUT_SUBTITLE="[$SESSION_LABEL]"
    fi

    OUT_BODY="$NOTI_MESSAGE"
}
# -----------------------------------------------------------------------------

if [ -d "$APP_BUNDLE" ]; then
    killall ClaudeNotifier 2>/dev/null

    # Parse inputs for format_notification
    NOTI_TYPE=$(echo "$INPUT" | jq -r '.notification_type // "unknown"')
    NOTI_MESSAGE=$(echo "$INPUT" | jq -r '.message // "Done"')
    NOTI_TITLE=$(echo "$INPUT" | jq -r '.title // ""')
    CWD=$(echo "$INPUT" | jq -r '.cwd // ""')

    # Read customTitle from transcript, fall back to cwd folder name
    TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // ""')
    SESSION_LABEL=""
    if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
        SESSION_LABEL=$(grep '"customTitle"' "$TRANSCRIPT" 2>/dev/null | tail -1 | jq -r '.customTitle // ""')
    fi
    if [ -z "$SESSION_LABEL" ] && [ -n "$CWD" ]; then
        SESSION_LABEL=$(basename "$CWD")
    fi

    # Run user-defined formatter
    OUT_TITLE=""; OUT_SUBTITLE=""; OUT_BODY=""; OUT_SOUND=""
    format_notification

    # Temp file is cleaned up by the Swift app after reading.
    TMPFILE=$(mktemp /tmp/claude-noti-XXXXXX)
    printf '%s' "$INPUT" > "$TMPFILE"

    BUNDLE_ID=$(resolve_terminal_bundle_id)

    # Extract iTerm2 session UUID (format: w0t10p1:UUID) for per-tab activation
    ITERM_UUID=""
    if [ -n "$ITERM_SESSION_ID" ]; then
        ITERM_UUID="${ITERM_SESSION_ID#*:}"
    fi

    # Capture tmux target so the click handler can `tmux switch-client` back
    # to the exact session/window/pane that triggered this notification.
    TMUX_BIN=""
    TMUX_SOCKET=""
    TMUX_PANE_ID=""
    if [ -n "${TMUX:-}" ] && [ -n "${TMUX_PANE:-}" ]; then
        TMUX_BIN=$(command -v tmux 2>/dev/null)
        if [ -n "$TMUX_BIN" ]; then
            TMUX_SOCKET="${TMUX%%,*}"
            TMUX_PANE_ID="$TMUX_PANE"
        fi
    fi

    # Capture the Herdr terminal so the click handler can run
    # `herdr-app do agent.focus --terminal <id>`, which shows that agent's
    # space, tab and pane in the open Herdr window. The absolute path is needed
    # because the Swift app is started by `open` and does not get this PATH.
    HERDR_BIN=""
    HERDR_TERMINAL=""
    if [ -n "${HC_TERMINAL_ID:-}" ]; then
        HERDR_BIN=$(command -v herdr-app 2>/dev/null)
        [ -n "$HERDR_BIN" ] && HERDR_TERMINAL="$HC_TERMINAL_ID"
    fi

    # Build CLI args — only pass overrides that are set
    ARGS=(--data "$TMPFILE" --activate "$BUNDLE_ID")
    [ -n "$OUT_TITLE" ]    && ARGS+=(--title    "$OUT_TITLE")
    [ -n "$OUT_SUBTITLE" ] && ARGS+=(--subtitle "$OUT_SUBTITLE")
    [ -n "$OUT_BODY" ]     && ARGS+=(--body     "$OUT_BODY")
    [ -n "$OUT_SOUND" ]    && ARGS+=(--sound    "$OUT_SOUND")
    [ -n "$ITERM_UUID" ]   && ARGS+=(--iterm-session "$ITERM_UUID")
    [ -n "$TMUX_PANE_ID" ] && ARGS+=(--tmux-bin "$TMUX_BIN" --tmux-socket "$TMUX_SOCKET" --tmux-pane "$TMUX_PANE_ID")
    [ -n "$HERDR_TERMINAL" ] && ARGS+=(--herdr-bin "$HERDR_BIN" --herdr-terminal "$HERDR_TERMINAL")

    open -a "$APP_BUNDLE" --args "${ARGS[@]}" &
else
    # Fallback: osascript (click opens Script Editor)
    MESSAGE=$(echo "$INPUT" | jq -r '.message // "Done"')
    osascript - "$MESSAGE" <<'APPLESCRIPT'
on run argv
    display notification (item 1 of argv) with title "🤖 Claude Code"
end run
APPLESCRIPT
fi
