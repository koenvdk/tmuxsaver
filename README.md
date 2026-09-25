# tmuxsaver

A minimal tmux session saver. Saves the **working directory** and **shell history** for each session — nothing more. No window/pane layout, no running programs, no complexity.

On login, your saved tmux sessions are restored in the background — run `tmux attach` to step back into them.

## Why not tmux-resurrect?

[tmux-resurrect](https://github.com/tmux-plugins/tmux-resurrect) saves the full session layout: every window, every pane, running programs, vim sessions, etc. That is powerful but also heavy. If all you need is to get back to the right directory with the right history after a reboot, `tmuxsaver` is a focused alternative.

## Features

- Saves working directory and shell history per tmux session
- Auto-saves whenever you detach from tmux (via a tmux hook)
- Auto-restores sessions on login (via systemd user service) — without attaching; you `tmux attach` when you want
- systemd user services as belt-and-suspenders backup
- Single bash script, zero runtime dependencies beyond tmux (3.0 or newer) itself

## Installation

### Debian / Ubuntu (recommended)

```bash
wget -P /tmp https://github.com/koenvdk/tmuxsaver/releases/download/v0.5.0/tmuxsaver_0.5.0_all.deb
sudo apt install /tmp/tmuxsaver_0.5.0_all.deb
```

> **Note:** `apt install` requires the file to be outside your home directory
> (`_apt` sandbox restriction). Downloading directly to `/tmp` avoids the issue.

The package only installs files. Then set it up **for your user** (as
yourself, not with `sudo`):

```bash
tmuxsaver setup
```

`setup` is idempotent and does the following:
- **Shell hook:** adds the per-session history hook to your `~/.bashrc` and
  `~/.zshrc`. If your `~/.bash_profile` never loads `~/.bashrc`, it's hooked
  too, because tmux starts login shells.
- **tmux hook:** adds a save-on-detach hook to your `~/.tmux.conf`.
- **Services:** enables your `tmuxsaver-save.service` (save on logout) and
  `tmuxsaver-restore.service` (restore on login).
- **Lingering:** asks whether to turn it on, so live sessions survive a full
  logout (see below). The default is yes.

Opt out of any part with `--no-shell-hook`, `--no-tmux-hook`, `--no-systemd`
or `--no-linger`. Undo it all with `tmuxsaver unsetup`, which keeps your saved
sessions. Open a new shell (or `exec $SHELL`) for the history hook to take effect.

Each user on the machine runs `tmuxsaver setup` for themselves.

> **Upgrading from 0.4.x:** older packages set up the installing user
> automatically. That setup keeps working after the upgrade. Run
> `tmuxsaver setup` once to move to the per-user services.

### Other Linux distros (release tarball)

If you don't have `apt`, grab the source tarball from the same release and run the installer:

```bash
VER=0.5.0
wget -O /tmp/tmuxsaver.tar.gz "https://github.com/koenvdk/tmuxsaver/archive/refs/tags/v${VER}.tar.gz"
tar -xzf /tmp/tmuxsaver.tar.gz -C /tmp
cd /tmp/tmuxsaver-${VER}
./install.sh
```

`./install.sh` installs the files under `~/.local`, then runs `tmuxsaver setup` for you. It accepts the same opt-outs (`--no-shell-hook`, `--no-tmux-hook`, `--no-systemd`, `--no-linger`). `--binary-only` installs the files without running `setup`.

Make sure `~/.local/bin` (or your chosen `--prefix/bin`) is in `$PATH`.

### From a git checkout

```bash
git clone https://github.com/koenvdk/tmuxsaver.git
cd tmuxsaver
./install.sh                 # full install (default)
./install.sh --binary-only   # just the files; run `tmuxsaver setup` later
```

### Manual install

```bash
chmod +x tmuxsaver
cp tmuxsaver ~/.local/bin/
tmuxsaver setup --no-systemd   # hooks only (the unit files aren't installed this way)
```

### Updating, reinstalling, uninstalling

Your saved sessions in `~/.tmuxsaver` are **user data** — they survive upgrades and
reinstalls, and are only ever removed when you explicitly ask.

```bash
# Update / reinstall (keeps saved sessions, never prompts)
sudo apt install /tmp/tmuxsaver_0.5.0_all.deb
sudo apt install --reinstall /tmp/tmuxsaver_0.5.0_all.deb

# Reinstall AND wipe saved sessions ("reinstallclean", opt-in)
sudo TMUXSAVER_PURGE_DATA=1 apt install --reinstall /tmp/tmuxsaver_0.5.0_all.deb

# Uninstall. This undoes `tmuxsaver setup` for the user running sudo, and is
# the only path that asks about removing saved sessions. Other users on the
# machine should run `tmuxsaver unsetup` first.
sudo apt remove tmuxsaver
```

> If `apt` doesn't pass the variable through to the package scripts, run the
> reinstallclean via dpkg directly: `sudo TMUXSAVER_PURGE_DATA=1 dpkg -i /tmp/tmuxsaver_0.5.0_all.deb`.
> You can also wipe sessions any time with `tmuxsaver clean`.

## How it works

**Saving** happens automatically in two ways:
- Whenever you detach from tmux (`tmux detach` or closing the terminal), a hook in `~/.tmux.conf` runs `tmuxsaver save`
- On logout/shutdown, the systemd user service saves as a fallback

**Restoring** happens automatically on login via `tmuxsaver-restore.service` (enabled by `tmuxsaver setup`). Sessions are re-created in the background and **never attached for you** — run `tmux attach` to pick them up when you want.

**Removing.** Closing a session in tmux does *not* delete its saved copy (`save` only ever adds — it never prunes, so a partial save can't wipe your other sessions). Drop saved sessions you no longer want with `tmuxsaver forget <name>...`, or wipe everything with `tmuxsaver clean`.

Alternative / supplemental:
- `tmuxsaver restore` — run it by hand any time (e.g. after killing the server)

### Surviving a full logout (systemd lingering)

There are two different things you might mean by "keeping a session":

- **Saved data** (working directory + history) — always preserved. It's written
  on detach/logout and re-created on your next login, no matter what.
- **The *live* session** (the running tmux server and whatever is executing in
  its panes) — this only survives a full logout if **lingering** is enabled.

Why: the restore service runs the tmux server under your *systemd user manager*
(`user@UID.service`), not inside any one login session. logind stops that user
manager when your **last** login session ends, taking the tmux server with it,
unless lingering is on. This happens whatever `KillUserProcesses` is set to;
that setting only controls processes inside login sessions. Lingering (`loginctl enable-linger`) tells logind to keep your
user manager (and its daemons) running with zero active sessions. It is the
supported, per-user way to make a user daemon outlive logout.

`tmuxsaver setup` **offers to enable lingering** and defaults to yes. Skip it
with `--no-linger` or `TMUXSAVER_NO_LINGER=1`. If your system only allows
admins to enable lingering, `setup` prints the `sudo loginctl` command to ask
for. `unsetup` leaves lingering as it is.

Toggle it yourself any time:

```bash
loginctl enable-linger "$USER"    # live sessions survive full logout
loginctl disable-linger "$USER"   # revert to logout tearing the server down
loginctl show-user "$USER" | grep Linger
```

> Even with lingering off, you never lose your saved directories/history — only
> the running processes. With it on, closing your last SSH terminal leaves the
> tmux server (and its panes) running for `tmux attach` next time.

### Per-session history

The shell hook (in `~/.bashrc`/`~/.zshrc`, added by `tmuxsaver setup`) points each tmux session at its own
history file and flushes after every command, so history is always on disk —
not just when the shell exits.

This only applies to shells started **after** the hook was installed. A pane
that was already running (or one running a foreground program like an editor)
keeps writing to the default `~/.bash_history`, so `tmuxsaver save` will report
`no per-session history yet` for it. New panes are fine automatically. To
capture an existing session's current history once, run **inside that pane**:

```bash
export HISTFILE="$HOME/.tmuxsaver/sessions/$(tmux display-message -p '#S')/history"
mkdir -p "$(dirname "$HISTFILE")" && history -w
```

> `tmuxsaver setup-shell` only *prints* the hook snippet (for manual installs);
> it does not create history for a running shell.

## Saved data layout

```
~/.tmuxsaver/
└── sessions/
    ├── main/
    │   ├── workdir   # last known working directory
    │   └── history   # shell history (written live by bash/zsh)
    └── work/
        ├── workdir
        └── history
```

## Usage

```
tmuxsaver setup             Set up hooks, services and lingering for your user
tmuxsaver unsetup           Undo setup (saved sessions are kept)
tmuxsaver save              Save all active tmux sessions
tmuxsaver restore           Restore saved sessions (skips existing ones)
tmuxsaver list              Show saved sessions and their directories
tmuxsaver forget <name>...  Remove saved data for specific session(s)
tmuxsaver clean             Delete all saved session data
tmuxsaver setup-shell       Print the shell integration snippet
tmuxsaver setup-tmux        Add only the save-on-detach hook to ~/.tmux.conf
```

`tmuxsaver --help` lists all options, including the `setup` opt-outs.

Options available on all commands:

```
--dir <path>    Use a custom save directory instead of ~/.tmuxsaver
--quiet, -q     Suppress informational output (useful in scripts/services)
```

## Automatic save/restore (systemd)

Two systemd user units are installed by the `.deb` (or by `install.sh`) and
enabled for you by `tmuxsaver setup`:

| Unit | Trigger | Action |
|------|---------|--------|
| `tmuxsaver-save.service` | User logout / shutdown | `tmuxsaver save` |
| `tmuxsaver-restore.service` | User login | `tmux start-server` + `tmuxsaver restore` |

Manage them with standard `systemctl --user` commands:

```bash
systemctl --user status tmuxsaver-save.service
systemctl --user enable --now tmuxsaver-restore.service
systemctl --user disable tmuxsaver-restore.service
```

## Development

```bash
make check   # bash -n on every script
make lint    # shellcheck
make test    # end-to-end: builds the .deb, installs it for a throwaway user,
             # drives real tmux sessions in bash and zsh, uninstalls it
```

`make test` needs root, `tmux` (3.0+), `zsh` and `dpkg-deb`, and it creates
and deletes a system user. Run it in a container or VM, not on your
workstation. CI runs all three on every pull request.

## Releasing

Releases are automatic. Bump the version in a PR and merge it:

```bash
make bump V=0.5.0   # updates tmuxsaver, packaging/DEBIAN/control and README.md
```

When a commit on `main` carries a version that has no `v<version>` tag yet, the
Release workflow builds the `.deb`, then creates the tag and the GitHub release
on that commit. Merges that don't change the version release nothing. Don't
tag by hand; if you do, the tag must match the commit's `TMUXSAVER_VERSION` or
the workflow fails rather than publishing a mislabeled package.

## License

MIT
