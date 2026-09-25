#!/usr/bin/env bash
# tmuxsaver installer (from-source / non-Debian path)
#
# Installs the files for your user, then runs `tmuxsaver setup`, which adds:
#   - shell integration in ~/.bashrc / ~/.zshrc (per-session HISTFILE)
#   - the tmux save-on-detach hook in ~/.tmux.conf
#   - systemd user services (save on logout, restore on login)
#   - lingering, so live sessions survive a full logout (asks first)
#
# Usage: ./install.sh [options]
#
#   --no-shell-hook   Skip ~/.bashrc / ~/.zshrc integration
#   --no-tmux-hook    Skip ~/.tmux.conf save-on-detach hook
#   --no-systemd      Skip systemd user services
#   --no-linger       Don't enable systemd lingering (sessions won't survive full logout)
#   --binary-only     Only install the files; don't run `tmuxsaver setup`
#   --prefix <dir>    Install binary to <dir>/bin (default: ~/.local)
#
# Undo the per-user parts any time with `tmuxsaver unsetup`.

set -euo pipefail

PREFIX="$HOME/.local"
DO_SETUP=1
DO_SYSTEMD=1
SETUP_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-shell-hook|--no-tmux-hook|--no-linger)
            SETUP_ARGS+=("$1"); shift ;;
        --no-systemd)
            DO_SYSTEMD=0; SETUP_ARGS+=("$1"); shift ;;
        --binary-only)
            DO_SETUP=0; DO_SYSTEMD=0; shift ;;
        --prefix)
            [[ -n "${2:-}" ]] || { echo "ERROR: --prefix requires a path"; exit 1; }
            PREFIX="$2"; shift 2
            ;;
        -h|--help)
            sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "Unknown option: $1 (try --help)"; exit 1 ;;
    esac
done

BIN_DIR="$PREFIX/bin"
SYSTEMD_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
SCRIPT_DIR="$(dirname "$(realpath "$0")")"

# ── Files ───────────────────────────────────────────────────────────────────
mkdir -p "$BIN_DIR"
install -m 755 "$SCRIPT_DIR/tmuxsaver" "$BIN_DIR/tmuxsaver"
echo "Installed: $BIN_DIR/tmuxsaver"

# Shell snippet, where `tmuxsaver setup-shell` looks for it (<prefix>/share).
install -Dm 644 "$SCRIPT_DIR/shell/tmuxsaver.sh" "$PREFIX/share/tmuxsaver/tmuxsaver.sh"
echo "Installed: $PREFIX/share/tmuxsaver/tmuxsaver.sh"

if [[ $DO_SYSTEMD -eq 1 ]]; then
    mkdir -p "$SYSTEMD_DIR"
    for unit in tmuxsaver-save.service tmuxsaver-restore.service; do
        # The units reference /usr/bin/tmuxsaver (the .deb location);
        # point them at the binary we just installed instead.
        sed "s|/usr/bin/tmuxsaver|$BIN_DIR/tmuxsaver|g" \
            "$SCRIPT_DIR/systemd/$unit" > "$SYSTEMD_DIR/$unit"
        chmod 644 "$SYSTEMD_DIR/$unit"
        echo "Installed: $SYSTEMD_DIR/$unit"
    done
fi

# ── Per-user integration ────────────────────────────────────────────────────
echo ""
if [[ $DO_SETUP -eq 1 ]]; then
    "$BIN_DIR/tmuxsaver" setup ${SETUP_ARGS[@]+"${SETUP_ARGS[@]}"}
else
    echo "Files installed. Run '$BIN_DIR/tmuxsaver setup' to enable the hooks and services."
fi

echo ""
echo "Make sure $BIN_DIR is in your PATH."
echo "Quick reference: tmuxsaver save | restore | list | forget <name> | unsetup"
