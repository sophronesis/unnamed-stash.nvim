# unnamed-stash.nvim

Persist unnamed (No Name) buffers across Neovim sessions. Like VSCode's "hot exit" for buffers that were never saved to disk.

## The problem

When you close Neovim, any unnamed buffers - text you typed without saving to a file - are lost forever. Built-in sessions, ShaDa, swap files, none of them handle this case.

## How it works

- Saves unnamed buffer contents to `~/.local/share/nvim/unnamed/` as timestamped stash files
- Saves automatically 1 second after each text change (debounced), plus every 60 seconds and on quit
- Survives window kills (SIGTERM/SIGKILL) since it saves continuously, not just on exit
- Optionally restores stashed buffers when Neovim starts
- Preserves filetype and cursor position across sessions
- Stash files are named with unix timestamps for easy browsing

## Installation

### lazy.nvim

```lua
{
  "sophronesis/unnamed-stash.nvim",
  lazy = false,
  opts = {},
}
```

### With custom options

```lua
{
  "sophronesis/unnamed-stash.nvim",
  lazy = false,
  opts = {
    restore = false,    -- don't auto-restore on startup (use :UnnamedStashRestore manually)
    auto_clean = false, -- keep stash files from previous sessions
  },
}
```

## Configuration

Default options:

```lua
require("unnamed_stash").setup({
  -- Auto-restore stashed buffers on startup (skipped when opening files directly)
  restore = true,
  -- Directory to store stash files
  stash_dir = vim.fn.stdpath("data") .. "/unnamed",
  -- Debounce delay (ms) for saving after text changes
  save_delay = 1000,
  -- Periodic save interval (ms), 0 to disable
  periodic_save = 60000,
  -- Delete old stash files when saving new ones
  -- true:  only current session's buffers are kept
  -- false: stash files accumulate across sessions (clean up manually with :UnnamedStashClear)
  auto_clean = true,
})
```

## Commands

| Command | Description |
|---|---|
| `:UnnamedStashSave` | Manually save all unnamed buffers to stash |
| `:UnnamedStashRestore` | Restore stashed buffers into current session |
| `:UnnamedStashClear` | Delete all stash files from disk |

## Lua API

```lua
local stash = require("unnamed_stash")
stash.save()    -- save all unnamed buffers
stash.restore() -- restore from stash
stash.clear()   -- delete all stash files
```

## Stash format

Files are saved as `<unix_timestamp>_<index>.stash` in the stash directory. The first line is JSON metadata, remaining lines are the buffer content.

```
~/.local/share/nvim/unnamed/
  1742752800_0.stash    -- buffer created at 2025-03-23 18:00:00
  1742753100_0.stash    -- buffer created at 2025-03-23 18:05:00
```

Metadata includes:
- `created_at` - unix timestamp when the buffer was first seen
- `filetype` - buffer filetype (for syntax highlighting on restore)
- `cursor` - cursor position `[row, col]`

## How saving works

The plugin uses multiple save strategies to ensure your data is never lost:

1. **On text change** - debounced save 1 second after you stop typing in an unnamed buffer
2. **Periodic** - saves every 60 seconds (configurable, or disable with `periodic_save = 0`)
3. **On quit** - saves on `QuitPre` and `VimLeavePre` events
4. **Manual** - `:UnnamedStashSave` command

Since saves happen continuously during editing, your stash is always up to date - even if the window is killed.

## Requirements

- Neovim >= 0.10 (uses `vim.uv`)

## License

MIT
