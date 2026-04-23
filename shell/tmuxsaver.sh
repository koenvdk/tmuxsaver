# tmuxsaver shell integration — source from ~/.bashrc or ~/.zshrc
# Run `tmuxsaver setup-shell` to print this snippet.

if [[ -n "${TMUX:-}" ]]; then
    # Inside tmux: give each session its own history file
    _ts_session=$(tmux display-message -p '#S' 2>/dev/null)
    if [[ -n "$_ts_session" ]]; then
        export HISTFILE="${TMUXSAVER_DIR:-$HOME/.tmuxsaver}/sessions/$_ts_session/history"
        mkdir -p "$(dirname "$HISTFILE")"
    fi
    unset _ts_session
elif [[ -z "${TMUXSAVER_NO_ATTACH:-}" ]] && command -v tmux &>/dev/null; then
    # Outside tmux: restore saved sessions and auto-attach
    _ts_dir="${TMUXSAVER_DIR:-$HOME/.tmuxsaver}/sessions"
    if [[ -d "$_ts_dir" ]] && [[ -n "$(ls -A "$_ts_dir" 2>/dev/null)" ]]; then
        if ! tmux has-session 2>/dev/null; then
            tmux start-server
            tmuxsaver restore --quiet 2>/dev/null
        fi
        exec tmux attach
    fi
    unset _ts_dir
fi
