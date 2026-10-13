-- Standalone state source: Fcitx5 tray signals trigger queries; polling covers missing signals.
local M = {}
local listeners = {}
local current, process, job, timer
local initialized, stopped, busy, dirty = false, false, false, false
local last_warning

-- Bound repeated service/monitor failure notifications.
local function warn(message)
  local now = vim.uv.now()
  if last_warning and now - last_warning < 10000 then return end
  last_warning = now
  vim.notify('fcitx5-ime: ' .. message, vim.log.levels.WARN)
end

-- Expose the last observed name; nil means unknown, not an English input method.
function M.read() return current end

-- Publish only actual changes, so our own repeated queries do not create an event loop.
local function publish(name)
  if name == current then return end
  current = name
  for _, callback in ipairs(listeners) do callback(name) end
end

-- Coalesce signals arriving during a query into one follow-up query.
function M.refresh()
  if stopped then return end
  if busy then dirty = true; return end
  busy = true
  local ok, result = pcall(vim.system, { 'fcitx5-remote', '-n' }, { text = true, timeout = 1000 }, function(out)
    vim.schedule(function()
      busy, process = false, nil
      if stopped then return end
      local name = vim.trim(out.stdout or '')
      if out.code ~= 0 or name == '' or name == 'unknown' then
        publish(nil)
        warn('cannot query the current input method')
      else publish(name) end
      if dirty then dirty = false; M.refresh() end
    end)
  end)
  if ok then process = result
  else busy = false; publish(nil); warn(tostring(result)) end
end

-- gdbus tracks the service owner; a dead monitor is restarted by the polling timer.
local function monitor()
  if stopped or job then return end
  local pending = ''
  local id = vim.fn.jobstart({ 'gdbus', 'monitor', '--session', '--dest', 'org.fcitx.Fcitx5' }, {
    on_stdout = function(_, data)
      if stopped then return end
      pending = pending .. table.concat(data, '\n')
      local lines = vim.split(pending, '\n', { plain = true })
      pending = table.remove(lines)
      for _, line in ipairs(lines) do
        if line:find('org.kde.StatusNotifierItem.NewIcon', 1, true)
          or line:find('org.kde.StatusNotifierItem.NewToolTip', 1, true)
          or line:find('owned by', 1, true) or line:find('does not have an owner', 1, true) then
          M.refresh()
          break
        end
      end
    end,
    on_exit = function() job = nil; if not stopped then warn('D-Bus monitor stopped; polling continues') end end,
  })
  if id > 0 then job = id else warn('cannot start D-Bus monitor; polling continues') end
end

-- Subscribe without touching runtime files or starting a separate daemon.
function M.subscribe(callback)
  listeners[#listeners + 1] = callback
  if current then callback(current) end
end

-- Stop all state-source resources; the lock module separately finishes/restores its writes.
function M.stop()
  stopped = true
  if timer then timer:stop(); timer:close(); timer = nil end
  if job then vim.fn.jobstop(job); job = nil end
  if process then process:kill(15); process = nil end
end

function M.setup(options)
  if initialized then return end
  initialized = true
  local group = vim.api.nvim_create_augroup('fcitx5_ime_source', { clear = true })
  vim.api.nvim_create_autocmd('VimLeavePre', { group = group, callback = M.stop })
  vim.api.nvim_create_autocmd('FocusGained', { group = group, callback = M.refresh })
  timer = assert(vim.uv.new_timer())
  timer:start(0, options.poll_interval, vim.schedule_wrap(function()
    if stopped then return end
    if options.monitor then monitor() end
    M.refresh()
  end))
end

return M
