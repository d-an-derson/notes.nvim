local uv = vim.uv

local M = {}

---@param path string
---@return boolean
function M.exists(path)
  return uv.fs_stat(path) ~= nil
end

---@param path string
---@return boolean
function M.is_dir(path)
  local stat = uv.fs_stat(path)
  return stat ~= nil and stat.type == "directory"
end

---@class notes.Entry
---@field name string
---@field path string
---@field type "file"|"directory"
---@field depth? integer

--- List a directory's entries, folders first, then alphabetically.
---@param dir string
---@param show_hidden boolean
---@return notes.Entry[]
function M.list(dir, show_hidden)
  local entries = {}
  for name, type in vim.fs.dir(dir) do
    if show_hidden or name:sub(1, 1) ~= "." then
      local path = dir .. "/" .. name
      if type == "link" then
        local stat = uv.fs_stat(path)
        type = stat and stat.type or "file"
      end
      entries[#entries + 1] = {
        name = name,
        path = path,
        type = type == "directory" and "directory" or "file",
      }
    end
  end
  table.sort(entries, function(a, b)
    if a.type ~= b.type then
      return a.type == "directory"
    end
    return a.name:lower() < b.name:lower()
  end)
  return entries
end

--- Create a directory and its parents. Succeeds if it already exists.
---@param path string
---@return boolean ok, string? err
function M.mkdir(path)
  if M.is_dir(path) then
    return true
  end
  local ok, err = pcall(vim.fn.mkdir, path, "p")
  if not ok then
    return false, err
  end
  return true
end

---@param path string
---@return boolean ok, string? err
function M.create_dir(path)
  if M.exists(path) then
    return false, "already exists"
  end
  return M.mkdir(path)
end

---@param path string
---@return boolean ok, string? err
function M.create_file(path)
  if M.exists(path) then
    return false, "already exists"
  end
  local ok, err = M.mkdir(vim.fs.dirname(path))
  if not ok then
    return false, err
  end
  local fd, open_err = io.open(path, "w")
  if not fd then
    return false, open_err
  end
  fd:close()
  return true
end

---@param path string
---@return boolean ok, string? err
function M.delete(path)
  local flags = M.is_dir(path) and "rf" or ""
  if vim.fn.delete(path, flags) ~= 0 then
    return false, "could not delete"
  end
  return true
end

---@param from string
---@param to string
---@return boolean ok, string? err
function M.rename(from, to)
  if M.exists(to) then
    return false, "already exists"
  end
  local ok, err = M.mkdir(vim.fs.dirname(to))
  if not ok then
    return false, err
  end
  local renamed, rename_err = uv.fs_rename(from, to)
  if not renamed then
    return false, rename_err
  end
  return true
end

return M
