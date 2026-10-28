local M = {}

---@param opts? notes.Config
function M.setup(opts)
  require("notes.config").setup(opts)
end

function M.open()
  require("notes.ui").open()
end

function M.close()
  require("notes.ui").close()
end

function M.toggle()
  require("notes.ui").toggle()
end

return M
