# fcitx5-lock.nvim — local prototype

Mode-aware Fcitx5 locking and input-method cursor colors for Neovim.
This prototype is not installed in the author's dotfiles and has not been
runtime-tested. It is not yet a published plugin.

## Requirements

- Linux desktop session with a working session D-Bus connection.
- Running Fcitx5 with its D-Bus addon (`org.fcitx.Fcitx5`).
- Neovim 0.10+ for the plugin; Neovim 0.12+ for the `vim.pack` example below.
- `fcitx5-remote` (Fcitx5) and `gdbus` (GLib/GIO tools) on PATH.

No Python, PyGObject, `ime-cursor` daemon, or runtime state file is needed.
Tray signals require Fcitx5's notificationitem addon. Without those signals,
periodic queries still work but detection can take up to the polling interval.

## Installation

The repository is local-only for now. These examples intentionally use the local
checkout; no GitHub repository URL has been assigned. Choose one plugin manager.

### vim.pack (Neovim 0.12+)

Add to your `init.lua` before the setup call:

```lua
vim.pack.add {
  { src = 'file://' .. vim.fn.expand('~/.local/share/fcitx5-lock.nvim') },
}
require('fcitx5-lock').setup {}
```

`vim.pack` clones the committed local repository into its plugin directory.
Uncommitted edits in the source checkout are not installed. After committing
an update, use `vim.pack.update({ 'fcitx5-lock.nvim' })` to update the installed copy.
Once published, replace `src` with the actual repository's HTTPS URL.

### lazy.nvim

Add this entry to your existing lazy.nvim plugin specifications:

```lua
{
  dir = vim.fn.expand('~/.local/share/fcitx5-lock.nvim'),
  name = 'fcitx5-lock.nvim',
  main = 'fcitx5-lock',
  lazy = false,
  opts = {},
}
```

The local `dir` loads this checkout directly. `main` selects the setup module,
and `opts` is passed to `setup()` automatically: do not call it a second time.
Once published, replace `dir` with the actual `owner/repository` entry.

Before trying either example in this dotfiles configuration, disable the existing
`require('ime.cursor').setup()` and `require('ime.lock').setup(...)` calls.
Both implementations must not run at the same time. This README does not enable
the prototype in your existing configuration.

References: [Neovim packages](https://neovim.io/doc/user/pack/),
[lazy.nvim plugin specifications](https://lazy.folke.io/spec).

## Configuration

For vim.pack, replace the empty setup options with the following. For lazy.nvim,
use the table contents as `opts` instead of calling `setup()` yourself:

```lua
require('fcitx5-lock').setup {
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
Changed names publish `zh`/`en` (or nil when unknown) to subscribers, matching the
dotfiles backend's interface. `cursor.input_methods` selects the names classified
as `zh`; a change between two names in the same category still emits a notification.
The lock re-queries before
reconciliation rather than trusting a delayed state-source observation.
Exit cleanup stops the monitor, polling timer and state query; the lock finishes
its own in-flight operation separately.

Fcitx5 input-method sharing settings affect other applications. This plugin does
not create a per-editor input context. It does not implement Kitty coloring or
keyboard-idle switching. Multiple Neovim instances each run their own monitor.

## Keeping the shared core in sync

`lock.lua` and `cursor.lua` are byte-identical copies of the dotfiles modules.
They resolve their sibling `state` module from the name used by `require`, so no
module-path rewriting is needed. The only backend difference lives in `state.lua`:
the dotfiles backend watches the daemon's file, while this backend owns D-Bus
monitoring and polling. `init.lua` is the plugin's setup entry point.

After changing the dotfiles core, run:

```sh
python3 tools/sync_core.py ~/.config/nvim/lua/ime
```

This copies only `lock.lua` and `cursor.lua`; it leaves the plugin's backend and
setup entry point intact. Python is a development helper, not a runtime dependency.

The standalone state source is new. No validation or compatibility guarantee is
implied by copying the existing modules.

