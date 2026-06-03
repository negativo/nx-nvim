local M = {}

local has_telescope, _ = pcall(require, "telescope")
if not has_telescope then
  error("nx-nvim requires telescope.nvim")
end

local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local entry_display = require("telescope.pickers.entry_display")

--- Open a split and run the selected target in a terminal buffer.
---@param entry {project: string, target: string}
---@param config NxConfig
local function run_target(entry, config)
  local parts = { config.nx_cmd, "run", entry.project .. ":" .. entry.target }
  if config.extra_args and config.extra_args ~= "" then
    parts[#parts + 1] = config.extra_args
  end
  local cmd = table.concat(parts, " ")

  if config.split == "horizontal" then
    vim.cmd((config.size and tostring(config.size) or "") .. "split")
  else
    vim.cmd((config.size and tostring(config.size) or "") .. "vsplit")
  end

  -- termopen requires an empty buffer; the split still shows the prior file.
  vim.cmd("enew")

  -- Run in the workspace root (same dir used to enumerate projects).
  local cwd = (config.cwd and config.cwd ~= "" and config.cwd) or require("nx.projects").cwd(config)
  vim.fn.termopen(cmd, { cwd = cwd })
  vim.cmd("file nx://" .. entry.project .. ":" .. entry.target)

  if config.start_insert then
    vim.cmd("startinsert")
  end
end

--- Build the telescope finder entries displayer.
local displayer = entry_display.create({
  separator = " ",
  items = {
    { width = 40 },
    { remaining = true },
  },
})

local function make_display(entry)
  return displayer({
    { entry.value.project, "TelescopeResultsIdentifier" },
    { entry.value.target, "TelescopeResultsFunction" },
  })
end

---@param config NxConfig
function M.pick(config)
  local spinner = require("nx.spinner").open()

  require("nx.projects").load(config, function(entries)
    spinner.close()
    if #entries == 0 then
      vim.notify("nx-nvim: no projects/targets found.", vim.log.levels.WARN)
      return
    end

    -- A fresh config without the one-shot refresh flag, for re-opens (<C-r>).
    local reopen_config = vim.tbl_extend("force", config, { refresh = false })

    pickers
      .new({}, {
        prompt_title = "NX Projects & Targets",
        finder = finders.new_table({
          results = entries,
          entry_maker = function(e)
            return {
              value = e,
              display = make_display,
              ordinal = e.project .. ":" .. e.target,
            }
          end,
        }),
        sorter = conf.generic_sorter({}),
        attach_mappings = function(prompt_bufnr, map)
          -- Run the current selection, optionally overriding the split direction.
          local function select(split)
            local selection = action_state.get_selected_entry()
            actions.close(prompt_bufnr)
            if selection then
              run_target(selection.value, split and vim.tbl_extend("force", config, { split = split }) or config)
            end
          end

          actions.select_default:replace(function()
            select()
          end)
          -- `-` horizontal split, `|` vertical split.
          map("i", "-", function()
            select("horizontal")
          end)
          map("n", "-", function()
            select("horizontal")
          end)
          map("i", "|", function()
            select("vertical")
          end)
          map("n", "|", function()
            select("vertical")
          end)
          -- <C-r>: bypass caches and re-enumerate from nx.
          local function refresh()
            actions.close(prompt_bufnr)
            require("nx.projects").clear_cache(config)
            M.pick(vim.tbl_extend("force", reopen_config, { refresh = true }))
          end
          map("i", "<C-r>", refresh)
          map("n", "<C-r>", refresh)
          return true
        end,
      })
      :find()
  end, function(msg)
    spinner.close()
    vim.notify("nx-nvim: " .. msg, vim.log.levels.ERROR)
  end, { force = config.refresh == true })
end

return M
