local M = {}

local cache_file = "dinkeys.json"
local keys = {}

function M.get(lang)
  return keys[lang]
end

function M.set(ft, key)
  keys[ft] = key
end

function M.add(ft, key)
  if not keys[ft] then
    keys[ft] = key
  else
    keys[ft] = keys[ft] .. "," .. key
  end
end

function M.read()
  local file = vim.fn.findfile(cache_file, vim.fn.stdpath("cache"))
  local f = io.open(file, "r")
  if f then
    local content = f:read("*a")
    f:close()
    local ok, cached_keys = pcall(vim.json.decode, content)
    if ok then
      keys = cached_keys
    else
      vim.loop.fs_unlink(file, function() end)
    end
  end
end

function M.write()
  local f = io.open(vim.fn.stdpath("cache") .. "/" .. cache_file, "w")
  if f then
    local raw_content = vim.json.encode(keys)
    f:write(raw_content)
    f:close()
  end
end

return M
