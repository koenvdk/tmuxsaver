# Changelog

All notable changes to tmuxsaver. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[semantic versioning](https://semver.org) (see "Compatibility promise" in the
README).

## [0.6.1]

### Fixed
- **Closed sessions weren't marked after upgrading to 0.6.0** while a tmux
  server kept running (e.g. with lingering). tmux reads `~/.tmux.conf` only
  when its server starts, so the new `session-closed` hook never reached the
  running server. `setup` now loads the hooks into a running server itself,
  and `unsetup` removes them from it.
- On tmux older than 3.4, closing a session never marked it: the hook relied
  on `#{server_sessions}`, which only exists from 3.4. The handler now asks
  the server instead when the count is missing.
- `status` reported the hooks as loaded when only the save hook was; it now
  checks each hook in the running server.

### Changed
- The hooks now live in a fixed slot (`[77]`) instead of being appended, so
  loading the config again (`setup`, `tmux source-file`) never duplicates them
  and your own hooks for the same events are untouched. Run `tmuxsaver setup`
  once to switch.
- `list` shows which saved sessions are `running` right now.
- **Minimum tmux is now 3.2.** Restore uses `new-session -e`, added in 3.2;
  on 3.0/3.1 restore has failed since 0.4.15. `setup` and `status` warn on
  older versions; the package depends on `tmux (>= 3.2)`.
- CI also runs the end-to-end tests on tmux 3.2a.

### After upgrading
Sessions you closed before this fix weren't marked. Check `tmuxsaver list`
for entries that are neither `running` nor `closed`; remove the ones you
don't want back with `tmuxsaver forget <name>...`.

## [0.6.0]

### Added
- **Closed sessions stay closed.** A session you close yourself (typing `exit`
  in its last pane, or `tmux kill-session`) is marked *closed* and no longer
  restored at the next login. Logout, shutdown and `tmux kill-server` never
  mark anything. Closing your very last session isn't reported by tmux, so
  that one isn't marked.
- `tmuxsaver reopen <name>...` restores closed sessions; `tmuxsaver forget
  --closed` deletes them; `tmuxsaver list` shows them.
- `tmuxsaver setup --keep-closed` opts out: every session is restored.
- `tmuxsaver status` reports each part of the setup, and whether the current
  shell is recording history.
- `setup` and `status` warn when tmux is older than 3.0.
- README: requirements and supported platforms; compatibility promise.

### Changed
- `setup` writes a second tmux hook (`session-closed`). Re-run `tmuxsaver setup`
  after upgrading to get it; the old single-hook block is replaced in place.
- Session names are always taken as names after the command, so sessions
  called `list`, `save` or `-x` work with `forget`, `reopen` (use `--` before
  names that start with `-`).

## [0.5.2] — 2026-09-25

### Fixed
- **Data loss:** renaming a session back to an earlier name, or two sessions
  swapping names, deleted their saved history (regression in 0.5.1).
- zsh: a restored session got back only its last ~30 commands (zsh's default
  `HISTSIZE`).
- `~/.tmuxsaver` was group-accessible under a 002 umask; it is now private.

## [0.5.1] — 2026-09-25

### Fixed
- A renamed session was restored under both its old and new name.
- Session names containing `/` were stored as nested directories and restored
  wrongly.
- `save` exited 1 when no tmux server was running (the logout service showed
  as failed).
- `--dir` didn't reach the shell hook of restored sessions.
- The save service is ordered to stop before the restore service at shutdown.
- Package Homepage URL.

## [0.5.0] — 2026-09-25

### Changed
- **Per-user setup.** The package only installs files; each user runs
  `tmuxsaver setup` (shell hook, tmux hook, systemd user services, lingering)
  and can undo it with `tmuxsaver unsetup`. Upgrades from 0.4.x keep working.
- `apt remove` runs `unsetup` for the user who ran sudo.

### Fixed
- Login shells whose `~/.bash_profile` never loads `~/.bashrc` now get the
  history hook.
- A symlinked `~/.tmux.conf` stays a symlink.
- `--help` printed a truncated usage.

## [0.4.16] – [0.4.17] — 2026-09-25

Version bumps only.

## [0.4.15] — 2026-09-24

### Changed
- Releases are cut automatically when a version bump lands on `main`.
- History is handed to restored sessions via their environment instead of
  typing commands into the pane (which broke in zsh). Requires tmux 3.0+.

## [0.4.14] — 2026-09-24

### Fixed
- The package no longer needs an undeclared `python3`.

## [0.4.13] — 2026-09-24

### Fixed
- From-source installs: systemd units, `setup-shell` and the tmux hook now use
  the installed binary's path.

## [0.4.12] — 2026-09-24

### Fixed
- `restore` skipped a saved session when a live one's name started with it.
- `apt remove` failed without a terminal.
- The shell hook could pick the wrong session with several clients attached.

## [0.4.11] and earlier — 2026-04 to 2026-08

Initial development: per-session history and working directory, save on
detach, systemd save/restore services, `forget`, lingering by default.
See the git history for details.

[0.6.1]: https://github.com/koenvdk/tmuxsaver/compare/v0.6.0...v0.6.1
[0.6.0]: https://github.com/koenvdk/tmuxsaver/compare/v0.5.2...v0.6.0
[0.5.2]: https://github.com/koenvdk/tmuxsaver/compare/v0.5.1...v0.5.2
[0.5.1]: https://github.com/koenvdk/tmuxsaver/compare/v0.5.0...v0.5.1
[0.5.0]: https://github.com/koenvdk/tmuxsaver/compare/v0.4.17...v0.5.0
[0.4.16]: https://github.com/koenvdk/tmuxsaver/compare/v0.4.15...v0.4.16
[0.4.17]: https://github.com/koenvdk/tmuxsaver/compare/v0.4.16...v0.4.17
[0.4.15]: https://github.com/koenvdk/tmuxsaver/compare/v0.4.14...v0.4.15
[0.4.14]: https://github.com/koenvdk/tmuxsaver/compare/v0.4.13...v0.4.14
[0.4.13]: https://github.com/koenvdk/tmuxsaver/compare/v0.4.12...v0.4.13
[0.4.12]: https://github.com/koenvdk/tmuxsaver/compare/v0.4.11...v0.4.12
[0.4.11]: https://github.com/koenvdk/tmuxsaver/releases/tag/v0.4.11
