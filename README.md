# nx-nvim
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Neovim](https://img.shields.io/badge/neovim-%3E%3D0.10-blue)](https://neovim.io)

A [Neovim](https://neovim.io) + [Telescope](https://github.com/nvim-telescope/telescope.nvim)
plugin that lists every [NX](https://nx.dev) project/target in your workspace and
runs the selected one in a split terminal.

> ⚠️ **Early development.** This plugin has only been tested on my own
> setup (specific Neovim, Telescope, nx, and package-manager versions). It may
> break on other configurations. If something doesn't work, please
> [open an issue](../../issues) — bug reports and setup details are very welcome.

## Why

I built this because the existing
[Equilibris/nx.nvim](https://github.com/Equilibris/nx.nvim) plugin started
crashing and would no longer load in my current project. `nx-nvim` is a smaller,
focused alternative: enumerate projects/targets, pick one, run it in a split.

That plugin is more mature and feature-rich — if it works for you, keep using it.
`nx-nvim` exists for cases like mine where it doesn't.

## Requirements

- Neovim >= 0.10 (uses `vim.system`)
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
- `nx` available on `PATH` (or set `nx_cmd = "npx nx"`)

## Install

### lazy.nvim

```lua
{
  "negativo/nx-nvim",
  dependencies = { "nvim-telescope/telescope.nvim" },
  config = function()
    require("nx").setup({
      -- defaults shown:
      nx_cmd = "nx",          -- or "npx nx"
      cwd = nil,              -- workspace root; defaults to Neovim's cwd
      split = "vertical",     -- "vertical" | "horizontal"
      size = nil,             -- split size (cols/rows)
      extra_args = "",        -- appended to `nx run <project>:<target>`
      start_insert = false,   -- enter terminal-insert mode after launch
      keymap = "<leader>nx",  -- normal-mode mapping; set false to disable
      cache = true,           -- reuse the list across opens (in-memory)
      use_cache_file = true,  -- read nx's on-disk graph, skipping the nx spawn
      max_concurrency = 10,   -- parallel `nx show project` calls in fallback
    })
    require("telescope").load_extension("nx")
  end,
}
```

## Usage

- `:Telescope nx`
- `:Nx` — same picker; accepts inline overrides, e.g. `:Nx split=horizontal`
- `require("nx").pick()` — programmatic, accepts a per-call options table

Select an entry → a split opens and `nx run <project>:<target>` runs in a
terminal buffer there.

### Picker mappings

| Key     | Action                                            |
| ------- | ------------------------------------------------- |
| `<CR>`  | Run in the configured `split` direction (default) |
| `-`     | Run in a **horizontal** split                     |
| `\|`    | Run in a **vertical** split                       |
| `<C-r>` | Refresh — bypass caches and re-enumerate from nx  |

> Note: `-` and `\|` are mapped in insert mode too, so they cannot be typed in
> the search prompt. If your project names contain `-`, filter by the rest of
> the name (fuzzy match), or override these mappings.

### Keymap

`<leader>nx` is bound by default in `setup()`. Change it with `keymap = "<key>"`,
or disable with `keymap = false` and bind your own:

```lua
vim.keymap.set("n", "<leader>nx", "<cmd>Telescope nx<cr>", { desc = "NX targets" })
```

## How it works

The list is resolved in fastest-first order:

1. **In-memory cache** — instant on re-open (`cache`).
2. **On-disk graph** — reads nx's own `.nx/workspace-data/project-graph.json`
   (or `.nx/cache/`, `node_modules/.cache/nx/`), skipping the nx spawn entirely
   (`use_cache_file`).
3. **`nx graph --file`** — one spawn; parses `graph.nodes[*].data.targets`.
4. **`nx show projects` + `nx show project`** — fallback, capped at
   `max_concurrency` parallel calls.

Selecting an entry opens a split and launches the target via `vim.fn.termopen`
in the workspace root.

### Refreshing

Caches are bypassed and nx is re-queried with:

- `<C-r>` inside the picker (see [Picker mappings](#picker-mappings))
- `:Nx refresh`
- `require("nx.projects").clear_cache()` (programmatic)
