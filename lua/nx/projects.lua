local M = {}

--- In-memory cache of resolved entries, keyed by cwd + nx_cmd.
---@type table<string, table[]>
local cache = {}

--- Split a command string into argv (space-separated).
---@param cmd string
---@return string[]
local function argv(cmd)
  return vim.split(vim.trim(cmd), "%s+")
end

--- nx prints banners / log lines / ANSI colors to stdout alongside `--json`
--- output. Strip color codes and slice from the first `open` char to the last
--- `close` char, then JSON-decode that.
---@param s string
---@param open string  -- "[" for arrays, "{" for objects
---@param close string -- "]" or "}"
---@return boolean ok, any value
local function decode_loose(s, open, close)
  s = (s or ""):gsub("\27%[[0-9;]*m", "")
  local i = s:find(open, 1, true)
  local j
  for k = #s, 1, -1 do
    if s:sub(k, k) == close then
      j = k
      break
    end
  end
  if not i or not j or j < i then
    return false, nil
  end
  return pcall(vim.json.decode, s:sub(i, j))
end

--- Walk up from `start` looking for an nx workspace root (nx.json).
---@param start string
---@return string|nil
local function find_root(start)
  local found = vim.fs.find({ "nx.json" }, { upward = true, path = start, type = "file" })[1]
  if found then
    return vim.fs.dirname(found)
  end
  return nil
end

--- Resolve the workspace cwd: explicit config.cwd, else search up from the
--- current buffer / Neovim cwd for nx.json.
---@param config NxConfig
---@return string
local function resolve_cwd(config)
  if config.cwd and config.cwd ~= "" then
    return config.cwd
  end
  local buf = vim.api.nvim_buf_get_name(0)
  local start = (buf ~= "" and vim.fs.dirname(buf)) or vim.fn.getcwd()
  return find_root(start) or vim.fn.getcwd()
end

--- Public: resolve the workspace cwd for a given config.
---@param config NxConfig
---@return string
function M.cwd(config)
  return resolve_cwd(config)
end

--- Drop cached entries (all, or just for one resolved cwd+cmd key).
---@param config NxConfig|nil
function M.clear_cache(config)
  if config then
    cache[resolve_cwd(config) .. "\0" .. config.nx_cmd] = nil
  else
    cache = {}
  end
end

--- Build entry list from a graph nodes table.
---@param nodes table
---@return {project: string, target: string, executor: string|nil}[]
local function entries_from_nodes(nodes)
  local entries = {}
  for name, node in pairs(nodes) do
    local targets = node.data and node.data.targets or {}
    for tname, tdata in pairs(targets) do
      entries[#entries + 1] = {
        project = name,
        target = tname,
        executor = type(tdata) == "table" and tdata.executor or nil,
      }
    end
  end
  return entries
end

local function sort_entries(entries)
  table.sort(entries, function(a, b)
    if a.project == b.project then
      return a.target < b.target
    end
    return a.project < b.project
  end)
  return entries
end

--- Extract graph nodes from a decoded `nx graph` payload (file or cache shape).
---@param data any
---@return table|nil
local function nodes_of(data)
  if type(data) ~= "table" then
    return nil
  end
  local nodes = (data.graph and data.graph.nodes) or data.nodes
  return type(nodes) == "table" and nodes or nil
end

--- Fast path: nx persists the project graph on disk. Read it directly to avoid
--- spawning node at all. Returns nil if no valid cache file is present.
---@param cwd string
---@return table[]|nil
local function load_from_disk(cwd)
  local candidates = {
    "/.nx/workspace-data/project-graph.json",
    "/.nx/cache/project-graph.json",
    "/node_modules/.cache/nx/project-graph.json",
  }
  for _, rel in ipairs(candidates) do
    local fd = io.open(cwd .. rel, "r")
    if fd then
      local raw = fd:read("*a")
      fd:close()
      local ok, data = pcall(vim.json.decode, raw)
      local nodes = ok and nodes_of(data)
      if nodes and next(nodes) then
        return sort_entries(entries_from_nodes(nodes))
      end
    end
  end
  return nil
end

