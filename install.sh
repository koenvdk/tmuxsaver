#!/usr/bin/env bash
# tmuxsaver installer
#
# Usage: ./install.sh [--systemd] [--shell-hook] [--prefix <dir>]
#
#   --systemd      Install and enable the systemd user services
#                  (save on logout, restore on login)
#   --shell-hook   Append the shell integration snippet to ~/.bashrc and/or
#                  ~/.zshrc so each tmux session gets its own history file
#   --prefix <dir> Install binary to <dir>/bin  (default: ~/.local)

set -euo pipefail

PREFIX="$HOME/.local"
DO_SYSTEMD=0
DO_SHELL=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --systemd)     DO_SYSTEMD=1; shift ;;
        --shell-hook)  DO_SHELL=1;   shift ;;
        --prefix)
            [[ -n "${2:-}" ]] || { echo "ERROR: --prefix requires a path"; exit 1; }
            PREFIX="$2"; shift 2
            ;;
        -h|--help)
            sed -n '2,8p' "$0"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

BIN_DIR="$PREFIX/bin"
SYSTEMD_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"

# ── Binary ──────────────────────────────────────────────────────────────────
mkdir -p "$BIN_DIR"
install -m 755 "$(dirname "$0")/tmuxsaver" "$BIN_DIR/tmuxsaver"
echo "Installed: $BIN_DIR/tmuxsaver"

# ── Shell hook ──────────────────────────────────────────────────────────────
if [[ $DO_SHELL -eq 1 ]]; then
    SNIPPET=$(cat "$(dirname "$0")/shell/tmuxsaver.sh")
    MARKER="# tmuxsaver shell integration"

    for rcfile in "$HOME/.bashrc" "$HOME/.zshrc"; do
        [[ -f "$rcfile" ]] || continue
        if grep -qF "$MARKER" "$rcfile"; then
            echo "Shell hook already present in $rcfile — skipping"
        else
            printf '\n%s\n' "$SNIPPET" >> "$rcfile"
            echo "Shell hook appended to $rcfile"
        fi
    done
fi

# ── Systemd user services ────────────────────────────────────────────────────
if [[ $DO_SYSTEMD -eq 1 ]]; then
    command -v systemctl &>/dev/null || { echo "WARNING: systemctl not found; skipping systemd setup"; }

    mkdir -p "$SYSTEMD_DIR"
    SCRIPT_DIR="$(dirname "$0")/systemd"

    for unit in tmuxsaver-save.service tmuxsaver-restore.service; do
        install -m 644 "$SCRIPT_DIR/$unit" "$SYSTEMD_DIR/$unit"
        echo "Installed: $SYSTEMD_DIR/$unit"
    done

    systemctl --user daemon-reload
    systemctl --user enable --now tmuxsaver-save.service
    echo "Enabled tmuxsaver-save.service (saves sessions on logout)"

    read -r -p "Also enable auto-restore on login? [y/N] " answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        systemctl --user enable --now tmuxsaver-restore.service
        echo "Enabled tmuxsaver-restore.service (restores sessions on login)"
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
echo "For per-session bash/zsh history, run:"
echo "  tmuxsaver setup-shell # prints the snippet to add to your shell rc"
