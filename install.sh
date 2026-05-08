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
#   --binary-only     Only install the binary; equivalent to --no-shell-hook --no-tmux-hook --no-systemd
#   --prefix <dir>    Install binary to <dir>/bin (default: ~/.local)

set -euo pipefail

PREFIX="$HOME/.local"
DO_SYSTEMD=1
DO_SHELL=1
DO_TMUX=1

while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-systemd)     DO_SYSTEMD=0; shift ;;
        --no-shell-hook)  DO_SHELL=0;   shift ;;
        --no-tmux-hook)   DO_TMUX=0;    shift ;;
        --binary-only)    DO_SYSTEMD=0; DO_SHELL=0; DO_TMUX=0; shift ;;
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

BIN_DIR="$PREFIX/bin"
SYSTEMD_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
SCRIPT_DIR="$(dirname "$(realpath "$0")")"

# ── Binary ──────────────────────────────────────────────────────────────────
mkdir -p "$BIN_DIR"
install -m 755 "$SCRIPT_DIR/tmuxsaver" "$BIN_DIR/tmuxsaver"
echo "Installed: $BIN_DIR/tmuxsaver"

# ── Shell hook (per-session HISTFILE) ───────────────────────────────────────
if [[ $DO_SHELL -eq 1 ]]; then
    SNIPPET_FILE="$SCRIPT_DIR/shell/tmuxsaver.sh"
    for rcfile in "$HOME/.bashrc" "$HOME/.zshrc"; do
        [[ -f "$rcfile" ]] || continue
        # Idempotent: strip any existing tmuxsaver block (old or new style),
        # then re-append the current snippet.
        python3 - "$rcfile" "$SNIPPET_FILE" <<'PYEOF'
import re, sys, pathlib
rcfile  = pathlib.Path(sys.argv[1])
snippet = pathlib.Path(sys.argv[2]).read_text()
content = rcfile.read_text()
content = re.sub(r'\n# tmuxsaver:begin.*?# tmuxsaver:end\n', '\n', content, flags=re.DOTALL)
content = re.sub(r'\n# tmuxsaver shell integration.*?^fi\n', '\n', content, flags=re.DOTALL | re.MULTILINE)
rcfile.write_text(content.rstrip('\n') + '\n\n' + snippet)
PYEOF
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
            install -m 644 "$SCRIPT_DIR/systemd/$unit" "$SYSTEMD_DIR/$unit"
            echo "Installed: $SYSTEMD_DIR/$unit"
        done
        systemctl --user daemon-reload
        systemctl --user enable --now tmuxsaver-save.service
        systemctl --user enable --now tmuxsaver-restore.service
        echo "Enabled tmuxsaver-save.service (save on logout)"
        echo "Enabled tmuxsaver-restore.service (restore on login)"
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
echo "Optional — auto-attach to restored sessions on login:"
echo "  Add TMUXSAVER_AUTO_ATTACH=1 to your ~/.bashrc or ~/.profile"
