# tmuxsaver shell integration
# Source this file from ~/.bashrc or ~/.zshrc, or copy the block manually.
# Run `tmuxsaver setup-shell` to print this snippet.
#
# Effect: each tmux session gets its own history file under ~/.tmuxsaver/sessions/

if [[ -n "${TMUX:-}" ]]; then
    _ts_session=$(tmux display-message -p '#S' 2>/dev/null)
    if [[ -n "$_ts_session" ]]; then
        export HISTFILE="${TMUXSAVER_DIR:-$HOME/.tmuxsaver}/sessions/$_ts_session/history"
        mkdir -p "$(dirname "$HISTFILE")"
    fi
    unset _ts_session
fi
