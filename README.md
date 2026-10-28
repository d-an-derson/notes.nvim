# notes

A Neovim note-taking plugin. `:Notes` opens a floating popup over the editor with a
folder tree on the left and the selected note on the right. You can browse, create,
edit, save, rename/move and delete notes and folders without leaving it.

Notes are stored in one system-wide directory, so the same notes open no matter what
Neovim's cwd is.

Requires Neovim 0.10+.

## Install

lazy.nvim:

```lua
{
  'd-an-derson/notes.nvim',
  cmd = "Notes",
  keys = { { "<leader>n", "<cmd>Notes<cr>", desc = "Toggle notes" } },
  opts = {
    dir = "~/notes",
  },
}
```

## Commands

| Command          | Action                 |
| ---------------- | ---------------------- |
| `:Notes`         | Toggle the popup       |
| `:Notes open`    | Open (or focus) it     |
| `:Notes close`   | Close it               |

## Keys

Tree pane:

| Key              | Action                                                    |
| ---------------- | --------------------------------------------------------- |
| `<CR>` `l` `o`   | Open note / toggle folder                                 |
| `h`              | Collapse folder (or the parent folder of a note)          |
| `a`              | New note in the folder under the cursor. End the name with `/` to make a folder. Nested paths such as `work/ideas/x` work too. |
| `d`              | Delete note or folder (asks first)                        |
| `r`              | Rename / move (edit the path relative to the notes root)  |
| `R`              | Refresh                                                   |
| `<Tab>`          | Focus the editor pane                                     |
| `q`              | Close                                                     |
| `?`              | Show help                                                 |

Editor pane: this is a normal buffer for the note file, so `:w` and all your usual
editing work. In addition:

| Key              | Action          |
| ---------------- | --------------- |
| `<C-s>`          | Save (normal and insert mode) |
| `<S-Tab>`        | Focus the tree  |

With `autosave` on (the default), the open note is saved when you switch notes or close
the popup. The popup also closes when focus moves to a regular window.

## Configuration

Defaults:

```lua
require("notes").setup({
  dir = vim.fn.stdpath("data") .. "/notes", -- use an absolute or ~ path
  extension = ".md",      -- added to new notes without an extension; false to disable
  autosave = true,
  show_hidden = false,
  width = 0.8,            -- <= 1: fraction of the editor, > 1: columns
  height = 0.8,           -- <= 1: fraction of the editor, > 1: lines
  tree_width = 0.25,      -- <= 1: fraction of the popup, > 1: columns
  border = "rounded",
  editor_win_opts = {
    wrap = true,
    linebreak = true,
    number = false,
    relativenumber = false,
    signcolumn = "no",
    foldcolumn = "0",
  },
  keymaps = {             -- any entry may be a string, a list, or false
    open = { "<CR>", "l", "o" },
    collapse = "h",
    create = "a",
    delete = "d",
    rename = "r",
    refresh = "R",
    help = "?",
    close = "q",
    focus_editor = "<Tab>",
    focus_tree = "<S-Tab>",
    save = "<C-s>",
  },
})
```
