-- SPDX-License-Identifier: GPL-3.0-only
-- Copyright (c) 2026 zxzx

-- Standalone state source: Fcitx5 tray signals trigger queries; polling covers missing signals.
local M = {}
local listeners = {}
local current, process, job, timer
local observed_name
local input_methods
local initialized, stopped, busy, dirty = false, false, false, false
local last_warning
local failures = 0

-- Bound repeated service/monitor failure notifications.
local function warn(message)
  local now = vim.uv.now()
  if last_warning and now - last_warning < 10000 then return end
  last_warning = now
  vim.notify('fcitx5-lock-and-glow: ' .. message, vim.log.levels.WARN)
end

-- Shared backend contract: read()/subscribe() use 'zh', 'en', or nil (unknown).
function M.read() return current end

-- Publish only actual changes, so our own repeated queries do not create an event loop.
local function publish(name)
  if name == observed_name then return end
  observed_name = name
  current = name and (vim.tbl_contains(input_methods, name) and 'zh' or 'en') or nil
  for _, callback in ipairs(listeners) do callback(current) end
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
        failures = failures + 1
        if failures > 1 then
          local reason = vim.trim(out.stderr or '')
          if reason == '' then
            reason = out.code == 0 and 'no active input context' or ('query exited with code ' .. tostring(out.code))
          end
          warn('cannot query the current input method: ' .. reason)
        end
      else
        failures = 0
        publish(name)
      end
      if dirty then dirty = false; M.refresh() end
    end)
  end)
  if ok then process = result
  else busy = false; publish(nil); warn(tostring(result)) end
end

-- Tray signals use a separate connection: match signal types, not the controller sender.
local function monitor()
  if stopped or job then return end
  if vim.fn.executable('dbus-monitor') ~= 1 then
    warn('dbus-monitor unavailable; polling continues')
    return
  end
  local pending = ''
  local id = vim.fn.jobstart({ 'dbus-monitor', '--session', '--monitor',
    "type='signal',interface='org.kde.StatusNotifierItem',path='/StatusNotifierItem',member='NewIcon'",
    "type='signal',interface='org.kde.StatusNotifierItem',path='/StatusNotifierItem',member='NewToolTip'",
    "type='signal',sender='org.freedesktop.DBus',interface='org.freedesktop.DBus',member='NameOwnerChanged',arg0='org.fcitx.Fcitx5'",
  }, {
    on_stdout = function(_, data)
      if stopped then return end
      pending = pending .. table.concat(data, '\n')
      local lines = vim.split(pending, '\n', { plain = true })
      pending = table.remove(lines)
      for _, line in ipairs(lines) do
        if line:match('^signal ') and (line:find('member=NewIcon', 1, true)
          or line:find('member=NewToolTip', 1, true) or line:find('member=NameOwnerChanged', 1, true)) then
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
  input_methods = options.input_methods
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
