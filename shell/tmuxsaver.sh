# tmuxsaver:begin — shell integration (managed by tmuxsaver, do not edit this block)
if [[ -n "${TMUX:-}" ]]; then
    # Inside tmux: give each session its own history file
    _ts_session=$(tmux display-message -p '#S' 2>/dev/null)
    if [[ -n "$_ts_session" ]]; then
        export HISTFILE="${TMUXSAVER_DIR:-$HOME/.tmuxsaver}/sessions/$_ts_session/history"
        mkdir -p "$(dirname "$HISTFILE")"
        # Flush history to the per-session file after every command, not only
        # on shell exit — so a long-running session's history is always on disk
        # and `tmuxsaver save` never reports it missing.
        if [[ -n "${BASH_VERSION:-}" ]]; then
            # Scalar PROMPT_COMMAND only; if it's an array (rare) leave it alone
            # and fall back to the on-exit write. Idempotent across re-sourcing.
            if [[ "$(declare -p PROMPT_COMMAND 2>/dev/null)" != "declare -a"* ]] \
               && [[ "${PROMPT_COMMAND:-}" != *"history -a"* ]]; then
                PROMPT_COMMAND="history -a${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
            fi
        elif [[ -n "${ZSH_VERSION:-}" ]]; then
            setopt INC_APPEND_HISTORY 2>/dev/null || true
            [[ ${SAVEHIST:-0} -gt 0 ]] || SAVEHIST=2000
        fi
    fi
    unset _ts_session
elif [[ "${TMUXSAVER_AUTO_ATTACH:-0}" == "1" ]] && command -v tmux &>/dev/null; then
    # Outside tmux: restore saved sessions and auto-attach (opt-in: set TMUXSAVER_AUTO_ATTACH=1)
    _ts_dir="${TMUXSAVER_DIR:-$HOME/.tmuxsaver}/sessions"
    if [[ -d "$_ts_dir" ]] && [[ -n "$(ls -A "$_ts_dir" 2>/dev/null)" ]]; then
        if ! tmux has-session 2>/dev/null; then
            tmux start-server
            tmuxsaver restore --quiet 2>/dev/null
        fi
        # Only attach if sessions actually exist — never exec into a void
        if tmux has-session 2>/dev/null; then
            exec tmux attach
        fi
    fi
    unset _ts_dir
fi
# tmuxsaver:end
