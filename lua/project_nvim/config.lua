local M = {}

---@class ProjectOptions
M.defaults = {
  -- Manual mode doesn't automatically change your root directory, so you have
  -- the option to manually do so using `:ProjectRoot` command.
  manual_mode = false,

  -- Methods of detecting the root directory. **"lsp"** uses the native neovim
  -- lsp, while **"pattern"** uses vim-rooter like glob pattern matching. Here
  -- order matters: if one is not detected, the other is used as fallback. You
  -- can also delete or rearangne the detection methods.
  detection_methods = { "lsp", "pattern" },

  -- All the patterns used to detect root dir, when **"pattern"** is in
  -- detection_methods
  patterns = { ".git", ".hg", ".svn", "package.json", ".direnv", "Cargo.toml", "pyproject.toml" },

  get_patterns = nil,

  -- Table of lsp clients to ignore by name
  -- eg: { "efm", ... }
  ignore_lsp = {
    "efm",
    "null-ls",
    "copilot",
    "jsonls",
    "eslint",
  },

  -- Don't calculate root dir on specific directories
  -- Ex: { "~/.cargo/*", ... }
  exclude_dirs = {},
  -- Callback to check if specific buf should be excluded
  -- @type function
  ignore_buffer_fn = nil,
  -- excluded filetypes
  exclude_ft = { "gitcommit", "git", "fugitive" },

  -- When set to false, you will get a message when project.nvim changes your
  -- directory.
  silent_chdir = true,

  -- What scope to change the directory, valid options are
  -- * global (default)
  -- * tab
  -- * win
  scope_chdir = "tab",
}

---@type ProjectOptions
M.options = {}

M.setup = function(options)
  M.options = vim.tbl_deep_extend("force", M.defaults, options or {})

  local glob = require("project_nvim.utils.globtopattern")
  local home = vim.fn.expand("~")
  M.options.exclude_dirs = vim.tbl_map(function(pattern)
    if vim.startswith(pattern, "~/") then
      pattern = home .. "/" .. pattern:sub(3, #pattern)
    end
    return glob.globtopattern(pattern)
  end, M.options.exclude_dirs)

  vim.opt.autochdir = false -- implicitly unset autochdir

  require("project_nvim.project").init()
end

return M
