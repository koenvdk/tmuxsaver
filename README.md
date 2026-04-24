# tmuxsaver

A minimal tmux session saver. Saves the **working directory** and **shell history** for each session — nothing more. No window/pane layout, no running programs, no complexity.

On login, your terminal automatically attaches to your restored tmux sessions.

## Why not tmux-resurrect?

[tmux-resurrect](https://github.com/tmux-plugins/tmux-resurrect) saves the full session layout: every window, every pane, running programs, vim sessions, etc. That is powerful but also heavy. If all you need is to get back to the right directory with the right history after a reboot, `tmuxsaver` is a focused alternative.

## Features

- Saves working directory and shell history per tmux session
- Auto-saves whenever you detach from tmux (via a tmux hook)
- Auto-restores sessions and attaches on login (via shell hook)
- systemd user services as belt-and-suspenders backup
- Single bash script, zero runtime dependencies beyond tmux itself

## Installation

### Debian / Ubuntu (recommended)

```bash
wget -P /tmp https://github.com/koenvdk/tmuxsaver/releases/download/v0.4.3/tmuxsaver_0.4.3_all.deb
sudo apt install /tmp/tmuxsaver_0.4.3_all.deb
```

> **Note:** `apt install` requires the file to be outside your home directory
> (`_apt` sandbox restriction). Downloading directly to `/tmp` avoids the issue.

The installer automatically:
- enables `tmuxsaver-save.service` (save on logout) for all users
- enables `tmuxsaver-restore.service` (restore on login) for all users
- appends the shell integration hook to your `~/.bashrc` and `~/.zshrc`
- adds a save-on-detach hook to your `~/.tmux.conf`

Open a new shell (or `source ~/.bashrc`) for the hooks to take effect.

### From source

```bash
git clone https://github.com/koenvdk/tmuxsaver.git
cd tmuxsaver
./install.sh                      # binary only (~/.local/bin)
./install.sh --shell-hook         # also add shell integration
./install.sh --systemd            # also install systemd services
./install.sh --shell-hook --systemd  # everything
```

Make sure `~/.local/bin` (or your chosen `--prefix/bin`) is in `$PATH`.

### Manual install

```bash
chmod +x tmuxsaver
cp tmuxsaver ~/.local/bin/
tmuxsaver setup-shell   # print shell snippet → add to ~/.bashrc
tmuxsaver setup-tmux    # add save-on-detach hook to ~/.tmux.conf
```

## How it works

**Saving** happens automatically in two ways:
- Whenever you detach from tmux (`tmux detach` or closing the terminal), a hook in `~/.tmux.conf` runs `tmuxsaver save`
- On logout/shutdown, the systemd user service saves as a fallback

**Restoring** happens automatically on login via `tmuxsaver-restore.service` (enabled by default by the `.deb`). Sessions are re-created in the background; run `tmux attach` to pick them up.

Alternative / supplemental:
- `tmuxsaver restore` — run it by hand any time (e.g. after killing the server)
- `TMUXSAVER_AUTO_ATTACH=1` in `~/.bashrc` or `~/.profile` — shell hook restores and attaches automatically on shell startup (opt-in; only attaches if sessions actually exist)

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
tmuxsaver save          Save all active tmux sessions
tmuxsaver restore       Restore saved sessions (skips existing ones)
tmuxsaver list          Show saved sessions and their directories
tmuxsaver clean         Delete all saved session data
tmuxsaver setup-shell   Print the shell integration snippet
tmuxsaver setup-tmux    Add save-on-detach hook to ~/.tmux.conf
```

Options available on all commands:

```
--dir <path>    Use a custom save directory instead of ~/.tmuxsaver
--quiet, -q     Suppress informational output (useful in scripts/services)
```

## Automatic save/restore (systemd)

Two systemd user units are installed by the `.deb`:

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

## License

MIT
