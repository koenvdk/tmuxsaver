#!/usr/bin/env bash
# tmuxsaver installer (from-source / non-Debian path)
#
# By default this installs everything:
#   - the binary to ~/.local/bin
#   - shell integration in ~/.bashrc and ~/.zshrc (per-session HISTFILE)
#   - tmux save-on-detach hook in ~/.tmux.conf
#   - systemd user services (save on logout, restore on login)
#
# Usage: ./install.sh [options]
#
#   --no-shell-hook   Skip ~/.bashrc / ~/.zshrc integration
#   --no-tmux-hook    Skip ~/.tmux.conf save-on-detach hook
#   --no-systemd      Skip systemd user services
#   --no-linger       Don't enable systemd lingering (sessions won't survive full logout)
#   --binary-only     Only install the binary; equivalent to --no-shell-hook --no-tmux-hook --no-systemd
#   --prefix <dir>    Install binary to <dir>/bin (default: ~/.local)
#
# Lingering (enabled by default with --systemd) keeps your user systemd manager
# — and the tmux server it runs — alive after your last logout. Opt out with
# --no-linger or TMUXSAVER_NO_LINGER=1.

set -euo pipefail

PREFIX="$HOME/.local"
DO_SYSTEMD=1
DO_SHELL=1
DO_TMUX=1
DO_LINGER=1

while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-systemd)     DO_SYSTEMD=0; shift ;;
        --no-shell-hook)  DO_SHELL=0;   shift ;;
        --no-tmux-hook)   DO_TMUX=0;    shift ;;
        --no-linger)      DO_LINGER=0;  shift ;;
        --binary-only)    DO_SYSTEMD=0; DO_SHELL=0; DO_TMUX=0; DO_LINGER=0; shift ;;
        --prefix)
            [[ -n "${2:-}" ]] || { echo "ERROR: --prefix requires a path"; exit 1; }
            PREFIX="$2"; shift 2
            ;;
        -h|--help)
            sed -n '2,18p' "$0"
            exit 0
            ;;
        *) echo "Unknown option: $1 (try --help)"; exit 1 ;;
    esac
done

# Environment opt-out (mirrors the .deb's TMUXSAVER_NO_LINGER=1).
[[ "${TMUXSAVER_NO_LINGER:-0}" == "1" ]] && DO_LINGER=0

BIN_DIR="$PREFIX/bin"
SYSTEMD_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
SCRIPT_DIR="$(dirname "$(realpath "$0")")"

