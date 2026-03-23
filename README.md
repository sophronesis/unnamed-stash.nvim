# unnamed-stash.nvim

Persist unnamed (No Name) buffers across Neovim sessions. Like VSCode's "hot exit" for buffers that were never saved to disk.

## The problem

When you close Neovim, any unnamed buffers (text you typed without saving to a file) are lost forever. Built-in sessions, ShaDa, swap files - none of them handle this case.

## How it works

- Saves unnamed buffer contents to `~/.local/share/nvim/unnamed/` as timestamped stash files
- Saves automatically on every text change (debounced), on quit, and periodically
- Optionally restores stashed buffers when Neovim starts
- Survives window kills (SIGTERM) since it saves continuously, not just on exit
- Preserves filetype and cursor position

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
    restore = false, -- don't auto-restore on startup
  },
}
```

## Configuration

Default options:

```lua
{
  -- Auto-restore stashed buffers on startup
  restore = true,
  -- Directory to store stash files
  stash_dir = vim.fn.stdpath("data") .. "/unnamed",
  -- Debounce delay (ms) for saving after text changes
  save_delay = 1000,
  -- Periodic save interval (ms), 0 to disable
  periodic_save = 60000,
  -- Delete old stash files when saving new ones (false = accumulate across sessions)
  auto_clean = true,
}
```

## Commands

| Command | Description |
|---|---|
| `:UnnamedStashSave` | Manually save all unnamed buffers |
| `:UnnamedStashRestore` | Manually restore stashed buffers |
| `:UnnamedStashClear` | Delete all stash files |

## Stash format

Files are saved as `<unix_timestamp>_<index>.stash` in the stash directory. First line is JSON metadata (filetype, cursor position, creation time), remaining lines are buffer content.

```
~/.local/share/nvim/unnamed/
  1742752800_0.stash
  1742753100_0.stash
```

## License

MIT
