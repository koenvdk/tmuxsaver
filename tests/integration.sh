#!/usr/bin/env bash
# End-to-end tests for tmuxsaver.
#
# Builds the .deb, installs it for a throwaway user the way `sudo apt install`
# would, drives real tmux sessions in bash and zsh (save, detach hook, restore,
# forget), uninstalls it non-interactively, and checks the from-source
# install.sh path. Every step asserts on what a user would actually see.
#
# Needs root (it creates and deletes a user), tmux >= 3.0, zsh and dpkg-deb.
# Meant for CI or a disposable container/VM:
#
#   sudo tests/integration.sh
#
# The same file is re-invoked as the test user (`--as-user <scenario>`) so the
# tmux parts run with that user's own login shell, rc files and tmux server.

# Many checks hand a single-quoted snippet to `bash -c`; the quoting is
# deliberate (the inner shell expands $1 and ~), so silence those notes.
# shellcheck disable=SC2016,SC2088

set -uo pipefail

TEST_USER="tmuxsaver-test"
PASS=0
FAIL=0

pass() { PASS=$(( PASS + 1 )); echo "  ok    $*"; }
fail() { FAIL=$(( FAIL + 1 )); echo "  FAIL  $*"; }
check() {            # check "description" command args...
    local desc=$1; shift
    if "$@" >/dev/null 2>&1; then pass "$desc"; else fail "$desc"; fi
}
section() { echo; echo "== $*"; }

# Poll until the visible pane content of session $1 matches regex $2.
# Shells and tmux need a moment to start and redraw; polling keeps the
# tests fast locally and tolerant of slow CI runners.
wait_pane() {
    local session=$1 pattern=$2 tries=${3:-50}
    while (( tries-- > 0 )); do
        tmux capture-pane -p -t "=$session:" 2>/dev/null | grep -Eq "$pattern" && return 0
        sleep 0.1
    done
    return 1
}
pane_last_line() { tmux capture-pane -p -t "=$1:" | grep -v '^$' | tail -1; }

# ─────────────────────────────────────────────────────────────────────────────
# User-side scenarios (run as TEST_USER via --as-user). They print ok/FAIL
# lines; the root side counts them.
# ─────────────────────────────────────────────────────────────────────────────

# Run a command in a session's shell and wait until the shell has written it
# to the per-session history (PROMPT_COMMAND / INC_APPEND_HISTORY flush).
run_in() {
    local session=$1 cmd=$2 histfile=~/.tmuxsaver/sessions/$1/history tries=50
    tmux send-keys -t "=$session:" "$cmd" Enter
    while (( tries-- > 0 )); do
        grep -qxF "$cmd" "$histfile" 2>/dev/null && return 0
        sleep 0.1
    done
    return 1
}

user_bash() {
    section "bash: live history, detach hook, restore (as $USER)"
    tmux kill-server 2>/dev/null; rm -rf ~/.tmuxsaver

    # "proj" is a prefix of "projx": every step must keep them apart.
    tmux new-session -d -s proj  -x 160 -c /tmp
    tmux new-session -d -s projx -x 160 -c /var
    wait_pane proj  '\$ *$'
    wait_pane projx '\$ *$'

    check "history is written per command (proj)"  run_in proj  'cd /etc'
    check "history is written per command (projx)" run_in projx 'cd /usr/share'
    check "sessions do not share history" \
        bash -c '! grep -q /usr/share ~/.tmuxsaver/sessions/proj/history'

    # A real client attaches and detaches: the client-detached hook saves.
    # `script` gives the client a pty. Its stdin must stay open: a background
    # job's stdin is /dev/null, and `script` would forward that EOF as ^D,
    # logging out the pane's shell and ending the session under test.
    (sleep 10 | TERM=xterm script -qfc "tmux attach -t =proj" /dev/null >/dev/null 2>&1) &
    local tries=50
    until [[ -n "$(tmux list-clients 2>/dev/null)" ]] || (( tries-- <= 0 )); do sleep 0.1; done
    tmux detach-client -s proj
    tries=50
    until [[ -s ~/.tmuxsaver/sessions/projx/workdir ]] || (( tries-- <= 0 )); do sleep 0.1; done
    check "detach hook saved proj's workdir"  grep -qx /etc        ~/.tmuxsaver/sessions/proj/workdir
    check "detach hook saved projx's workdir" grep -qx /usr/share  ~/.tmuxsaver/sessions/projx/workdir
    check "list shows both sessions" bash -c 'tmuxsaver list | grep -q "proj " && tmuxsaver list | grep -q projx'

    # Simulated reboot.
    tmux kill-server
    sleep 0.3
    local out
    out=$(tmuxsaver restore 2>&1)
    check "restore reports 2 sessions" grep -q "Restored 2 session" <<<"$out"
    wait_pane proj '\$ *$'
    check "proj restored at /etc" \
        test "$(tmux display -p -t =proj: '#{pane_current_path}')" = /etc
    check "projx restored at /usr/share" \
        test "$(tmux display -p -t =projx: '#{pane_current_path}')" = /usr/share
    check "restored pane is clean (nothing typed into it)" \
        bash -c '! tmux capture-pane -p -t =proj: | grep -q HISTFILE'
    tmux send-keys -t =proj: Up
    check "first Up-arrow recalls the last command" wait_pane proj 'cd /etc$' 20
    tmux send-keys -t =proj: C-u

    out=$(tmuxsaver restore 2>&1)
    check "second restore skips existing sessions" grep -q "Restored 0 session" <<<"$out"
    check "second restore prints no workdir warning" bash -c '! grep -q WARNING <<<"$1"' _ "$out"

    tmuxsaver forget projx >/dev/null 2>&1
    check "forget removes only projx" \
        bash -c '[[ ! -e ~/.tmuxsaver/sessions/projx && -d ~/.tmuxsaver/sessions/proj ]]'
    tmux kill-server
}

