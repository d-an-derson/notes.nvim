local M = {}

---@class notes.Config
---@field dir? string Notes root. Absolute (or ~) so it is the same regardless of cwd.
---@field extension? string|false Appended to new notes created without an extension.
---@field autosave? boolean Save the open note when switching notes or closing the popup.
---@field show_hidden? boolean Show dotfiles in the tree.
---@field width? number Popup width: fraction of the editor (<= 1) or columns (> 1).
---@field height? number Popup height: fraction of the editor (<= 1) or lines (> 1).
---@field tree_width? number Tree pane width: fraction of the popup (<= 1) or columns (> 1).
---@field border? string|table Any value accepted by nvim_open_win's `border`.
---@field editor_win_opts? table<string, any> Window options applied to the editor pane.
---@field keymaps? table<string, string|string[]|false> Set an entry to false to disable it.

---@type notes.Config
M.defaults = {
  dir = vim.fn.stdpath("data") .. "/notes",
  extension = ".md",
  autosave = true,
  show_hidden = false,
  width = 0.8,
  height = 0.8,
  tree_width = 0.25,
  border = "rounded",
  editor_win_opts = {
    wrap = true,
    linebreak = true,
    number = false,
    relativenumber = false,
    signcolumn = "no",
    foldcolumn = "0",
  },
  keymaps = {
    -- tree pane
    open = { "<CR>", "l", "o" },
    collapse = "h",
    create = "a",
    delete = "d",
    rename = "r",
    refresh = "R",
    help = "?",
    close = "q",
    focus_editor = "<Tab>",
    -- editor pane
    focus_tree = "<S-Tab>",
    save = "<C-s>",
  },
}

---@type notes.Config
M.options = {}

---@param dir string
---@return string
local function resolve_dir(dir)
  local path = vim.fs.normalize(vim.fn.fnamemodify(vim.fn.expand(dir), ":p"))
  if #path > 1 then
    path = path:gsub("/+$", "")
  end
  return path
end

---@param opts? notes.Config
function M.setup(opts)
  opts = opts or {}
  local options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts)
  -- Keymap values may be lists; merge them shallowly so a user list replaces the default list.
  options.keymaps = vim.tbl_extend("force", vim.deepcopy(M.defaults.keymaps), opts.keymaps or {})
  options.dir = resolve_dir(options.dir)
  if options.extension and options.extension ~= "" and options.extension:sub(1, 1) ~= "." then
    options.extension = "." .. options.extension
  end
  M.options = options
end

M.setup()

return M
