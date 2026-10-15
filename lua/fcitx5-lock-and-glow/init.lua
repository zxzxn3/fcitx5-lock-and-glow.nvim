local M = {}

-- Explicit setup only: requiring the plugin does not switch the desktop input method.
function M.setup(options)
  if M.initialized then return end
  options = vim.tbl_deep_extend('force', {
    lock = {
      enabled = true, ascii_im = 'keyboard-us', restore = false,
      unlocked_modes = { 'i', 'R', 't', 'c', 's', 'S', '\019' },
    },
    cursor = { enabled = true, color = '#ffbf69', input_methods = { 'rime' } },
    source = { monitor = true, poll_interval = 5000 },
  }, options or {})
  assert(type(options.lock.unlocked_modes) == 'table' and vim.islist(options.lock.unlocked_modes),
    'lock.unlocked_modes must be a list of single-character mode codes')
  for _, mode in ipairs(options.lock.unlocked_modes) do
    assert(type(mode) == 'string' and #mode == 1,
      'lock.unlocked_modes entries must be single-character mode codes; see :help mode()')
  end
  for _, bin in ipairs({ 'fcitx5-remote', 'gdbus' }) do
    if vim.fn.executable(bin) ~= 1 then
      vim.notify('fcitx5-lock-and-glow: missing executable ' .. bin, vim.log.levels.WARN)
      return
    end
  end
  assert(options.source.poll_interval > 0, 'poll_interval must be positive')
  M.initialized = true
  options.source.input_methods = options.cursor.input_methods
  require('fcitx5-lock-and-glow.state').setup(options.source)
  local cursor = require('fcitx5-lock-and-glow.cursor')
  cursor.options = options.cursor
  cursor.setup()
  if options.lock.enabled then require('fcitx5-lock-and-glow.lock').setup(options.lock) end
end

return M
