-- SPDX-License-Identifier: GPL-3.0-only
-- Copyright (c) 2026 zxzx

-- 文本模式允许中文，其余模式持续锁英文；restore=true 记忆并恢复文本选择。
-- 重新聚焦时读取桌面选择，查询与切换串行执行。
local M = {}
local state = require((...):match('^(.*)%.') .. '.state')

function M.setup(opts)
  if M.initialized then return end
  opts = opts or {}
  local ascii = opts.ascii_im or 'keyboard-us'
  local restore = opts.restore == true
  for _, bin in ipairs({ 'fcitx5-remote', 'gdbus' }) do
    if vim.fn.executable(bin) ~= 1 then
      vim.notify('ime-lock: 找不到 ' .. bin, vim.log.levels.WARN)
      return
    end
  end
  M.initialized = true

  local focused, stopped = true, false
  local epoch = 0
  local preferred, actual
  local forced = false
  local capture = true
  local adopt = true
  local learn = false
  local busy, process
  local changing = false
  local reconcile
  local failures = 0
  local retry_ticket = 0
  local last_warning

  local function warn(message, always)
    local now = vim.uv.now()
    if not always and last_warning and now - last_warning < 10000 then return end
    last_warning = now
    vim.notify('ime-lock: ' .. message, vim.log.levels.WARN)
  end

  local function input_mode()
    local mode = vim.api.nvim_get_mode().mode:sub(1, 1)
    return vim.tbl_contains(opts.unlocked_modes, mode)
  end

  local was_input = input_mode()

  local function argv(name)
    return {
      'gdbus', 'call', '--session', '--dest', 'org.fcitx.Fcitx5',
      '--object-path', '/controller',
      '--method', 'org.fcitx.Fcitx.Controller1.SetCurrentIM', name,
    }
  end

  local function retry(query)
    failures = failures + 1
    if failures > 8 then return end
    retry_ticket = retry_ticket + 1
    local ticket, focus_epoch = retry_ticket, epoch
    vim.defer_fn(function()
      if stopped or ticket ~= retry_ticket or focus_epoch ~= epoch then return end
      if query and focused then capture = true end
      reconcile()
    end, 300 * math.min(failures, 3))
  end

  local function run(args, callback)
    busy = true
    changing = args[1] == 'gdbus'
    local ok, result = pcall(vim.system, args, { text = true, timeout = 1000 }, function(out)
      vim.schedule(function()
        busy = false
        changing = false
        process = nil
        if stopped then return end
        callback(out)
      end)
    end)
    if ok then
      process = result
    else
      busy, process = false, nil
      changing = false
      callback({ code = -1, stderr = tostring(result) })
    end
  end

  reconcile = function()
    if stopped or busy then return end
    if focused and capture then
      capture = false
      local ticket = epoch
      run({ 'fcitx5-remote', '-n' }, function(out)
        if ticket ~= epoch then reconcile(); return end
        local name = vim.trim(out.stdout or '')
        if out.code ~= 0 or name == '' or name == 'unknown' then
          if failures >= 2 then
            local reason = vim.trim(out.stderr or '')
            if reason == '' then
              reason = out.code == 0 and '没有可用的输入法上下文（返回为空）'
                or ('查询退出码 ' .. tostring(out.code) .. '（可能超时）')
            end
            warn('查询输入法失败：' .. reason)
          end
          retry(true)
          return
        end
        failures = 0
        -- 自己发出的切换不能改写用户偏好；聚焦时则无条件采纳桌面选择。
        if restore and (adopt or learn or (input_mode() and name ~= actual)) then
          preferred = name
          if adopt or input_mode() then forced = false end
        end
        actual = name
        adopt, learn = false, false
        reconcile()
      end)
      return
    end
    local target
    if not focused or input_mode() then
      if restore and forced then target = preferred end
    else
      target = ascii
    end
    if not target then return end
    if target == actual then return end
    run(argv(target), function(out)
      if out.code ~= 0 then
        warn('切换输入法失败：' .. vim.trim(out.stderr or ''))
        actual = nil
        retry(false)
        return
      end
      failures = 0
      retry_ticket = retry_ticket + 1
      actual = target
      forced = restore and target == ascii and preferred ~= ascii
      reconcile()
    end)
  end

  local function mode_changed()
    if not focused then return end
    failures = 0
    retry_ticket = retry_ticket + 1
    local now_input = input_mode()
    if was_input and not forced and not changing then learn = true end
    -- 未完成的切换先收敛；不要读取自己正在写入的临时状态。
    if not busy and (was_input or not forced) then capture = true end
    was_input = now_input
    reconcile()
  end

  local group = vim.api.nvim_create_augroup('ime_lock', { clear = true })
  vim.api.nvim_create_autocmd('ModeChanged', {
    group = group,
    callback = mode_changed,
  })
  vim.api.nvim_create_autocmd({ 'FocusLost', 'FocusGained' }, {
    group = group,
    callback = function(event)
      local gained = event.event == 'FocusGained'
      if focused == gained then return end
      focused = gained
      epoch = epoch + 1
      failures = 0
      retry_ticket = retry_ticket + 1
      capture = gained
      if gained then
        adopt, learn = true, false
        was_input = input_mode()
      end
      reconcile()
    end,
  })
  vim.api.nvim_create_autocmd('VimLeavePre', {
    group = group,
    callback = function()
      stopped = true
      -- 退出时同步等完在途操作，再恢复用户选择。
      if process then process:wait(1100) end
      if restore and focused and preferred and (forced or busy) then
        local ok, out = pcall(function()
          return vim.system(argv(preferred), { text = true, timeout = 1000 }):wait()
        end)
        if not ok or out.code ~= 0 then warn('退出时恢复输入法失败', true) end
      end
    end,
  })
  state.subscribe(function(value)
    if stopped or not focused then return end
    if not value then warn('输入法状态缺失或未知') end
    -- 状态源只提供变化信号；真实名称由 fcitx5 查询，支持恢复任意输入法。
    capture = true
    reconcile()
  end)
  if vim.v.vim_did_enter == 1 then
    reconcile()
  else
    vim.api.nvim_create_autocmd('VimEnter', {
      group = group, once = true, callback = reconcile,
    })
  end
end

return M
