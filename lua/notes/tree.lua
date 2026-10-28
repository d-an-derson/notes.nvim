local fs = require("notes.fs")

local M = {}

--- Expanded folders, keyed by absolute path. Persists while Neovim runs.
---@type table<string, true>
M.expanded = {}

---@param path string
---@param dir string
---@return boolean
function M.is_under(path, dir)
  return path == dir or vim.startswith(path, dir .. "/")
end

--- Expand every folder between `root` and `path` so `path` is visible.
---@param root string
---@param path string
function M.reveal(root, path)
  for dir in vim.fs.parents(path) do
    if not M.is_under(dir, root) or dir == root then
      break
    end
    M.expanded[dir] = true
  end
end

--- Forget expansion state for `dir` and everything below it, optionally moving it to `new_dir`.
---@param dir string
---@param new_dir? string
function M.move_expanded(dir, new_dir)
  for path in pairs(vim.deepcopy(M.expanded)) do
    if M.is_under(path, dir) then
      M.expanded[path] = nil
      if new_dir then
        M.expanded[new_dir .. path:sub(#dir + 1)] = true
      end
    end
  end
end

---@param root string
---@param show_hidden boolean
---@return notes.Entry[]
function M.build(root, show_hidden)
  local nodes = {}
  local function walk(dir, depth)
    for _, entry in ipairs(fs.list(dir, show_hidden)) do
      entry.depth = depth
      nodes[#nodes + 1] = entry
      if entry.type == "directory" and M.expanded[entry.path] then
        walk(entry.path, depth + 1)
      end
    end
  end
  walk(root, 0)
  return nodes
end

---@param buf integer
---@param ns integer
---@param nodes notes.Entry[]
---@param current? string Path of the note open in the editor pane.
function M.render(buf, ns, nodes, current)
  local lines, hls = {}, {}
  for i, node in ipairs(nodes) do
    local indent = string.rep("  ", node.depth)
    if node.type == "directory" then
      local icon = M.expanded[node.path] and "▾ " or "▸ "
      lines[i] = indent .. icon .. node.name .. "/"
      hls[#hls + 1] = { i - 1, #indent, "Directory" }
    else
      lines[i] = indent .. "  " .. node.name
      if node.path == current then
        hls[#hls + 1] = { i - 1, #indent, "Special" }
      end
    end
  end
  if #nodes == 0 then
    lines = { "  (no notes yet)" }
    hls = { { 0, 0, "Comment" } }
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].modified = false

  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, hl in ipairs(hls) do
    local row, col, group = hl[1], hl[2], hl[3]
    vim.api.nvim_buf_set_extmark(buf, ns, row, col, {
      end_row = row,
      end_col = #lines[row + 1],
      hl_group = group,
    })
  end
end

return M
