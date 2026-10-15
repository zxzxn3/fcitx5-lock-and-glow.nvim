# Fcitx5 Lock & Glow

Mode-aware Fcitx5 locking and input-method cursor colors for Neovim.

## Demo

Both demos were recorded in Neovide with `lock.restore = false`.

### Cursor color

Switching from English to Rime changes the cursor color in Neovide (also works
in terminal Neovim; verified in Kitty).

![Input-method cursor colors in the upper fifth of Neovide](assets/cursor/demo-top-fifth.gif)

### Mode-aware locking

Type Chinese in Insert mode, press Esc, then use `hjkl` in Normal mode without
manually switching input methods. Returning to Insert mode keeps English active
with `restore = false`.

Command-line mode (`:`, `/`, `?`) does not force English; you can choose your
input method freely there.

![English locking when leaving Insert mode](assets/lock/demo-described.gif)

The buffer-tab styling shown in the demo is provided by
[Barbar Bubbles](https://github.com/zxzxn3/barbar-bubbles.nvim), a separate plugin.

Experimental: the locking/cursor core was tested with isolated Fcitx5 and Neovim
instances. The revised tray-signal monitor still needs runtime verification;
real GUI focus transitions have not been verified.

## Requirements

- Linux desktop session with a working session D-Bus connection.
- Running Fcitx5 with its D-Bus addon (`org.fcitx.Fcitx5`).
- Neovim 0.10+ for the plugin; Neovim 0.12+ for the `vim.pack` example below.
- `fcitx5-remote` (Fcitx5) and `gdbus` (GLib/GIO tools) on PATH.
- Optional `dbus-monitor` for event-driven updates; otherwise polling continues.

An active Fcitx5 input context is required to query or change the current input
method. Normally the focused desktop application supplies it. In a headless or
otherwise context-free session, Fcitx5 may return an empty name; the plugin treats
that as unknown rather than assuming English. Tested with Fcitx5 5.1.23 and
Neovim 0.12.6; the minimum Neovim version has not been separately tested.

Tray signals require an active Fcitx5 notificationitem addon and a registered
StatusNotifierWatcher; installing the addon alone does not guarantee signals.
Without those signals, periodic queries still work but detection can take up to
the polling interval.

## Installation

Choose one plugin manager.

### vim.pack (Neovim 0.12+)

Add to your `init.lua` before the setup call:

```lua
vim.pack.add {
  'https://github.com/zxzxn3/fcitx5-lock-and-glow.nvim',
}
require('fcitx5-lock-and-glow').setup {}
```

Use `vim.pack.update({ 'fcitx5-lock-and-glow.nvim' })` to update the installed copy.

### lazy.nvim

Add this entry to your existing lazy.nvim plugin specifications:

```lua
{
  'zxzxn3/fcitx5-lock-and-glow.nvim',
  main = 'fcitx5-lock-and-glow',
  lazy = false,
  opts = {},
}
```

`main` selects the setup module, and `opts` is passed to `setup()` automatically:
do not call it a second time.

Disable any existing Neovim input-method lock before enabling this plugin.
Installing this plugin does not disable other locks automatically.

References: [Neovim packages](https://neovim.io/doc/user/pack/),
[lazy.nvim plugin specifications](https://lazy.folke.io/spec).

## Configuration

For vim.pack, replace the empty setup options with the following. For lazy.nvim,
use the table contents as `opts` instead of calling `setup()` yourself:

```lua
require('fcitx5-lock-and-glow').setup {
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

Text-entry modes (Insert, Replace, terminal, command line, and Select) allow the
user's choice; other modes enforce `ascii_im` while Neovim is focused.
With `restore=false`, entering a text-entry mode does not restore a previous
input method. With `restore=true`, the lock remembers and restores that choice
on text-entry/focus changes and attempts restoration on exit.

Cursor color follows input method names, not an input method's internal ASCII
mode. Disabling the cursor does not disable locking, and vice versa.

## State source and boundaries

The state source runs one `dbus-monitor` with narrow signal match rules:
`NewIcon`/`NewToolTip` at `/StatusNotifierItem`, plus service-owner changes for
`org.fcitx.Fcitx5`. Fcitx5's tray uses a separate D-Bus connection, so filtering
tray signals by the controller's sender would miss them. Other tray items using
the same path can trigger an extra query; their payloads are not interpreted.
Matching signals trigger `fcitx5-remote -n`.
Queries are coalesced; a timer covers missed signals and restarts dead monitors.
The cursor uses `cursor.input_methods` to distinguish highlighted input methods
from other methods. Unknown state is handled separately. A change between two
method names in the same category still notifies subscribers.
The lock re-queries before
reconciliation rather than trusting a delayed state-source observation.
Exit cleanup stops the monitor, polling timer and state query; the lock finishes
its own in-flight operation separately.

Fcitx5 input-method sharing settings affect other applications. This plugin does
not create a per-editor input context. Multiple Neovim instances each run their
own monitor.

On desktops with Fcitx5 D-Bus activation configured, a query may automatically
start a stopped Fcitx5 service. Restart behavior therefore depends on the session
bus configuration. Notifications are rate-limited across failure types.

