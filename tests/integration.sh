#!/usr/bin/env bash
# End-to-end tests for tmuxsaver.
#
# Builds the .deb, installs it the way `sudo apt install` would, runs the
# per-user `tmuxsaver setup` for a throwaway user, drives real tmux sessions in
# bash and zsh (save, detach hook, restore, forget), checks `unsetup` and the
# non-interactive uninstall, and the from-source install.sh path. Every step
# asserts on what a user would actually see.
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
enc() { local n=${1//\%/%25}; printf '%s' "${n//\//%2F}"; }

run_in() {
    local session=$1 cmd=$2 tries=50
    local histfile
    histfile=~/.tmuxsaver/sessions/$(enc "$1")/history
    tmux send-keys -t "=$session:" "$cmd" Enter
    while (( tries-- > 0 )); do
        grep -qxF "$cmd" "$histfile" 2>/dev/null && return 0
        sleep 0.1
    done
    diagnose "$session"
    return 1
}

# Print what the shell in session $1 actually sees, so a CI failure log says
# why history went missing instead of only that it did.
diagnose() {
    local session=$1
    tmux send-keys -t "=$session:" \
        ' echo "@@ shell=$0 HISTFILE=$HISTFILE TMUX_PANE=$TMUX_PANE PROMPT_COMMAND=${PROMPT_COMMAND:-}"' Enter
    sleep 1
    # fd 3 is the scenario's real stdout: `check` silences fds 1 and 2.
    {
        echo "  --- diagnostics for session '$session':"
        tmux capture-pane -p -t "=$session:" -S -30 | grep -v '^$' | sed 's/^/  | /'
        echo "  | pane runs: $(tmux display -p -t "=$session:" '#{pane_current_command}'), default-shell: $(tmux show -gv default-shell)"
        echo "  | sessions dir: $(find ~/.tmuxsaver -maxdepth 3 2>/dev/null | tr '\n' ' ')"
        echo "  | rc files: $(find ~ -maxdepth 1 -name '.*' -printf '%f ')"
    } >&3
}

user_setup() {
    section "tmuxsaver setup (as $USER)"
    local out
    out=$(tmuxsaver setup --no-linger 2>&1)
    check "setup exits 0 without a systemd user manager" test $? -eq 0
    # Whether `su -` gives this user a systemd user manager depends on the
    # host (GitHub's runner does, most containers don't). Test whichever
    # path setup took.
    if systemctl --user show-environment &>/dev/null; then
        check "setup enables tmuxsaver-save.service" systemctl --user is-enabled -q tmuxsaver-save.service
        check "setup starts tmuxsaver-save.service (ExecStop saves at logout)" \
            systemctl --user is-active -q tmuxsaver-save.service
        check "setup enables tmuxsaver-restore.service" systemctl --user is-enabled -q tmuxsaver-restore.service
        check "save unit is ordered after restore (stops first at shutdown)" \
            bash -c 'systemctl --user show -p After tmuxsaver-save.service | grep -q tmuxsaver-restore.service'
    else
        check "setup explains the skipped services" grep -q "No systemd user manager" <<<"$out"
    fi
    check "hook added to .bashrc once" test "$(grep -c '^# tmuxsaver:begin' ~/.bashrc)" = 1
    check "hook added to .zshrc once"  test "$(grep -c '^# tmuxsaver:begin' ~/.zshrc)" = 1
    check ".profile left alone (it already loads .bashrc)" bash -c '! grep -q tmuxsaver ~/.profile'
    check "tmux hook uses /usr/bin/tmuxsaver" grep -qF "'/usr/bin/tmuxsaver' save" ~/.tmux.conf
    tmuxsaver setup --no-linger -q >/dev/null 2>&1
    check "second setup keeps one shell block" test "$(grep -c '^# tmuxsaver:begin' ~/.bashrc)" = 1
    check "second setup keeps one tmux hook block"   test "$(grep -c '^# tmuxsaver:' ~/.tmux.conf) $(grep -c 'set-hook.*tmuxsaver' ~/.tmux.conf)" = "1 2"
}

# $1/$2: pristine copies of .bashrc/.zshrc from before setup.
user_unsetup() {
    section "tmuxsaver unsetup (as $USER)"
    tmuxsaver unsetup >/dev/null 2>&1
    check "unsetup restores .bashrc byte-for-byte" cmp -s "$1" ~/.bashrc
    check "unsetup restores .zshrc byte-for-byte"  cmp -s "$2" ~/.zshrc
    check "unsetup removes the tmux.conf setup created" test ! -e ~/.tmux.conf
    check "unsetup keeps saved sessions" test -d ~/.tmuxsaver/sessions
    if systemctl --user show-environment &>/dev/null; then
        check "unsetup disables the services" \
            bash -c '! systemctl --user is-enabled -q tmuxsaver-save.service && ! systemctl --user is-enabled -q tmuxsaver-restore.service'
    fi
    tmuxsaver setup --no-linger -q >/dev/null 2>&1   # leave it set up for the uninstall test
}

# A login bash that reads a ~/.bash_profile which never sources ~/.bashrc
# (GitHub's runner image ships one): the hook must go there too.
user_bash_profile() {
    section "~/.bash_profile that ignores .bashrc (as $USER)"
    tmux kill-server 2>/dev/null; rm -rf ~/.tmuxsaver
    printf 'export PATH="$HOME/bin:$PATH"\n' > ~/.bash_profile
    cp ~/.bash_profile ~/.bash_profile.orig
    tmuxsaver setup --no-linger -q >/dev/null 2>&1
    check "setup hooks .bash_profile" grep -q '^# tmuxsaver:begin' ~/.bash_profile
    tmux new-session -d -s bp -x 160 -c /tmp
    wait_pane bp '\$ *$'
    check "history recorded in a login shell that skips .bashrc" run_in bp 'cd /etc'
    tmux kill-server
    tmuxsaver unsetup -q >/dev/null 2>&1
    check "unsetup restores .bash_profile" cmp -s ~/.bash_profile.orig ~/.bash_profile
    rm -f ~/.bash_profile ~/.bash_profile.orig
    tmuxsaver setup --no-linger -q >/dev/null 2>&1
}

# Dotfile managers symlink ~/.tmux.conf; editing must go through the link.
user_symlinked_tmux_conf() {
    section "symlinked ~/.tmux.conf (as $USER)"
    tmuxsaver unsetup -q >/dev/null 2>&1
    mkdir -p ~/dotfiles
    printf 'set -g mouse on\n' > ~/dotfiles/tmux.conf
    ln -sf dotfiles/tmux.conf ~/.tmux.conf
    tmuxsaver setup --no-linger -q >/dev/null 2>&1
    check "setup keeps ~/.tmux.conf a symlink" test -L ~/.tmux.conf
    check "hook written into the link target" grep -q tmuxsaver ~/dotfiles/tmux.conf
    tmuxsaver unsetup -q >/dev/null 2>&1
    check "unsetup keeps the symlink" test -L ~/.tmux.conf
    check "unsetup restores the target" \
        bash -c 'printf "set -g mouse on\n" | cmp -s - ~/dotfiles/tmux.conf'
    rm -rf ~/.tmux.conf ~/dotfiles
    tmuxsaver setup --no-linger -q >/dev/null 2>&1
}

# Session names with "/" and renamed sessions.
user_names_and_renames() {
    section "session names with / and renames (as $USER)"
    tmux kill-server 2>/dev/null; rm -rf ~/.tmuxsaver

    tmux new-session -d -s 'web/api' -x 160 -c /tmp
    tmux new-session -d -s old -x 160 -c /tmp
    wait_pane 'web/api' '\$ *$'
    wait_pane old '\$ *$'
    check "history for 'web/api' lands in its encoded dir" run_in 'web/api' 'cd /etc'
    check "history for 'old' is recorded" run_in old 'echo before-rename'
    tmuxsaver save -q

    tmux rename-session -t =old new
    local out
    out=$(tmuxsaver save 2>&1)
    check "save detects the rename" grep -q "renamed to 'new'" <<<"$out"
    check "old name is left as a link" test -L ~/.tmuxsaver/sessions/old
    check "history merged into the new name" grep -qx 'echo before-rename' ~/.tmuxsaver/sessions/new/history
    # The pane's shell still has HISTFILE=.../old/history; via the link its
    # new commands must reach the new name's history.
    tmux send-keys -t =new: 'echo after-rename' Enter
    local tries=50
    until grep -qx 'echo after-rename' ~/.tmuxsaver/sessions/new/history 2>/dev/null || (( tries-- <= 0 )); do sleep 0.1; done
    check "pre-rename shell keeps writing to the right history" \
        grep -qx 'echo after-rename' ~/.tmuxsaver/sessions/new/history
    check "list shows 'web/api' and 'new' only" \
        bash -c 'out=$(tmuxsaver list); grep -q "web/api" <<<"$out" && grep -q " new " <<<"$out" && ! grep -q " old " <<<"$out"'

    tmux kill-server
    sleep 0.3
    tmuxsaver restore -q
    check "restore brings back exactly 'new' and 'web/api'" \
        test "$(tmux ls -F '#S' | sort | tr '\n' ' ')" = "new web/api "
    wait_pane new '\$ *$'
    tmux send-keys -t =new: Up
    check "renamed session's Up-arrow recalls the post-rename command" wait_pane new 'echo after-rename$' 20
    check "'web/api' restored at /etc" test "$(tmux display -p -t '=web/api:' '#{pane_current_path}')" = /etc
    tmux kill-server

    tmuxsaver forget new >/dev/null 2>&1
    check "forget also removes the old name's link" test ! -e ~/.tmuxsaver/sessions/old

    check "save with no tmux server exits 0" tmuxsaver save -q

    # Renaming back to an earlier name, and two sessions swapping names,
    # must never lose history (0.5.1 deleted it in both cases).
    rm -rf ~/.tmuxsaver
    tmux new-session -d -s work -x 160 -c /tmp
    tmux new-session -d -s swap1 -x 160 -c /tmp
    tmux new-session -d -s swap2 -x 160 -c /var
    wait_pane work '\$ *$'; wait_pane swap1 '\$ *$'; wait_pane swap2 '\$ *$'
    run_in work 'echo work-history' >/dev/null
    run_in swap1 'echo one-history' >/dev/null
    run_in swap2 'echo two-history' >/dev/null
    tmuxsaver save -q
    tmux rename-session -t =work proj;  tmuxsaver save -q
    tmux rename-session -t =proj work;  tmuxsaver save -q
    check "renaming back keeps the history" grep -qx 'echo work-history' ~/.tmuxsaver/sessions/work/history
    check "renaming back leaves no link loop" test -d ~/.tmuxsaver/sessions/work -a ! -L ~/.tmuxsaver/sessions/work
    tmux rename-session -t =swap1 tmpname
    tmux rename-session -t =swap2 swap1
    tmux rename-session -t =tmpname swap2
    tmuxsaver save -q
    check "swapped names: each keeps its own history" \
        bash -c 'grep -qx "echo one-history" ~/.tmuxsaver/sessions/swap2/history && grep -qx "echo two-history" ~/.tmuxsaver/sessions/swap1/history'
    check "swapped names: each keeps its own workdir" \
        bash -c '[[ $(cat ~/.tmuxsaver/sessions/swap2/workdir) == /tmp && $(cat ~/.tmuxsaver/sessions/swap1/workdir) == /var ]]'
    check "saved data is private (sessions dir 700)" test "$(stat -c %a ~/.tmuxsaver/sessions)" = 700
    check "history files are private (600)" \
        bash -c '! find ~/.tmuxsaver/sessions -name history -perm /077 | grep -q .'
    tmux kill-server
}

# --dir must reach the shell hook of restored sessions.
user_custom_dir() {
    section "--dir (as $USER)"
    tmux kill-server 2>/dev/null
    local dir=~/alt
    rm -rf "$dir"; mkdir -p "$dir/sessions/cd1"
    echo /tmp > "$dir/sessions/cd1/workdir"
    echo 'echo from-custom-dir' > "$dir/sessions/cd1/history"
    tmuxsaver restore --dir "$dir" -q
    wait_pane cd1 '\$ *$'
    tmux send-keys -t =cd1: ' echo "HF=$HISTFILE"' Enter
    check "restored shell's HISTFILE is under --dir" wait_pane cd1 "HF=$dir/sessions/cd1/history" 20
    tmux send-keys -t =cd1: Up Up
    check "and its history came from --dir" wait_pane cd1 'echo from-custom-dir$' 20
    tmux kill-server
    rm -rf "$dir"
}

# Forget-on-close: sessions you close yourself are not restored; logout,
# shutdown and kill-server never mark anything.
user_closed_sessions() {
    section "forget on close (as $USER)"
    tmux kill-server 2>/dev/null; rm -rf ~/.tmuxsaver
    check "setup installs the session-closed hook" grep -q 'set-hook.*session-closed.*tmuxsaver' ~/.tmux.conf
    # The server must load ~/.tmux.conf (it does: first new-session starts it).
    tmux new-session -d -s keepme -x 160 -c /tmp
    tmux new-session -d -s gone -x 160 -c /tmp
    tmux new-session -d -s "it's odd" -x 160 -c /tmp
    tmux new-session -d -s list -x 160 -c /tmp     # a name that is also a command
    wait_pane gone '\$ *$'
    tmuxsaver save -q
    tmux send-keys -t =gone: 'exit' Enter
    tmux kill-session -t "=it's odd"
    tmux kill-session -t =list
    local tries=50
    until [[ -f ~/.tmuxsaver/sessions/list/closed ]] || (( tries-- <= 0 )); do sleep 0.1; done
    sleep 0.3
    check "typing exit marks the session closed" test -f ~/.tmuxsaver/sessions/gone/closed
    check "kill-session marks the session closed (name with a quote)" test -f ~/.tmuxsaver/sessions/"it's odd"/closed
    check "a session named 'list' is handled as a name" test -f ~/.tmuxsaver/sessions/list/closed
    check "the remaining session is not marked" test ! -e ~/.tmuxsaver/sessions/keepme/closed
    check "list shows closed sessions" bash -c 'tmuxsaver list | grep -q "gone .*closed"'

    tmux kill-server
    sleep 0.5
    check "kill-server does not mark the last sessions closed" test ! -e ~/.tmuxsaver/sessions/keepme/closed
    # kill-server fires session-closed only for some sessions, so also call
    # the handler exactly as tmux does then (0 sessions left): no mark.
    tmuxsaver closed --quiet -- keepme 0
    check "a close that leaves 0 sessions (kill-server) is ignored" test ! -e ~/.tmuxsaver/sessions/keepme/closed
    tmuxsaver restore -q
    check "restore skips closed sessions" test "$(tmux ls -F '#S' | tr '\n' ' ')" = "keepme "
    tmuxsaver reopen gone -q
    check "reopen restores a closed session" tmux has-session -t =gone
    check "reopen clears its closed mark" test ! -e ~/.tmuxsaver/sessions/gone/closed
    tmuxsaver forget --closed -q
    check "forget --closed removes only closed sessions" \
        bash -c '[[ ! -e ~/.tmuxsaver/sessions/list && -d ~/.tmuxsaver/sessions/gone && -d ~/.tmuxsaver/sessions/keepme ]]'

    wait_pane keepme '\$ *$'
    tmux send-keys -t =keepme: 'tmuxsaver status' Enter
    check "status (inside a pane) reports the shell is recording" wait_pane keepme 'this shell: +ok recording' 30
    check "status reports both tmux hooks" wait_pane keepme 'tmux hooks: +ok save on detach, forget on close' 10
    tmux kill-server

    tmuxsaver setup --keep-closed --no-linger -q >/dev/null 2>&1
    check "setup --keep-closed drops the session-closed hook" \
        bash -c '! grep -q session-closed ~/.tmux.conf && grep -q client-detached ~/.tmux.conf'
    tmuxsaver setup --no-linger -q >/dev/null 2>&1
    check "plain setup puts it back (one block)" \
        test "$(grep -c 'set-hook.*tmuxsaver' ~/.tmux.conf)" = 2
}

# Upgrade path: a ~/.tmux.conf with the pre-0.6 single hook line.
user_old_tmux_hook() {
    section "migrate a pre-0.6 tmux hook (as $USER)"
    printf 'set -g mouse on\n\n# tmuxsaver: save on detach\nset-hook -ga client-detached "run-shell -b \\"tmuxsaver save --quiet || true\\""\n' > ~/.tmux.conf
    tmuxsaver setup --no-linger -q >/dev/null 2>&1
    check "old hook replaced by one current block" \
        bash -c '[[ $(grep -c "^# tmuxsaver:" ~/.tmux.conf) == 1 && $(grep -c "set-hook.*tmuxsaver" ~/.tmux.conf) == 2 ]]'
    check "user settings kept" grep -qx 'set -g mouse on' ~/.tmux.conf
    rm -f ~/.tmux.conf
    tmuxsaver setup --no-linger -q >/dev/null 2>&1
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
    local i
    for i in $(seq 1 40); do tmux send-keys -t =zs: "echo z$i" Enter; done
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
    tmux send-keys -t =zs: C-u ' fc -ln 1 | grep -c "^echo z"' Enter
    check "zsh restores all 40 earlier commands (not just HISTSIZE=30)" wait_pane zs '^40$' 30
    tmux kill-server
}

user_from_source() {
    section "from-source install.sh (as $USER)"
    local src=$1
    tmux kill-server 2>/dev/null
    rm -f ~/.tmux.conf
    (cd "$src" && ./install.sh --no-systemd --no-linger </dev/null >/dev/null 2>&1)
    check "install.sh installs the binary"  test -x ~/.local/bin/tmuxsaver
    check "setup-shell finds its snippet"   bash -c '~/.local/bin/tmuxsaver setup-shell | grep -q "tmuxsaver:begin"'
    check "tmux hook uses the absolute path" \
        grep -qF "'$HOME/.local/bin/tmuxsaver' save" ~/.tmux.conf
    (cd "$src" && ./install.sh --no-systemd --no-linger </dev/null >/dev/null 2>&1)
    check "re-running install.sh keeps one shell block" \
        test "$(grep -c '^# tmuxsaver:begin' ~/.bashrc)" = 1
    check "re-running install.sh keeps one tmux hook block" \
        test "$(grep -c '^# tmuxsaver:' ~/.tmux.conf) $(grep -c 'set-hook.*tmuxsaver' ~/.tmux.conf)" = "1 2"
}

if [[ "${1:-}" == "--as-user" ]]; then
    exec 3>&1   # lets diagnose() print from inside a silenced `check`
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
# Build the home directory from a controlled skeleton, not the host's
# /etc/skel: CI images ship extras there (GitHub's runner adds a
# .bash_profile that never sources .bashrc, so tmux's login shells would
# skip the hook). Use a stock Debian/Ubuntu layout instead.
mkdir -p "$WORK/skel"
cat > "$WORK/skel/.profile" <<'PROFILE'
# Stock Debian/Ubuntu behaviour: login shells read .bashrc.
if [ -n "$BASH_VERSION" ] && [ -f "$HOME/.bashrc" ]; then
    . "$HOME/.bashrc"
fi
PROFILE
cat > "$WORK/skel/.bashrc" <<'BASHRC'
# Minimal interactive bash setup (mirrors the relevant bits of Ubuntu's skel).
case $- in *i*) ;; *) return ;; esac
HISTCONTROL=ignoreboth
shopt -s histappend
PS1='\u@\h:\w\$ '
BASHRC
# Ubuntu's /etc/zsh/zshrc runs compinit, which stops at an interactive
# "insecure directories" prompt on hosts with group-writable fpath dirs
# (the GitHub runner). Keystrokes the test sends would answer that prompt.
echo 'skip_global_compinit=1' > "$WORK/skel/.zshenv"
# No HISTSIZE: zsh then defaults to 30, which the hook must raise.
echo '# zsh defaults' > "$WORK/skel/.zshrc"
useradd -m -k "$WORK/skel" -s /bin/bash "$TEST_USER"
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
check "install leaves .bashrc alone" cmp -s "$WORK/bashrc.orig" "$HOME_DIR/.bashrc"
check "install leaves .zshrc alone"  cmp -s "$WORK/zshrc.orig"  "$HOME_DIR/.zshrc"
check "install creates no .tmux.conf" test ! -e "$HOME_DIR/.tmux.conf"
check "install tells the user to run setup" grep -q "tmuxsaver setup" "$WORK/dpkg.log"
check "reinstall succeeds" install_deb

as_user setup
check ".bashrc still owned by the user" test "$(stat -c %U "$HOME_DIR/.bashrc")" = "$TEST_USER"
as_user bash
as_user zsh
as_user names_and_renames
as_user custom_dir
as_user closed_sessions
as_user old_tmux_hook
as_user unsetup "$WORK/bashrc.orig" "$WORK/zshrc.orig"
as_user bash_profile
as_user symlinked_tmux_conf

section "uninstall without a terminal (undoes setup for SUDO_USER)"
check "dpkg -r succeeds with no tty" \
    bash -c 'SUDO_USER="$1" DEBIAN_FRONTEND=noninteractive dpkg -r tmuxsaver </dev/null >/dev/null 2>&1' _ "$TEST_USER"
check ".bashrc restored byte-for-byte" cmp -s "$WORK/bashrc.orig" "$HOME_DIR/.bashrc"
check ".zshrc restored byte-for-byte"  cmp -s "$WORK/zshrc.orig"  "$HOME_DIR/.zshrc"
check "tmux.conf created by setup removed" test ! -e "$HOME_DIR/.tmux.conf"
check "saved sessions kept" test -d "$HOME_DIR/.tmuxsaver/sessions"

as_user from_source "$WORK/src"

echo
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
