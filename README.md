# fcitx5-ime.nvim — local prototype

Mode-aware Fcitx5 locking and input-method cursor colors for Neovim.
This prototype is not installed in the author's dotfiles and has not been
runtime-tested. It is not yet a published plugin.

## Requirements

- Linux desktop session with Fcitx5 and its session D-Bus service.
- Neovim 0.10+.
- `fcitx5-remote` and `gdbus` on PATH.

No Python, PyGObject, `ime-cursor` daemon, or runtime state file is needed.
Tray signals require Fcitx5's notificationitem addon. Without those signals,
periodic queries still work but detection can take up to the polling interval.

## Setup

Install this directory with your plugin manager, then explicitly call:

```lua
require('fcitx5-ime').setup {
  lock = {
    enabled = true,
    ascii_im = 'keyboard-us',
    restore = false,
  },
  cursor = {
    enabled = true,
    color = '#ffbf69',
    input_methods = { 'rime' },
  },
  source = {
    monitor = true,       -- false uses polling only
    poll_interval = 5000, -- positive milliseconds; also retries dead monitors
  },
}
```

These are the defaults. Requiring the module alone does not start monitoring or
switch input methods. Setup is once per Neovim process; restart to change options.
Do not enable this prototype alongside another Neovim input-method lock.

Text-entry modes (Insert, Replace, terminal, command line, and Select) allow the
user's choice; other modes enforce `ascii_im` while Neovim is focused.
With `restore=false`, entering a text-entry mode does not restore a previous
input method. With `restore=true`, the lock remembers and restores that choice
on text-entry/focus changes and attempts restoration on exit.

Cursor color follows input method names, not an input method's internal ASCII
mode. Disabling the cursor does not disable locking, and vice versa.

## State source and boundaries

The state source runs one `gdbus monitor` scoped to `org.fcitx.Fcitx5`.
`NewIcon`/`NewToolTip` and service-owner changes trigger `fcitx5-remote -n`.
Queries are coalesced; a timer covers missed signals and restarts dead monitors.
Only changed names are published to subscribers. The lock re-queries before
reconciliation rather than trusting a delayed state-source observation.
Exit cleanup stops the monitor, polling timer and state query; the lock finishes
its own in-flight operation separately.

Fcitx5 input-method sharing settings affect other applications. This plugin does
not create a per-editor input context. It does not implement Kitty coloring or
keyboard-idle switching. Multiple Neovim instances each run their own monitor.

The lock/cursor modules were adapted from the local Neovim configuration; the
standalone state source is new. No validation or compatibility guarantee is
implied by copying the existing modules. A license should be chosen before
public distribution.
