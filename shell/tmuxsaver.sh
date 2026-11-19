# tmuxsaver:begin — shell integration (managed by tmuxsaver, do not edit this block)
if [[ -n "${TMUX:-}" ]]; then
    # Inside tmux: give each session its own history file.
    # Target our own pane explicitly: without -t, tmux resolves the "current
    # client", which can be a different session when several are attached.
    _ts_session=$(tmux display-message -p -t "${TMUX_PANE:-}" '#S' 2>/dev/null)
    if [[ -n "$_ts_session" ]]; then
        # Same directory naming as `tmuxsaver`: "%" -> %25, "/" -> %2F.
        _ts_session=${_ts_session//\%/%25}   # \% : a bare % anchors to the end in zsh
        _ts_session=${_ts_session//\//%2F}
        export HISTFILE="${TMUXSAVER_DIR:-$HOME/.tmuxsaver}/sessions/$_ts_session/history"
        (umask 077 && mkdir -p "$(dirname "$HISTFILE")")   # history is private
        # Flush history to the per-session file after every command, not only
        # on shell exit — so a long-running session's history is always on disk
        # and `tmuxsaver save` never reports it missing.
        if [[ -n "${BASH_VERSION:-}" ]]; then
            # PROMPT_COMMAND may be a scalar or, from bash 5.1 (and on systems
            # whose /etc/profile.d sets it, e.g. Ubuntu 26.04), an array.
            # Idempotent across re-sourcing.
            if [[ "$(declare -p PROMPT_COMMAND 2>/dev/null)" == "declare -a"* ]]; then
                [[ "${PROMPT_COMMAND[*]}" == *"history -a"* ]] \
                    || PROMPT_COMMAND=("history -a" "${PROMPT_COMMAND[@]}")
            elif [[ "${PROMPT_COMMAND:-}" != *"history -a"* ]]; then
                # shellcheck disable=SC2178,SC2128  # scalar here; the array case is above
                PROMPT_COMMAND="history -a${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
            fi
        elif [[ -n "${ZSH_VERSION:-}" ]]; then
            setopt INC_APPEND_HISTORY 2>/dev/null || true
            [[ ${SAVEHIST:-0} -gt 0 ]] || SAVEHIST=2000
            # zsh keeps (and reloads) only HISTSIZE entries, which defaults
            # to 30: without this a restored session would get back just the
            # last 30 commands.
            [[ ${HISTSIZE:-0} -ge $SAVEHIST ]] || HISTSIZE=$SAVEHIST
        fi
    fi
    unset _ts_session
fi
# Note: sessions are restored on login by tmuxsaver-restore.service (systemd),
# WITHOUT attaching. Open a normal shell and run `tmux attach` when you want in.
# tmuxsaver:end
