local has_telescope, telescope = pcall(require, "telescope")
if not has_telescope then
  error("nx-nvim requires telescope.nvim")
end

return telescope.register_extension({
  exports = {
    nx = function(opts)
      require("nx").pick(opts)
    end,
  },
})
