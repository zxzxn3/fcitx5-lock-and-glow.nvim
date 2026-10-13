local M = {}

-- Explicit setup only: requiring the plugin does not switch the desktop input method.
function M.setup(options)
  if M.initialized then return end
  options = vim.tbl_deep_extend('force', {
    lock = { enabled = true, ascii_im = 'keyboard-us', restore = false },
    cursor = { enabled = true, color = '#ffbf69', input_methods = { 'rime' } },
    source = { monitor = true, poll_interval = 5000 },
  }, options or {})
  for _, bin in ipairs({ 'fcitx5-remote', 'gdbus' }) do
    if vim.fn.executable(bin) ~= 1 then
      vim.notify('fcitx5-ime: missing executable ' .. bin, vim.log.levels.WARN)
      return
    end
  end
  assert(options.source.poll_interval > 0, 'poll_interval must be positive')
  M.initialized = true
  require('fcitx5-ime.state').setup(options.source)
  local cursor = require('fcitx5-ime.cursor')
  cursor.options = options.cursor
  cursor.setup()
  if options.lock.enabled then require('fcitx5-ime.lock').setup(options.lock) end
end

return M
