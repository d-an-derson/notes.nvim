local config = require("notes.config")
local fs = require("notes.fs")
local tree = require("notes.tree")

local api = vim.api

local M = {}

local ns = api.nvim_create_namespace("notes")

local S = {
  tree_buf = nil, ---@type integer?
  tree_win = nil, ---@type integer?
  editor_win = nil, ---@type integer?
  placeholder = nil, ---@type integer?
  augroup = nil, ---@type integer?
  current = nil, ---@type string? note shown in the editor pane
  nodes = {}, ---@type notes.Entry[]
}

local function opts()
  return config.options
end

local function root()
  return config.options.dir
end

local function notify(msg, level)
  vim.notify("Notes: " .. msg, level or vim.log.levels.INFO)
end

local function valid_win(win)
  return win ~= nil and api.nvim_win_is_valid(win)
end

function M.is_open()
  return valid_win(S.tree_win) and valid_win(S.editor_win)
end

local function has_border()
  local border = opts().border
  return border ~= nil and border ~= "none" and border ~= ""
end

--- Path relative to the notes root.
local function rel(path)
  if path == root() then
    return ""
  end
  if tree.is_under(path, root()) then
    return path:sub(#root() + 2)
  end
  return vim.fn.fnamemodify(path, ":~")
end

--- Resolve user input (relative to the notes root) to an absolute path inside it.
---@return string?
local function resolve(input)
  local path = vim.fs.normalize(vim.fs.joinpath(root(), input))
  if path == root() or not tree.is_under(path, root()) then
    return nil
  end
  return path
end

---@return integer?
local function editor_buf()
  return valid_win(S.editor_win) and api.nvim_win_get_buf(S.editor_win) or nil
end

--- Write `buf` if it is a modified note inside the notes root.
local function save_buf(buf)
  if not (buf and api.nvim_buf_is_valid(buf)) then
    return true
  end
  local name = api.nvim_buf_get_name(buf)
  if not vim.bo[buf].modified or vim.bo[buf].buftype ~= "" or not tree.is_under(name, root()) then
    return true
  end
  local ok, err = pcall(api.nvim_buf_call, buf, function()
    vim.cmd("silent write")
  end)
  if not ok then
    notify("failed to save " .. rel(name) .. ": " .. err, vim.log.levels.ERROR)
  end
  return ok
end

local function map(buf, modes, lhs, fn, desc)
  if not lhs then
    return
  end
  for _, key in ipairs(type(lhs) == "table" and lhs or { lhs }) do
    vim.keymap.set(modes, key, fn, { buffer = buf, nowait = true, silent = true, desc = "Notes: " .. desc })
  end
end

local function first_key(lhs)
  return type(lhs) == "table" and lhs[1] or lhs
end

local function layout()
  local o = opts()
  local cols, lines = vim.o.columns, vim.o.lines - vim.o.cmdheight
  local b = has_border() and 2 or 0

  local width = o.width <= 1 and math.floor(cols * o.width) or o.width
  width = math.min(width, cols - 2)
  local height = o.height <= 1 and math.floor(lines * o.height) or o.height
  height = math.min(height, lines - 2)

  local tree_width = o.tree_width <= 1 and math.floor(width * o.tree_width) or o.tree_width
  tree_width = math.max(tree_width, 16)
  local editor_width = math.max(width - tree_width - 2 * b, 10)

  local row = math.floor((lines - height) / 2)
  local col = math.floor((cols - width) / 2)
  return {
    tree = { relative = "editor", row = row, col = col, width = tree_width, height = height - b },
    editor = {
      relative = "editor",
      row = row,
      col = col + tree_width + b,
      width = editor_width,
      height = height - b,
    },
  }
end

-- Tree ----------------------------------------------------------------------

---@param focus_path? string Put the cursor on this path after rendering.
function M.render(focus_path)
  if not (S.tree_buf and api.nvim_buf_is_valid(S.tree_buf)) then
    return
  end
  local old_line = valid_win(S.tree_win) and api.nvim_win_get_cursor(S.tree_win)[1] or 1
  if not focus_path and S.nodes[old_line] then
    focus_path = S.nodes[old_line].path
  end

  S.nodes = tree.build(root(), opts().show_hidden)
  tree.render(S.tree_buf, ns, S.nodes, S.current)

  if valid_win(S.tree_win) then
    local line = math.min(old_line, math.max(#S.nodes, 1))
    for i, node in ipairs(S.nodes) do
      if node.path == focus_path then
        line = i
        break
      end
    end
    api.nvim_win_set_cursor(S.tree_win, { line, 0 })
  end
end

local function node_at_cursor()
  return S.nodes[api.nvim_win_get_cursor(0)[1]]
end

--- Folder that new notes should go in, based on the node under the cursor.
local function target_dir(node)
  if not node then
    return root()
  end
  if node.type == "directory" then
    return node.path
  end
  return vim.fs.dirname(node.path)
end

-- Editor --------------------------------------------------------------------

local setup_editor_buf

local function placeholder()
  if S.placeholder and api.nvim_buf_is_valid(S.placeholder) then
    return S.placeholder
  end
  local keys = opts().keymaps
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "hide"
  api.nvim_buf_set_lines(buf, 0, -1, false, {
    "",
    "  No note open.",
    "",
    ("  Select a note in the list and press %s,"):format(first_key(keys.open) or "<CR>"),
    ("  or press %s to create one."):format(first_key(keys.create) or "a"),
  })
  vim.bo[buf].modifiable = false
  setup_editor_buf(buf)
  S.placeholder = buf
  return buf
end

local function update_editor_title()
  if not valid_win(S.editor_win) or not has_border() then
    return
  end
  local title = S.current and rel(S.current) or "no note"
  api.nvim_win_set_config(S.editor_win, { title = " " .. title .. " ", title_pos = "center" })
end

--- Sync state after a buffer is shown in the editor pane (by us or by the user, e.g. `:e`).
local function on_editor_buf(buf)
  if buf == S.placeholder then
    S.current = nil
  elseif vim.bo[buf].buftype == "" and api.nvim_buf_get_name(buf) ~= "" then
    S.current = api.nvim_buf_get_name(buf)
    setup_editor_buf(buf)
  end
  for name, value in pairs(opts().editor_win_opts or {}) do
    vim.wo[S.editor_win][name] = value
  end
  update_editor_title()
  M.render()
end

local function show_placeholder()
  if valid_win(S.editor_win) then
    api.nvim_win_set_buf(S.editor_win, placeholder())
    on_editor_buf(S.placeholder)
  end
end

--- Open a note in the editor pane.
---@param path string
---@param focus? boolean
function M.open_note(path, focus)
  if not M.is_open() then
    return
  end
  if opts().autosave then
    save_buf(editor_buf())
  end
  local ok, err = pcall(api.nvim_win_call, S.editor_win, function()
    vim.cmd("keepalt keepjumps edit " .. vim.fn.fnameescape(path))
  end)
  if not ok then
    notify(err, vim.log.levels.ERROR)
    return
  end
  on_editor_buf(api.nvim_win_get_buf(S.editor_win))
  if focus then
    api.nvim_set_current_win(S.editor_win)
  end
end

--- Wipe every buffer at or below `path`. Returns true if the editor pane was showing one.
local function drop_buffers(path)
  local shown = editor_buf()
  local was_shown = false
  for _, buf in ipairs(api.nvim_list_bufs()) do
    if tree.is_under(api.nvim_buf_get_name(buf), path) then
      if buf == shown then
        was_shown = true
        show_placeholder()
      end
      pcall(api.nvim_buf_delete, buf, { force = true })
    end
  end
  if S.current and tree.is_under(S.current, path) then
    S.current = nil
  end
  return was_shown
end

-- Actions -------------------------------------------------------------------

local actions = {}

function actions.open()
  local node = node_at_cursor()
  if not node then
    return
  end
  if node.type == "directory" then
    tree.expanded[node.path] = not tree.expanded[node.path] or nil
    M.render(node.path)
  else
    M.open_note(node.path, true)
  end
end

function actions.collapse()
  local node = node_at_cursor()
  if not node then
    return
  end
  if node.type == "directory" and tree.expanded[node.path] then
    tree.expanded[node.path] = nil
    M.render(node.path)
    return
  end
  local parent = vim.fs.dirname(node.path)
  if parent ~= root() then
    tree.expanded[parent] = nil
    M.render(parent)
  end
end

function actions.create()
  local prefix = rel(target_dir(node_at_cursor()))
  if prefix ~= "" then
    prefix = prefix .. "/"
  end
  vim.ui.input({ prompt = "New note (end with / for a folder): ", default = prefix }, function(input)
    input = input and vim.trim(input)
    if not input or input == "" or input == prefix then
      return
    end
    local is_dir = input:sub(-1) == "/"
    local path = resolve(input)
    if not path then
      notify("invalid path: " .. input, vim.log.levels.ERROR)
      return
    end
    local ext = opts().extension
    if not is_dir and ext and ext ~= "" and vim.fn.fnamemodify(path, ":e") == "" then
      path = path .. ext
    end

    local ok, err = (is_dir and fs.create_dir or fs.create_file)(path)
    if not ok then
      notify(("could not create %s: %s"):format(rel(path), err), vim.log.levels.ERROR)
      return
    end
    tree.reveal(root(), path)
    if is_dir then
      tree.expanded[path] = true
    end
    M.render(path)
    if not is_dir then
      M.open_note(path, true)
    end
  end)
end

function actions.delete()
  local node = node_at_cursor()
  if not node then
    return
  end
  local label = rel(node.path) .. (node.type == "directory" and "/ and everything in it" or "")
  if vim.fn.confirm("Delete " .. label .. "?", "&Yes\n&No", 2) ~= 1 then
    return
  end
  local ok, err = fs.delete(node.path)
  if not ok then
    notify(("could not delete %s: %s"):format(rel(node.path), err), vim.log.levels.ERROR)
    return
  end
  drop_buffers(node.path)
  tree.move_expanded(node.path)
  M.render()
end

function actions.rename()
  local node = node_at_cursor()
  if not node then
    return
  end
  vim.ui.input({ prompt = "Rename / move to: ", default = rel(node.path) }, function(input)
    input = input and vim.trim(input)
    if not input or input == "" then
      return
    end
    local new = resolve(input)
    if not new then
      notify("invalid path: " .. input, vim.log.levels.ERROR)
      return
    end
    if new == node.path then
      return
    end
    if node.type == "directory" and tree.is_under(new, node.path) then
      notify("cannot move a folder into itself", vim.log.levels.ERROR)
      return
    end

    for _, buf in ipairs(api.nvim_list_bufs()) do
      if tree.is_under(api.nvim_buf_get_name(buf), node.path) then
        save_buf(buf)
      end
    end
    local ok, err = fs.rename(node.path, new)
    if not ok then
      notify(("could not move %s: %s"):format(rel(node.path), err), vim.log.levels.ERROR)
      return
    end

    local new_current = S.current
      and tree.is_under(S.current, node.path)
      and new .. S.current:sub(#node.path + 1)
    local reopen = drop_buffers(node.path)
    tree.move_expanded(node.path, new)
    tree.reveal(root(), new)
    M.render(new)
    if reopen and new_current then
      M.open_note(new_current, false)
    end
  end)
end

function actions.refresh()
  M.render()
end

function actions.focus_editor()
  if valid_win(S.editor_win) then
    api.nvim_set_current_win(S.editor_win)
  end
end

function actions.focus_tree()
  if M.is_open() and api.nvim_get_current_win() == S.editor_win then
    api.nvim_set_current_win(S.tree_win)
  end
end

function actions.save()
  local buf = api.nvim_get_current_buf()
  if vim.bo[buf].buftype ~= "" then
    return
  end
  local ok, err = pcall(vim.cmd, "silent write")
  if ok then
    notify("saved " .. rel(api.nvim_buf_get_name(buf)))
  else
    notify(err, vim.log.levels.ERROR)
  end
end

function actions.help()
  local keys = opts().keymaps
  local function k(name)
    local lhs = keys[name]
    return type(lhs) == "table" and table.concat(lhs, "/") or tostring(lhs)
  end
  notify(table.concat({
    "",
    "Tree:",
    ("  %-14s open note / toggle folder"):format(k("open")),
    ("  %-14s collapse folder"):format(k("collapse")),
    ("  %-14s new note (trailing / = folder)"):format(k("create")),
    ("  %-14s delete"):format(k("delete")),
    ("  %-14s rename / move"):format(k("rename")),
    ("  %-14s refresh"):format(k("refresh")),
    ("  %-14s focus editor"):format(k("focus_editor")),
    ("  %-14s close"):format(k("close")),
    "Editor:",
    ("  %-14s save"):format(k("save")),
    ("  %-14s focus tree"):format(k("focus_tree")),
  }, "\n"))
end

function actions.close()
  M.close()
end

local function ensure_tree_buf()
  if S.tree_buf and api.nvim_buf_is_valid(S.tree_buf) then
    return S.tree_buf
  end
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].filetype = "notes"
  vim.bo[buf].modifiable = false

  local keys = opts().keymaps
  for _, name in ipairs({ "open", "collapse", "create", "delete", "rename", "refresh", "help", "close", "focus_editor" }) do
    map(buf, "n", keys[name], actions[name], name)
  end
  S.tree_buf = buf
  return buf
end

setup_editor_buf = function(buf)
  if vim.b[buf].notes_mapped then
    return
  end
  local keys = opts().keymaps
  map(buf, "n", keys.focus_tree, actions.focus_tree, "focus tree")
  map(buf, { "n", "i" }, keys.save, actions.save, "save note")
  vim.b[buf].notes_mapped = true
end

-- Window lifecycle ----------------------------------------------------------

local function create_autocmds()
  S.augroup = api.nvim_create_augroup("NotesUI", { clear = true })

  api.nvim_create_autocmd("WinClosed", {
    group = S.augroup,
    callback = function(ev)
      local win = tonumber(ev.match)
      if win ~= S.tree_win and win ~= S.editor_win then
        return
      end
      if win == S.editor_win and opts().autosave then
        save_buf(ev.buf)
      end
      vim.schedule(M.close)
    end,
  })

  -- Keep state in sync when the user runs e.g. `:e other.md` inside the editor pane.
  api.nvim_create_autocmd("BufEnter", {
    group = S.augroup,
    callback = function(ev)
      if api.nvim_get_current_win() == S.editor_win then
        on_editor_buf(ev.buf)
      end
    end,
  })

  -- Close when focus moves to a regular window. Other floats (pickers, input prompts) are fine.
  api.nvim_create_autocmd("WinEnter", {
    group = S.augroup,
    callback = function()
      local win = api.nvim_get_current_win()
      if win == S.tree_win or win == S.editor_win or api.nvim_win_get_config(win).relative ~= "" then
        return
      end
      vim.schedule(M.close)
    end,
  })

  api.nvim_create_autocmd("VimResized", { group = S.augroup, callback = M.resize })
end

function M.open()
  if M.is_open() then
    api.nvim_set_current_win(S.tree_win)
    return
  end
  M.close() -- clean up a half-open state

  local ok, err = fs.mkdir(root())
  if not ok then
    notify(("could not create %s: %s"):format(root(), err), vim.log.levels.ERROR)
    return
  end
  ensure_tree_buf()

  local l = layout()
  local border = opts().border
  local tree_cfg = vim.tbl_extend("force", l.tree, { border = border, style = "minimal", zindex = 50 })
  local editor_cfg = vim.tbl_extend("force", l.editor, { border = border, zindex = 50 })
  if has_border() then
    tree_cfg.title = " " .. vim.fn.fnamemodify(root(), ":~") .. " "
    tree_cfg.title_pos = "center"
    tree_cfg.footer = " " .. (first_key(opts().keymaps.help) or "?") .. " help "
    tree_cfg.footer_pos = "center"
  end

  S.editor_win = api.nvim_open_win(placeholder(), false, editor_cfg)
  S.tree_win = api.nvim_open_win(S.tree_buf, true, tree_cfg)
  vim.wo[S.tree_win].cursorline = true
  vim.wo[S.tree_win].wrap = false
  vim.wo[S.tree_win].winfixbuf = true

  if S.current and fs.exists(S.current) then
    tree.reveal(root(), S.current)
    M.open_note(S.current, false)
  else
    on_editor_buf(S.placeholder)
  end
  M.render(S.current)
  create_autocmds()
end

function M.close()
  if S.augroup then
    pcall(api.nvim_del_augroup_by_id, S.augroup)
    S.augroup = nil
  end
  if opts().autosave then
    save_buf(editor_buf())
  end
  if vim.fn.mode():sub(1, 1) == "i" then
    vim.cmd("stopinsert")
  end
  for _, win in ipairs({ S.editor_win, S.tree_win }) do
    if valid_win(win) then
      pcall(api.nvim_win_close, win, true)
    end
  end
  S.editor_win, S.tree_win = nil, nil
end

function M.toggle()
  if M.is_open() then
    M.close()
  else
    M.open()
  end
end

function M.resize()
  if not M.is_open() then
    return
  end
  local l = layout()
  api.nvim_win_set_config(S.tree_win, l.tree)
  api.nvim_win_set_config(S.editor_win, l.editor)
end

return M
