# tmuxsaver:begin — shell integration (managed by tmuxsaver, do not edit this block)
if [[ -n "${TMUX:-}" ]]; then
    # Inside tmux: give each session its own history file.
    # Target our own pane explicitly: without -t, tmux resolves the "current
    # client", which can be a different session when several are attached.
    _ts_session=$(tmux display-message -p -t "${TMUX_PANE:-}" '#S' 2>/dev/null)
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
fi
# Note: sessions are restored on login by tmuxsaver-restore.service (systemd),
# WITHOUT attaching. Open a normal shell and run `tmux attach` when you want in.
# tmuxsaver:end
