local config = require("project_nvim.config")
local path = require("project_nvim.utils.path")
local M = {}

-- Internal states
M.attached_lsp = false

---@param client? any
function M.find_lsp_root(client)
  -- Get lsp client for current buffer
  -- Returns nil or string
  local buf_ft = vim.api.nvim_get_option_value("filetype", {
    buf = 0,
  })
  if not buf_ft or buf_ft == "" then
    return
  end

  local clients = client and { client } or vim.lsp.get_clients({
    bufnr = vim.api.nvim_get_current_buf(),
  })
  if next(clients) == nil then
    return nil
  end

  -- NOTE: eslint lsp may return sibling project dir as root dir because current
  -- project doesn't have node_modules yet.
  for _, ct in pairs(clients) do
    local filetypes = ct.config.filetypes
    if filetypes and vim.tbl_contains(filetypes, buf_ft) then
      if not vim.tbl_contains(config.options.ignore_lsp, ct.name) then
        -- ignore single file mode.
        if ct.config.single_file_support ~= true then
          return ct.config.root_dir, ct.name
        end
      end
    end
  end

  return nil
end

function M.find_pattern_root()
  local search_dir = vim.fn.expand("%:p:h", true)
  if vim.fn.has("win32") > 0 then
    search_dir = search_dir:gsub("\\", "/")
  end

  local patterns = config.options.patterns
  if not patterns or #patterns < 1 then
    patterns = { ".git", "package.json" }
  end

  local found = vim.fs.root(search_dir, patterns)
  if found == vim.env.HOME then
    return nil, nil
  end

  return found, "pattern"
end

---@diagnostic disable-next-line: unused-local
local on_attach_lsp = function(client, bufnr)
  M.on_buf_enter({
    trigger = "lsp",
    client = client,
    buf = bufnr,
  }) -- Recalculate root dir after lsp attaches
end

--- FIXME: do not hijack lsp atttach.
--- Only run on buffer is visible to window.
function M.attach_to_lsp()
  if M.attached_lsp then
    return
  end

  vim.api.nvim_create_augroup("setup_project_nvim_lsp", { clear = true })

  vim.api.nvim_create_autocmd("LspAttach", {
    group = "setup_project_nvim_lsp",
    pattern = "*",
    callback = function(args)
      local bufnr = args.buf
      local client = vim.lsp.get_client_by_id(args.data.client_id)
      if not client then
        return
      end

      on_attach_lsp(client, bufnr)
    end,
  })

  M.attached_lsp = true
end

function M.set_pwd(dir, method)
  if dir ~= nil then
    local scope_chdir = config.options.scope_chdir

    vim.api.nvim_exec_autocmds("User", {
      pattern = "ProjectNvimSetPwd",
      modeline = false,
      data = {
        dir = dir,
        method = method,
        scope = scope_chdir,
      },
    })

    if vim.fn.getcwd() ~= dir then
      if scope_chdir == "global" then
        vim.api.nvim_set_current_dir(dir)
      elseif scope_chdir == "tab" then
        vim.cmd("tcd " .. dir)
      elseif scope_chdir == "win" then
        vim.cmd("lcd " .. dir)
      else
        return
      end

      if config.options.silent_chdir == false then
        vim.notify("Set CWD to " .. dir .. " using " .. method)
      end
    end
    return true
  end

  return false
end

local function make_lsp_method_name(name)
  return '"' .. name .. '"' .. " lsp"
end

---@param ctx? {trigger:'lsp'|'manual'|'auto', client:any, buf:number}
function M.get_project_root(ctx)
  ctx = ctx or {}
  if ctx.trigger ~= "lsp" and vim.b[0].project_nvim_cwd ~= nil then
    return vim.b[ctx.buf or 0].project_nvim_cwd, vim.b[ctx.buf or 0].project_nvim_method
  elseif
    ctx.trigger == "lsp"
    and ctx.client
    and make_lsp_method_name(ctx.client.name) == vim.b[ctx.buf or 0].project_nvim_method
  then
    return vim.b[ctx.buf or 0].project_nvim_cwd, vim.b[ctx.buf or 0].project_nvim_method
  end

  local detection_methods = ctx.trigger == "lsp" and { "lsp" } or config.options.detection_methods
  local buf = ctx.buf or vim.api.nvim_get_current_buf()
  -- returns project root, as well as method
  for _, detection_method in ipairs(detection_methods) do
    if detection_method == "lsp" then
      local root, lsp_name = M.find_lsp_root(ctx.client)
      if root ~= nil then
        local method_name = make_lsp_method_name(lsp_name)
        vim.b[buf].project_nvim_cwd = root
        vim.b[buf].project_nvim_method = method_name
        return root, method_name
      end
    elseif detection_method == "pattern" then
      local root, method = M.find_pattern_root()
      if root ~= nil then
        vim.b[buf].project_nvim_cwd = root
        vim.b[buf].project_nvim_method = method
        return root, method
      end
    end
  end
end

function M.is_file(buf)
  buf = buf or 0

  local buf_type = vim.api.nvim_get_option_value("buftype", {
    buf = buf,
  })
  local ft = vim.api.nvim_get_option_value("filetype", {
    buf = buf,
  })

  local buf_name = vim.api.nvim_buf_get_name(buf)
  if not buf_name or buf_name == "" then
    return
  end

  local whitelisted_buf_type = { "", "acwrite" }
  local is_in_whitelist = false
  for _, wtype in ipairs(whitelisted_buf_type) do
    if buf_type == wtype then
      is_in_whitelist = true
      break
    end
  end
  if not is_in_whitelist then
    return false
  end

  if config.options.exclude_ft and vim.tbl_contains(config.options.exclude_ft, ft) then
    return false
  end

  if config.options.ignore_buffer_fn then
    local value = config.options.ignore_buffer_fn(buf)
    if value == true then
      return false
    end
  end

  return true
end

---@param ctx? {trigger:string, client?:any, buf:number}
function M.on_buf_enter(ctx)
  ctx = ctx or {}
  if vim.v.vim_did_enter == 0 or vim.g.project_nvim_disable then
    return
  end
  if vim.b[ctx.buf or 0].project_nvim_disable then
    return
  end

  if not M.is_file(ctx.buf or 0) then
    return
  end

  local current_dir = vim.fn.expand("%:p:h", true)
  if not path.exists(current_dir) or path.is_excluded(current_dir) then
    return
  end

  local root, method = M.get_project_root(ctx)
  M.set_pwd(root, method)
end

function M.add_project_manually()
  local current_dir = vim.fn.expand("%:p:h", true)
  M.set_pwd(current_dir, "manual")
end

function M.init()
  local autocmds = {}
  if not config.options.manual_mode then
    autocmds[#autocmds + 1] = 'autocmd VimEnter,BufEnter * ++nested lua require("project_nvim.project").on_buf_enter()'

    if vim.tbl_contains(config.options.detection_methods, "lsp") then
      M.attach_to_lsp()
    end
  end

  vim.cmd([[
    command! ProjectRoot lua require("project_nvim.project").on_buf_enter()
    command! AddProject lua require("project_nvim.project").add_project_manually()
  ]])

  vim.cmd([[augroup project_nvim
            au!
  ]])
  for _, value in ipairs(autocmds) do
    vim.cmd(value)
  end
  vim.cmd("augroup END")
end

return M
