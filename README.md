# tmuxsaver

A minimal tmux session saver. Saves the **working directory** and **shell history** for each session — nothing more. No window/pane layout, no running programs, no complexity.

## Why not tmux-resurrect?

[tmux-resurrect](https://github.com/tmux-plugins/tmux-resurrect) saves the full session layout: every window, every pane, running programs, vim sessions, etc. That is powerful but also heavy. If all you need is to get back to the right directory with the right history after a reboot, `tmuxsaver` is a focused alternative.

## Features

- Saves the current working directory per tmux session
- Saves per-session shell history (bash/zsh) via a lightweight shell hook
- Restores sessions with the correct working directory on demand
- Optional systemd user services for automatic save on logout and restore on login
- Single bash script, zero runtime dependencies beyond tmux itself

## Installation

### Debian / Ubuntu (recommended)

Download the `.deb` from the [releases page](https://github.com/<you>/tmuxsaver/releases) and install:

```bash
sudo dpkg -i tmuxsaver_0.2.0_all.deb
```

If `tmux` is not yet installed, resolve it afterwards with `sudo apt-get install -f`.

The installer automatically:
- enables `tmuxsaver-save.service` (save on logout) for all users
- appends the shell history hook to your `~/.bashrc` and `~/.zshrc`

Open a new shell (or `source ~/.bashrc`) for the history hook to take effect.

### From source

```bash
git clone https://github.com/<you>/tmuxsaver.git
cd tmuxsaver
./install.sh                      # binary only (~/.local/bin)
./install.sh --shell-hook         # also add shell history integration
./install.sh --systemd            # also install systemd services
./install.sh --shell-hook --systemd  # everything
```

Make sure `~/.local/bin` (or your chosen `--prefix/bin`) is in `$PATH`.

### Manual install

```bash
chmod +x tmuxsaver
cp tmuxsaver ~/.local/bin/
```

## Shell history integration (recommended)

Without shell integration, `tmuxsaver` saves only working directories. To also capture per-session history, add the shell hook so each tmux session writes to its own history file:

```bash
tmuxsaver setup-shell   # prints the snippet
```

Append the printed block to `~/.bashrc` and/or `~/.zshrc`, or run `./install.sh --shell-hook` to do it automatically.

Once the hook is active, every new shell inside a tmux session writes its history to:

```
~/.tmuxsaver/sessions/<session-name>/history
```

## Usage

```
tmuxsaver save          Save all active tmux sessions
tmuxsaver restore       Restore saved sessions (skips existing ones)
tmuxsaver list          Show saved sessions and their directories
tmuxsaver clean         Delete all saved session data
tmuxsaver setup-shell   Print the shell integration snippet
```

Options available on all commands:

```
--dir <path>    Use a custom save directory instead of ~/.tmuxsaver
--quiet, -q     Suppress informational output (useful in scripts/services)
```

## Saved data layout

```
~/.tmuxsaver/
└── sessions/
    ├── main/
    │   ├── workdir   # last known working directory
    │   └── history   # shell history (if hook is active)
    └── work/
        ├── workdir
        └── history
```

## Automatic save/restore (systemd)

Install the user services with `./install.sh --systemd`. Two units are installed:

| Unit | Trigger | Action |
|------|---------|--------|
| `tmuxsaver-save.service` | User logout / system shutdown | `tmuxsaver save` |
| `tmuxsaver-restore.service` | User login | `tmuxsaver restore` (optional, prompt during install) |

Manage them with standard `systemctl --user` commands:

```bash
systemctl --user status tmuxsaver-save.service
systemctl --user disable tmuxsaver-restore.service
```

## License

MIT