# Print rc file $1 with every tmuxsaver shell block removed — the current
# "# tmuxsaver:begin" … "# tmuxsaver:end" form and the old unterminated form
# that ran to its closing `fi` — and with trailing blank lines dropped.
# A block whose closing line is missing is kept as-is rather than taking the
# rest of the file with it.
strip_shell_hook() {
    awk '
        skip != "" {
            block = block $0 "\n"
            if ((skip == "end" && /^# tmuxsaver:end/) || (skip == "fi" && /^fi$/)) {
                skip = ""; block = ""
            }
            next
        }
        /^# tmuxsaver:begin/             { skip = "end"; block = $0 "\n"; next }
        /^# tmuxsaver shell integration/ { skip = "fi";  block = $0 "\n"; next }
        /^$/ { blank = blank "\n"; next }
        { printf "%s", blank; blank = ""; print }
        END { if (skip != "") printf "%s%s", blank, block }
    ' "$1"
}

# Replace file $1's contents with stdin. Writing through the existing file
# (rather than swapping in a new one, as `sed -i` does) keeps its owner, mode
# and any symlink — e.g. a dotfile manager's ~/.bashrc — intact.
overwrite() {
    local tmp
    tmp=$(mktemp)
    cat > "$tmp" && cat "$tmp" > "$1"
    rm -f "$tmp"
}

# ── Binary ──────────────────────────────────────────────────────────────────
mkdir -p "$BIN_DIR"
install -m 755 "$SCRIPT_DIR/tmuxsaver" "$BIN_DIR/tmuxsaver"
echo "Installed: $BIN_DIR/tmuxsaver"

# Shell snippet, where `tmuxsaver setup-shell` looks for it (<prefix>/share).
install -Dm 644 "$SCRIPT_DIR/shell/tmuxsaver.sh" "$PREFIX/share/tmuxsaver/tmuxsaver.sh"
echo "Installed: $PREFIX/share/tmuxsaver/tmuxsaver.sh"

# ── Shell hook (per-session HISTFILE) ───────────────────────────────────────
if [[ $DO_SHELL -eq 1 ]]; then
    SNIPPET_FILE="$SCRIPT_DIR/shell/tmuxsaver.sh"
    for rcfile in "$HOME/.bashrc" "$HOME/.zshrc"; do
        [[ -f "$rcfile" ]] || continue
        # Idempotent: strip any existing tmuxsaver block (old or new style),
        # then re-append the current snippet.
        { strip_shell_hook "$rcfile"; echo; cat "$SNIPPET_FILE"; } | overwrite "$rcfile"
        echo "Shell hook updated in $rcfile"
    done
fi

# ── tmux save-on-detach hook ────────────────────────────────────────────────
if [[ $DO_TMUX -eq 1 ]]; then
    "$BIN_DIR/tmuxsaver" setup-tmux 2>/dev/null || true
fi

# ── Systemd user services ───────────────────────────────────────────────────
if [[ $DO_SYSTEMD -eq 1 ]]; then
    if ! command -v systemctl &>/dev/null; then
        echo "WARNING: systemctl not found; skipping systemd setup"
    else
        mkdir -p "$SYSTEMD_DIR"
        for unit in tmuxsaver-save.service tmuxsaver-restore.service; do
            # The units reference /usr/bin/tmuxsaver (the .deb location);
            # point them at the binary we just installed instead.
            sed "s|/usr/bin/tmuxsaver|$BIN_DIR/tmuxsaver|g" \
                "$SCRIPT_DIR/systemd/$unit" > "$SYSTEMD_DIR/$unit"
            chmod 644 "$SYSTEMD_DIR/$unit"
            echo "Installed: $SYSTEMD_DIR/$unit"
        done
        systemctl --user daemon-reload
        systemctl --user enable --now tmuxsaver-save.service
        systemctl --user enable --now tmuxsaver-restore.service
        echo "Enabled tmuxsaver-save.service (save on logout)"
        echo "Enabled tmuxsaver-restore.service (restore on login)"

        # ── Lingering: keep the tmux server alive past your last logout ──────
        # The restore service runs the tmux server under your systemd user
        # manager; without linger, logind stops that manager (and the server)
        # when your last session ends. Enabling linger persists it. Prompt when
        # we have a TTY (default yes); honor --no-linger / TMUXSAVER_NO_LINGER=1.
        if [[ $DO_LINGER -eq 1 ]] && command -v loginctl &>/dev/null; then
            ans=y
            if [[ -t 0 ]]; then
                read -r -p "Enable lingering so tmux sessions survive a full logout? [Y/n] " ans || ans=y
                ans=${ans:-y}
            fi
            if [[ "$ans" =~ ^[Yy]$ ]]; then
                if loginctl enable-linger "$USER" 2>/dev/null; then
                    echo "Enabled lingering for $USER (undo: loginctl disable-linger $USER)"
                else
                    echo "WARNING: could not enable lingering; run: sudo loginctl enable-linger $USER"
                fi
            else
                echo "Skipped lingering — live sessions won't survive your LAST logout until you run:"
                echo "  loginctl enable-linger $USER"
            fi
        fi
    fi
fi

echo ""
echo "Done. Make sure $BIN_DIR is in your PATH."
echo ""
echo "Quick start:"
echo "  tmuxsaver save        # save current sessions"
echo "  tmuxsaver restore     # restore saved sessions"
echo "  tmuxsaver list        # show what is saved"
echo ""
if [[ $DO_SHELL -eq 1 ]]; then
    echo "Open a new shell (or 'source ~/.bashrc') for the per-session history hook to take effect."
    echo ""
fi
echo "Sessions restore on login via the systemd service (without attaching);"
echo "run 'tmux attach' when you want to enter them."
