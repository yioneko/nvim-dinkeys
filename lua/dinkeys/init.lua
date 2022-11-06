local utils = require("dinkeys.utils")
local storage = require("dinkeys.storage")

local M = {}

local augroup_buf = vim.api.nvim_create_augroup("dinkeys", {})
local augroup_attach = vim.api.nvim_create_augroup("dinkeys_attach", {})
local augroup_write = vim.api.nvim_create_augroup("dinkeys_write", {})

local BUF_ORI_INKEY = "dinkeys_original"
local BUF_ATTACHED = "dinkeys_attached"

local function resume(co, cb)
  coroutine.resume(co)
  coroutine.resume(co, cb)
end

local function void(co)
  return (coroutine.wrap(function()
    resume(co, function() end)
  end))()
end

local detect_buf
local function detect_lang_inkeys(lang)
  return coroutine.create(function()
    local cb = coroutine.yield()
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].buftype == "" and vim.bo[bufnr].filetype == lang then
        if vim.b[bufnr][BUF_ATTACHED] and vim.b[bufnr][BUF_ORI_INKEY] then
          return cb(vim.b[bufnr][BUF_ORI_INKEY])
        else
          return cb(vim.bo[bufnr].indentkeys)
        end
      end
    end

    if not detect_buf then
      detect_buf = vim.api.nvim_create_buf(false, true)
    end

    vim.bo[detect_buf].filetype = lang
    -- TODO: 'OptionSet' event does not work
    vim.schedule(function()
      -- make sure the filetype doesn't changed
      if vim.bo[detect_buf].filetype == lang then
        cb(vim.bo[detect_buf].indentkeys)
      end
    end)
  end)
end

function M.detect(bufnr)
  local lnum, col = unpack(vim.api.nvim_win_get_cursor(0))
  local lang = utils.get_lang_at_pos(bufnr, lnum - 1, col)
  local ori_keys = vim.b[bufnr][BUF_ORI_INKEY] or vim.bo[bufnr].indentkeys

  local detecting = coroutine.create(function()
    if not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end

    local cb = coroutine.yield()
    if lang == vim.bo[bufnr].filetype then
      return cb(ori_keys)
    elseif storage.get(lang) then
      return cb(storage.get(lang))
    else
      resume(
        detect_lang_inkeys(lang),
        vim.schedule_wrap(function(keys)
          local nlnum, ncol = unpack(vim.api.nvim_win_get_cursor(0))
          -- check whether cursor has moved
          if nlnum == lnum and ncol == col then
            cb(keys)
          else
            cb(ori_keys)
          end
        end)
      )
    end
  end)

  return coroutine.create(function()
    local cb = coroutine.yield()
    resume(detecting, function(keys)
      if keys then
        storage.set(lang, keys)
      end
      cb(keys)
    end)
  end)
end

function M.detect_and_set(bufnr)
  local task = coroutine.wrap(vim.schedule_wrap(function()
    if not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end
    local detecting = M.detect(bufnr)

    resume(
      detecting,
      vim.schedule_wrap(function(keys)
        if keys then
          vim.bo[bufnr].indentkeys = keys
        end
      end)
    )
  end))
  return task()
end

local conf = {
  enable = { "markdown" },
  disable_cache = false,
  events = { "InsertEnter", "CursorMoved" },
  write_events = { "ExitPre" },
  debounce = 200,
}

local function merge_conf(base, o)
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
  vim.api.nvim_create_autocmd("Filetype", {
    group = augroup_attach,
    callback = function()
      local bufnr = vim.api.nvim_get_current_buf()
      if type(conf.enable) == "function" then
        if conf.enable(bufnr) then
          M.attach(bufnr)
        end
      elseif vim.tbl_contains(conf.enable, vim.bo[bufnr].filetype) then
        M.attach(bufnr)
      end
    end,
  })
  vim.api.nvim_create_autocmd("Filetype", {
    group = augroup_attach,
    callback = function()
      local bufnr = vim.api.nvim_get_current_buf()
      if type(conf.disable_cache) == "function" then
        if conf.disable_cache(bufnr) then
          void(M.detect(bufnr))
        end
      elseif not conf.disable_cache then
        void(M.detect(bufnr))
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

  local detect = utils.debounced_fn(M.detect_and_set, local_conf.debounce)
  detect(bufnr)

  vim.api.nvim_create_autocmd(local_conf.events, {
    group = augroup_buf,
    buffer = bufnr,
    callback = function()
      detect(bufnr)
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
