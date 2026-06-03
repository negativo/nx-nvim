local M = {}

local uv = vim.uv or vim.loop
local frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

--- Open a small animated loading popup in the top-right corner.
---@param msg string|nil
---@return { close: fun() }
function M.open(msg)
  msg = msg or "Loading NX projects…"

  local buf = vim.api.nvim_create_buf(false, true)
  local function line(frame)
    return " " .. frame .. " " .. msg .. " "
  end
  local width = vim.fn.strdisplaywidth(line(frames[1]))

  local win = vim.api.nvim_open_win(buf, false, {
    relative = "editor",
    anchor = "NE",
    row = 1,
    col = vim.o.columns - 1,
    width = width,
    height = 1,
    style = "minimal",
    border = "rounded",
    focusable = false,
    noautocmd = true,
    zindex = 200,
  })
  vim.wo[win].winhl = "Normal:NormalFloat,FloatBorder:FloatBorder"

  local i = 1
  local function render()
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { line(frames[i]) })
    end
  end
  render()

  local timer = uv.new_timer()
  timer:start(
    80,
    80,
    vim.schedule_wrap(function()
      i = (i % #frames) + 1
      if vim.api.nvim_win_is_valid(win) then
        render()
      end
    end)
  )

  local closed = false
  return {
    close = function()
      if closed then
        return
      end
      closed = true
      if timer then
        timer:stop()
        if not timer:is_closing() then
          timer:close()
        end
      end
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
      if vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_delete(buf, { force = true })
      end
    end,
  }
end

return M
