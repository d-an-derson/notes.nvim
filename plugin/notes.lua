if vim.g.loaded_notes then
  return
end
vim.g.loaded_notes = 1

local subcommands = { "toggle", "open", "close" }

vim.api.nvim_create_user_command("Notes", function(cmd)
  local sub = cmd.fargs[1] or "toggle"
  if not vim.tbl_contains(subcommands, sub) then
    vim.notify("Notes: unknown subcommand '" .. sub .. "'", vim.log.levels.ERROR)
    return
  end
  require("notes")[sub]()
end, {
  nargs = "?",
  complete = function(arg_lead)
    return vim.tbl_filter(function(s)
      return vim.startswith(s, arg_lead)
    end, subcommands)
  end,
  desc = "Toggle the notes popup",
})