user_zsh() {
    section "zsh: save and restore (as $USER)"
    tmux kill-server 2>/dev/null; rm -rf ~/.tmuxsaver
    tmux -f /dev/null start-server \; set -g exit-empty off \; set -g default-shell /usr/bin/zsh
    tmux new-session -d -s zs -x 160 -c /tmp
    wait_pane zs '% *$'
    check "zsh history is written per command" run_in zs 'cd /etc'
    tmuxsaver save -q
    tmux kill-server
    sleep 0.3

    tmux -f /dev/null start-server \; set -g exit-empty off \; set -g default-shell /usr/bin/zsh
    tmuxsaver restore -q
    wait_pane zs '% *$'
    check "zsh session restored at /etc" \
        test "$(tmux display -p -t =zs: '#{pane_current_path}')" = /etc
    check "zsh restored pane is clean" bash -c '! tmux capture-pane -p -t =zs: | grep -q HISTFILE'
    tmux send-keys -t =zs: Up
    check "zsh first Up-arrow recalls the last command" wait_pane zs 'cd /etc$' 20
    tmux kill-server
}

user_from_source() {
    section "from-source install.sh (as $USER)"
    local src=$1
    tmux kill-server 2>/dev/null
    (cd "$src" && ./install.sh --no-systemd --no-linger </dev/null >/dev/null 2>&1)
    check "install.sh installs the binary"  test -x ~/.local/bin/tmuxsaver
    check "setup-shell finds its snippet"   bash -c '~/.local/bin/tmuxsaver setup-shell | grep -q "tmuxsaver:begin"'
    check "tmux hook uses the absolute path" \
        grep -qF "'$HOME/.local/bin/tmuxsaver' save" ~/.tmux.conf
    (cd "$src" && ./install.sh --no-systemd --no-linger </dev/null >/dev/null 2>&1)
    check "re-running install.sh keeps one shell block" \
        test "$(grep -c '^# tmuxsaver:begin' ~/.bashrc)" = 1
    check "re-running install.sh keeps one tmux hook" \
        test "$(grep -c 'set-hook.*tmuxsaver' ~/.tmux.conf)" = 1
}

if [[ "${1:-}" == "--as-user" ]]; then
    shift
    scenario=$1; shift
    "user_$scenario" "$@"
    echo "RESULT pass=$PASS fail=$FAIL"
    exit 0
fi

# ─────────────────────────────────────────────────────────────────────────────
# Root side
# ─────────────────────────────────────────────────────────────────────────────

[[ $EUID -eq 0 ]] || { echo "Run as root (it creates a throwaway user): sudo $0" >&2; exit 2; }
for tool in tmux zsh dpkg-deb script; do
    command -v "$tool" >/dev/null || { echo "Missing required tool: $tool" >&2; exit 2; }
done

REPO="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
chmod 755 "$WORK"
HOME_DIR="/home/$TEST_USER"

cleanup() {
    pkill -u "$TEST_USER" 2>/dev/null
    userdel -r "$TEST_USER" 2>/dev/null
    dpkg -P tmuxsaver >/dev/null 2>&1
    rm -rf "$WORK"
}
trap cleanup EXIT

