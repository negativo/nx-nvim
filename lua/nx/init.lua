local M = {}

---@class NxConfig
---@field nx_cmd string Command used to invoke nx (e.g. "nx" or "npx nx").
---@field cwd string|nil Workspace root. Defaults to current working directory.
---@field split "vertical"|"horizontal" Split direction for the target terminal.
---@field size number|nil Optional split size (columns for vertical, rows for horizontal).
---@field extra_args string Extra args appended to the `nx run` invocation.
---@field start_insert boolean Enter terminal-insert mode after launching.
---@field keymap string|false Normal-mode mapping that opens the picker. Set false to disable.
---@field cache boolean Reuse the in-memory project/target list across opens.
---@field use_cache_file boolean Read nx's on-disk project graph (skips spawning nx) when present.
---@field max_concurrency number Max parallel `nx show project` calls in the fallback path.
local defaults = {
	nx_cmd = "nx",
	cwd = nil,
	split = "vertical",
	size = nil,
	extra_args = "",
	start_insert = false,
	keymap = "<leader>nx",
	cache = true,
	use_cache_file = true,
	max_concurrency = 10,
}

---@type NxConfig
M.config = vim.deepcopy(defaults)

---@param opts NxConfig|nil
function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})

	if M.config.keymap then
		vim.keymap.set("n", M.config.keymap, function()
			M.pick()
		end, { desc = "NX projects & targets" })
	end
end

--- Open the telescope picker of NX projects/targets.
---@param opts table|nil Per-call overrides merged onto M.config.
function M.pick(opts)
	require("nx.picker").pick(vim.tbl_deep_extend("force", M.config, opts or {}))
end

return M
