local M = {}

function M.get_parser(bufnr, lang)
  local ok, ts_parser = pcall(require, "nvim-treesitter.parsers")
  if ok then
    return ts_parser.get_parser(bufnr, lang)
  end
  return vim.treesitter.get_parser(bufnr, lang)
end

function M.get_lang_at_pos(bufnr, lnum, col)
  local ok, parser = pcall(M.get_parser, bufnr)
  if not ok or not parser then
    return
  end
  local lang_tree = parser:language_for_range({ lnum, col, lnum, col })
  if lang_tree then
    return lang_tree:lang()
  end

  return vim.bo[bufnr].filetype
end

function M.debounced_fn(fn, ms)
  local timer = vim.loop.new_timer()
  return function(...)
    local args = { ... }
    timer:stop()
    timer:start(
      ms,
      0,
      vim.schedule_wrap(function()
        fn(unpack(args))
      end)
    )
  end
end

return M