# Run a scenario as the test user and fold its ok/FAIL counts into ours.
as_user() {
    local out
    out=$(su - "$TEST_USER" -c "bash $WORK/integration.sh --as-user $*" 2>&1)
    grep -v '^RESULT' <<<"$out"
    local p f
    p=$(sed -n 's/^RESULT pass=\([0-9]*\) fail=\([0-9]*\)$/\1/p' <<<"$out")
    f=$(sed -n 's/^RESULT pass=\([0-9]*\) fail=\([0-9]*\)$/\2/p' <<<"$out")
    if [[ -z "$p" ]]; then fail "scenario '$1' did not finish"; return; fi
    PASS=$(( PASS + p )); FAIL=$(( FAIL + f ))
}

section "build"
cp "$0" "$WORK/integration.sh"; chmod 755 "$WORK/integration.sh"
cp -r "$REPO" "$WORK/src"
make -s -C "$WORK/src" deb >/dev/null
debs=("$WORK"/src/tmuxsaver_*_all.deb)
DEB=${debs[0]}
check "make deb produced a package" test -f "$DEB"
chmod -R a+rX "$WORK/src"

section "install the .deb for $TEST_USER (python3 blocked)"
pkill -u "$TEST_USER" 2>/dev/null; userdel -r "$TEST_USER" 2>/dev/null
useradd -m -s /bin/bash "$TEST_USER"
cp /etc/skel/.bashrc "$HOME_DIR/.bashrc"
echo 'HISTSIZE=1000' > "$HOME_DIR/.zshrc"
chown "$TEST_USER:" "$HOME_DIR/.bashrc" "$HOME_DIR/.zshrc"
cp "$HOME_DIR/.bashrc" "$WORK/bashrc.orig"
cp "$HOME_DIR/.zshrc"  "$WORK/zshrc.orig"

# The package must not need python3 (it isn't a declared dependency).
mkdir -p "$WORK/nopy"
printf '#!/bin/sh\necho "python3 must not be called" >&2\nexit 127\n' > "$WORK/nopy/python3"
chmod +x "$WORK/nopy/python3"

install_deb() {
    PATH="$WORK/nopy:$PATH" SUDO_USER="$TEST_USER" TMUXSAVER_NO_LINGER=1 \
        DEBIAN_FRONTEND=noninteractive dpkg -i "$DEB" </dev/null >"$WORK/dpkg.log" 2>&1
}
check "dpkg -i succeeds" install_deb
check "package is installed"  bash -c 'dpkg -s tmuxsaver | grep -q "Status: install ok installed"'
check "shell hook added to .bashrc" test "$(grep -c '^# tmuxsaver:begin' "$HOME_DIR/.bashrc")" = 1
check "shell hook added to .zshrc"  test "$(grep -c '^# tmuxsaver:begin' "$HOME_DIR/.zshrc")" = 1
check ".bashrc still owned by the user" test "$(stat -c %U "$HOME_DIR/.bashrc")" = "$TEST_USER"
check "tmux hook uses /usr/bin/tmuxsaver" grep -qF "'/usr/bin/tmuxsaver' save" "$HOME_DIR/.tmux.conf"
check "reinstall succeeds" install_deb
check "reinstall keeps one shell block" test "$(grep -c '^# tmuxsaver:begin' "$HOME_DIR/.bashrc")" = 1
check "reinstall keeps one tmux hook"   test "$(grep -c 'set-hook.*tmuxsaver' "$HOME_DIR/.tmux.conf")" = 1

as_user bash
as_user zsh

section "uninstall without a terminal"
check "dpkg -r succeeds with no tty" \
    bash -c 'SUDO_USER="$1" DEBIAN_FRONTEND=noninteractive dpkg -r tmuxsaver </dev/null >/dev/null 2>&1' _ "$TEST_USER"
check ".bashrc restored byte-for-byte" cmp -s "$WORK/bashrc.orig" "$HOME_DIR/.bashrc"
check ".zshrc restored byte-for-byte"  cmp -s "$WORK/zshrc.orig"  "$HOME_DIR/.zshrc"
check "tmux hook removed" bash -c '! grep -q tmuxsaver "$1"' _ "$HOME_DIR/.tmux.conf"
check "saved sessions kept" test -d "$HOME_DIR/.tmuxsaver/sessions/zs"

as_user from_source "$WORK/src"

echo
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
