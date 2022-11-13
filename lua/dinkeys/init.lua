local utils = require("dinkeys.utils")
local storage = require("dinkeys.storage")

local M = {}

local augroup_buf = vim.api.nvim_create_augroup("dinkeys", {})
local augroup_attach = vim.api.nvim_create_augroup("dinkeys_attach", {})
local augroup_write = vim.api.nvim_create_augroup("dinkeys_write", {})

local BUF_ORI_INKEY = "dinkeys_original"
local BUF_ATTACHED = "dinkeys_attached"

local function nr(winnr)
  winnr = winnr or vim.api.nvim_get_current_win()
  local bufnr = vim.api.nvim_win_get_buf(winnr)
  return winnr, bufnr
end

local detect_buf
local function detect_lang_inkeys(lang, cb)
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].buftype == "" and vim.bo[bufnr].filetype == lang then
      if vim.b[bufnr][BUF_ATTACHED] and vim.b[bufnr][BUF_ORI_INKEY] then
        return cb(vim.b[bufnr][BUF_ORI_INKEY])
      else
        return cb(vim.bo[bufnr].indentkeys)
      end
    end
  end

  if not detect_buf or not vim.api.nvim_buf_is_valid(detect_buf) then
    detect_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[detect_buf].syntax = ""
  end

  vim.bo[detect_buf].filetype = lang
  -- TODO: 'OptionSet' event does not work
  vim.schedule(function()
    -- make sure the filetype doesn't changed
    if vim.bo[detect_buf].filetype == lang then
      cb(vim.bo[detect_buf].indentkeys)
    else
      cb()
    end
  end)
end

function M.detect(winnr, cb)
  local winnr, bufnr = nr(winnr)
  local lnum, col = unpack(vim.api.nvim_win_get_cursor(winnr))
  local lang = utils.get_lang_at_pos(bufnr, lnum - 1, col)
  local ori_keys = vim.b[bufnr][BUF_ORI_INKEY] or vim.bo[bufnr].indentkeys

  local function checked_cb(keys)
    if cb then
      return cb(keys)
    end
  end

  local cb_with_set = vim.schedule_wrap(function(keys)
    local nlnum, ncol = unpack(vim.api.nvim_win_get_cursor(winnr))
    -- check whether cursor has moved
    if keys and nlnum == lnum and ncol == col then
      storage.set(lang, keys)
      checked_cb(keys)
    else
      checked_cb()
    end
  end)

  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  if lang == vim.bo[bufnr].filetype then
    return checked_cb(ori_keys)
  elseif storage.get(lang) then
    return checked_cb(storage.get(lang))
  else
    detect_lang_inkeys(lang, cb_with_set)
  end
end

function M.detect_and_apply(winnr)
  local winnr, bufnr = nr(winnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  M.detect(winnr, function(keys)
    if keys then
      vim.bo[bufnr].indentkeys = keys
    end
  end)
end

local conf = {
  enable = { "markdown" },
  disable_cache = false,
  events = { "InsertEnter" },
  write_events = { "ExitPre" },
  debounce = 200,
}

local function merge_conf(base, o)
  if o.enable ~= nil then
    base.enable = o.enable
  end
  if o.disable_cache ~= nil then
    base.disable_cache = o.disable_cache
  end
  if o.events then
    base.events = o.events
  end
  if o.write_events then
    base.write_events = o.write_events
  end
  if o.debounce then
    base.debounce = o.debounce
  end
end

function M.setup(o)
  merge_conf(conf, o or {})

  vim.schedule(storage.read)

  vim.api.nvim_clear_autocmds({ group = augroup_write })
  vim.api.nvim_create_autocmd(conf.write_events, {
    group = augroup_write,
    callback = storage.write,
  })

  vim.api.nvim_clear_autocmds({ group = augroup_attach })
  vim.api.nvim_create_autocmd("FileType", {
    group = augroup_attach,
    callback = function(args)
      local bufnr = args.buf
      if type(conf.enable) == "function" then
        if conf.enable(bufnr) then
          M.attach(bufnr)
        end
      elseif vim.tbl_contains(conf.enable, vim.bo[bufnr].filetype) then
        M.attach(bufnr)
      end
    end,
  })
  vim.api.nvim_create_autocmd("FileType", {
    group = augroup_attach,
    callback = function(args)
      local bufnr = args.buf
      local winnr = utils.find_win_for_buf(bufnr)
      if winnr == nil then
        return
      end
      if type(conf.disable_cache) == "function" then
        if conf.disable_cache(bufnr) then
          M.detect(winnr)
        end
      elseif not conf.disable_cache then
        M.detect(winnr)
      end
    end,
  })
end

function M.attach(bufnr, opts)
  if vim.b[bufnr][BUF_ATTACHED] then
    return
  end
  vim.b[bufnr][BUF_ATTACHED] = true
  vim.b[bufnr][BUF_ORI_INKEY] = vim.bo[bufnr].indentkeys

  local local_conf = vim.deepcopy(conf)
  merge_conf(local_conf, opts or {})

  if local_conf.events == {} then
    return
  end

  local detect = utils.debounced_fn(M.detect_and_apply, local_conf.debounce)

  vim.api.nvim_create_autocmd(local_conf.events, {
    group = augroup_buf,
    buffer = bufnr,
    callback = function()
      detect(vim.api.nvim_get_current_win())
    end,
  })
end

function M.detach(bufnr)
  vim.b[bufnr][BUF_ATTACHED] = nil
  vim.bo[bufnr].indentkeys = vim.b[bufnr][BUF_ORI_INKEY]
  vim.b[bufnr][BUF_ORI_INKEY] = nil

  vim.api.nvim_clear_autocmds({
    group = augroup_buf,
    buffer = bufnr,
  })
end

return M
