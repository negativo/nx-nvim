if vim.g.loaded_nx_nvim then
  return
end
vim.g.loaded_nx_nvim = true

vim.api.nvim_create_user_command("Nx", function(cmd)
  local opts = {}
  if cmd.args and cmd.args ~= "" then
    for _, kv in ipairs(vim.split(cmd.args, "%s+")) do
      if kv == "refresh" then
        -- `:Nx refresh` -> bypass caches and re-enumerate.
        opts.refresh = true
      else
        -- Allow `:Nx split=horizontal` style overrides.
        local k, v = kv:match("^([%w_]+)=(.+)$")
        if k then
          opts[k] = v
        end
      end
    end
  end
  require("nx").pick(opts)
end, {
  nargs = "*",
  complete = function()
    return { "refresh", "split=vertical", "split=horizontal" }
  end,
  desc = "Open the NX projects/targets picker",
})
