-- 根据状态源标记中文光标；通过 guicursor 指定高亮组。

local M = {}
M.options = {
  enabled = true, -- Cursor color only; does not disable the lock module.
  color = '#ffbf69', -- Chinese input cursor background.
}
local GROUP = 'ImeCursor'
local state = require((...):match('^(.*)%.') .. '.state')
local base_guicursor
local chinese = false
local initialized = false

-- 原生高亮接口接受整数颜色；保留主题的光标前景色。
local function paint_group()
  vim.api.nvim_set_hl(0, GROUP, {
    bg = M.options.color, fg = vim.api.nvim_get_hl(0, { name = 'Cursor' }).fg,
  })
end

local function is_shape_arg(token)
  return token == 'block'
    or token:match('^ver%d+$') ~= nil
    or token:match('^hor%d+$') ~= nil
    or token:match('^blinkwait%d+$') ~= nil
    or token:match('^blinkon%d+$') ~= nil
    or token:match('^blinkoff%d+$') ~= nil
end

-- 保留光标形状和闪烁参数，替换高亮组。
local function to_group(part)
  local modes, args = part:match('^([^:]+):(.+)$')
  if not modes then
    return part
  end
  local kept = {}
  for token in args:gmatch('[^-]+') do
    if is_shape_arg(token) then
      kept[#kept + 1] = token
    end
  end
  kept[#kept + 1] = GROUP
  return modes .. ':' .. table.concat(kept, '-')
end

local function orange_guicursor()
  local parts = {}
  for part in base_guicursor:gmatch('[^,]+') do
    parts[#parts + 1] = to_group(part)
  end
  return table.concat(parts, ',')
end

local function apply(state)
  local want = state == 'zh'
  if want == chinese then
    return
  end
  chinese = want
  if chinese then
    paint_group()
    vim.o.guicursor = orange_guicursor()
  else
    vim.o.guicursor = base_guicursor
  end
end

local function refresh()
  apply(state.read() or 'en')
end

function M.setup()
  if initialized or not M.options.enabled then return end
  base_guicursor = vim.o.guicursor
  if base_guicursor == '' then
    return
  end
  initialized = true
  local group = vim.api.nvim_create_augroup('ime_cursor', { clear = true })
  state.subscribe(function(value) apply(value or 'en') end)
  vim.api.nvim_create_autocmd({ 'FocusGained', 'ColorScheme' }, {
    group = group,
    desc = '重新确认输入法状态 / 换配色后补上光标色',
    callback = function(event)
      if event.event == 'ColorScheme' and vim.o.guicursor ~= orange_guicursor() then
        base_guicursor = vim.o.guicursor
      end
      if chinese then
        paint_group()
        vim.o.guicursor = orange_guicursor()
      end
      refresh()
    end,
  })

end

return M
