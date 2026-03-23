local M = {}

local defaults = {
  -- Auto-restore stashed buffers on startup
  restore = true,
  -- Directory to store stash files
  stash_dir = vim.fn.stdpath("data") .. "/unnamed",
  -- Debounce delay (ms) for saving after text changes
  save_delay = 1000,
  -- Periodic save interval (ms), 0 to disable
  periodic_save = 60000,
}

local config = {}
local save_timer = nil
local periodic_timer = nil

local function ensure_dir()
  vim.fn.mkdir(config.stash_dir, "p")
end

--- Get or assign a creation timestamp for an unnamed buffer.
local function get_created_at(buf)
  local ts = vim.fn.getbufvar(buf, "__unnamed_stash_created", 0)
  if ts == 0 then
    ts = os.time()
    vim.fn.setbufvar(buf, "__unnamed_stash_created", ts)
  end
  return ts
end

--- Serialize an unnamed buffer to a stash file.
--- Filename: <unix_timestamp>_<index>.stash
--- File format: first line is JSON metadata, rest is buffer content.
local function save_buffer(buf, created_at, dedup_index)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  if #lines == 0 or (#lines == 1 and lines[1] == "") then return false end

  local meta = vim.json.encode({
    created_at = created_at,
    filetype = vim.bo[buf].filetype or "",
    cursor = vim.fn.getbufvar(buf, "__unnamed_stash_cursor", { 1, 0 }),
  })

  local path = config.stash_dir .. "/" .. string.format("%d_%d.stash", created_at, dedup_index)
  local f = io.open(path, "w")
  if not f then return false end
  f:write(meta .. "\n")
  for _, line in ipairs(lines) do
    f:write(line .. "\n")
  end
  f:close()
  return true
end

--- Save all unnamed buffers.
function M.save()
  ensure_dir()

  local unnamed_bufs = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf)
      and vim.api.nvim_buf_get_name(buf) == ""
      and vim.bo[buf].buftype == ""
    then
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      if #lines > 0 and not (#lines == 1 and lines[1] == "") then
        table.insert(unnamed_bufs, buf)
      end
    end
  end

  -- Don't clear stash if there's nothing to save (avoids wiping after QuitPre)
  if #unnamed_bufs == 0 then return end

  local old_files = vim.fn.glob(config.stash_dir .. "/*.stash", false, true)
  for _, fp in ipairs(old_files) do
    os.remove(fp)
  end

  local ts_counts = {}
  for _, buf in ipairs(unnamed_bufs) do
    if buf == vim.api.nvim_get_current_buf() then
      local pos = vim.api.nvim_win_get_cursor(0)
      vim.fn.setbufvar(buf, "__unnamed_stash_cursor", pos)
    end
    local created_at = get_created_at(buf)
    ts_counts[created_at] = (ts_counts[created_at] or 0)
    save_buffer(buf, created_at, ts_counts[created_at])
    ts_counts[created_at] = ts_counts[created_at] + 1
  end
end

--- Restore stashed unnamed buffers.
function M.restore()
  local files = vim.fn.glob(config.stash_dir .. "/*.stash", false, true)
  table.sort(files)

  for _, fp in ipairs(files) do
    local f = io.open(fp, "r")
    if f then
      local meta_line = f:read("*l")
      local content = f:read("*a")
      f:close()

      if meta_line and content then
        local ok, meta = pcall(vim.json.decode, meta_line)
        if not ok then meta = {} end

        if content:sub(-1) == "\n" then
          content = content:sub(1, -2)
        end

        local lines = vim.split(content, "\n", { plain = true })
        if #lines == 0 or (#lines == 1 and lines[1] == "") then goto continue end

        local buf = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
        vim.bo[buf].modified = true

        if meta.created_at then
          vim.fn.setbufvar(buf, "__unnamed_stash_created", meta.created_at)
        end

        if meta.filetype and meta.filetype ~= "" then
          vim.bo[buf].filetype = meta.filetype
        end

        if meta.cursor then
          vim.api.nvim_create_autocmd("BufEnter", {
            buffer = buf,
            once = true,
            callback = function()
              local row = math.min(meta.cursor[1], vim.api.nvim_buf_line_count(buf))
              local col = meta.cursor[2] or 0
              pcall(vim.api.nvim_win_set_cursor, 0, { row, col })
            end,
          })
        end
      end

      ::continue::
    end
  end

  for _, fp in ipairs(files) do
    os.remove(fp)
  end
end

--- Clear all stashed files.
function M.clear()
  local files = vim.fn.glob(config.stash_dir .. "/*.stash", false, true)
  for _, fp in ipairs(files) do os.remove(fp) end
  vim.notify("Unnamed stash cleared", vim.log.levels.INFO)
end

--- Setup the plugin.
---@param opts? table
function M.setup(opts)
  config = vim.tbl_deep_extend("force", defaults, opts or {})

  local group = vim.api.nvim_create_augroup("UnnamedStash", { clear = true })

  -- Restore on startup
  vim.api.nvim_create_autocmd("VimEnter", {
    group = group,
    callback = function()
      if vim.fn.argc() > 0 then return end
      if not config.restore then return end
      vim.schedule(M.restore)
    end,
  })

  -- Save on text changes in unnamed buffers (debounced)
  save_timer = vim.uv.new_timer()
  local function save_debounced()
    save_timer:stop()
    save_timer:start(config.save_delay, 0, vim.schedule_wrap(M.save))
  end

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = group,
    callback = function(ev)
      if vim.api.nvim_buf_get_name(ev.buf) == "" and vim.bo[ev.buf].buftype == "" then
        save_debounced()
      end
    end,
  })

  -- Save on exit hooks as fallback
  vim.api.nvim_create_autocmd({ "QuitPre", "VimLeavePre" }, {
    group = group,
    callback = M.save,
  })

  -- Periodic save
  if config.periodic_save > 0 then
    periodic_timer = vim.uv.new_timer()
    periodic_timer:start(config.periodic_save, config.periodic_save, vim.schedule_wrap(M.save))
  end

  -- Cleanup timers on exit
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      if save_timer then save_timer:stop() save_timer:close() end
      if periodic_timer then periodic_timer:stop() periodic_timer:close() end
    end,
  })

  -- Track cursor position in unnamed buffers
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = vim.api.nvim_create_augroup("UnnamedStashCursor", { clear = true }),
    callback = function(ev)
      local buf = ev.buf
      if vim.api.nvim_buf_get_name(buf) == "" and vim.bo[buf].buftype == "" then
        local pos = vim.api.nvim_win_get_cursor(0)
        vim.fn.setbufvar(buf, "__unnamed_stash_cursor", pos)
      end
    end,
  })

  -- User commands
  vim.api.nvim_create_user_command("UnnamedStashSave", M.save, { desc = "Save unnamed buffers to stash" })
  vim.api.nvim_create_user_command("UnnamedStashRestore", M.restore, { desc = "Restore unnamed buffers from stash" })
  vim.api.nvim_create_user_command("UnnamedStashClear", M.clear, { desc = "Clear stashed unnamed buffers" })
end

return M