--- Fallback: `nx show projects --json` then `nx show project <p> --json` for
--- each (capped concurrency), reading everything from stdout. Slower but robust.
---@param config NxConfig
---@param cwd string
---@param on_done fun(entries: table[])
---@param on_error fun(msg: string)
local function load_via_show(config, cwd, on_done, on_error)
  local list_cmd = argv(config.nx_cmd)
  vim.list_extend(list_cmd, { "show", "projects", "--json" })

  vim.system(list_cmd, { text = true, cwd = cwd }, function(obj)
    vim.schedule(function()
      if obj.code ~= 0 then
        on_error(("nx show projects failed (exit %d):\n%s"):format(obj.code, obj.stderr or obj.stdout or ""))
        return
      end
      local ok, names = decode_loose(obj.stdout or "", "[", "]")
      if not ok or type(names) ~= "table" then
        on_error("Failed to parse `nx show projects --json`:\n" .. (obj.stdout or ""))
        return
      end
      if #names == 0 then
        on_done({})
        return
      end

      local entries = {}
      local limit = math.max(1, config.max_concurrency or 10)
      local idx, active, pending = 0, 0, #names

      local function pump()
        while active < limit and idx < #names do
          idx = idx + 1
          active = active + 1
          local name = names[idx]
          local pc = argv(config.nx_cmd)
          vim.list_extend(pc, { "show", "project", name, "--json" })
          vim.system(pc, { text = true, cwd = cwd }, function(po)
            vim.schedule(function()
              if po.code == 0 then
                local pok, pdata = decode_loose(po.stdout or "", "{", "}")
                if pok and type(pdata) == "table" and type(pdata.targets) == "table" then
                  for tname, tdata in pairs(pdata.targets) do
                    entries[#entries + 1] = {
                      project = name,
                      target = tname,
                      executor = type(tdata) == "table" and tdata.executor or nil,
                    }
                  end
                end
              end
              active = active - 1
              pending = pending - 1
              if pending == 0 then
                on_done(sort_entries(entries))
              else
                pump()
              end
            end)
          end)
        end
      end

      pump()
    end)
  end)
end

--- Spawn `nx graph --file=<tmp>` and parse the result; fall back to show.
---@param config NxConfig
---@param cwd string
---@param on_done fun(entries: table[])
---@param on_error fun(msg: string)
local function load_via_graph(config, cwd, on_done, on_error)
  local tmp = vim.fn.tempname() .. ".json"
  local cmd = argv(config.nx_cmd)
  vim.list_extend(cmd, { "graph", "--file=" .. tmp })

  vim.system(cmd, { text = true, cwd = cwd }, function(obj)
    vim.schedule(function()
      local fd = obj.code == 0 and io.open(tmp, "r") or nil
      if not fd then
        load_via_show(config, cwd, on_done, on_error)
        return
      end
      local raw = fd:read("*a")
      fd:close()
      os.remove(tmp)

      local ok, data = pcall(vim.json.decode, raw)
      local nodes = ok and nodes_of(data)
      if not nodes then
        load_via_show(config, cwd, on_done, on_error)
        return
      end
      on_done(sort_entries(entries_from_nodes(nodes)))
    end)
  end)
end

--- Load all NX project/target pairs.
--- Order: in-memory cache -> on-disk graph -> `nx graph` spawn -> `nx show`.
--- Requires Neovim >= 0.10 (vim.system).
---@param config NxConfig
---@param on_done fun(entries: {project: string, target: string, executor: string|nil}[])
---@param on_error fun(msg: string)
---@param opts {force: boolean}|nil  -- force bypasses both caches and re-spawns nx graph
function M.load(config, on_done, on_error, opts)
  if not vim.system then
    on_error("nx-nvim requires Neovim >= 0.10 (vim.system).")
    return
  end

  opts = opts or {}
  local cwd = resolve_cwd(config)
  local key = cwd .. "\0" .. config.nx_cmd

  local function finish(entries)
    cache[key] = entries
    on_done(entries)
  end

  if not opts.force then
    if config.cache ~= false and cache[key] then
      on_done(cache[key])
      return
    end
    if config.use_cache_file ~= false then
      local entries = load_from_disk(cwd)
      if entries then
        finish(entries)
        return
      end
    end
  end

  load_via_graph(config, cwd, finish, on_error)
end

return M
