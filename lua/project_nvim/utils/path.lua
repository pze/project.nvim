local config = require("project_nvim.config")
local M = {}

function M.is_excluded(dir)
  for _, dir_pattern in ipairs(config.options.exclude_dirs) do
    if dir:match(dir_pattern) ~= nil then
      return true
    end
  end

  return false
end

function M.exists(path)
  return vim.fn.empty(vim.fn.glob(path)) == 0
end

return M
