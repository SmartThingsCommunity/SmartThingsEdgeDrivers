local net_url = require "net.url"

local util = {}

util.force_url_table = function(url)
  if type(url) ~= "table" then url = net_url.parse(url) end

  if not url.port then
    if url.scheme == "http" then
      url.port = 80
    elseif url.scheme == "https" then
      url.port = 443
    end
  end

  return url
end

---@param tbl table the table to make read only
---@return table read_only read-only version of the table
util.read_only = function(tbl)
  if type(tbl) == "table" then
    local proxy = {}
    local mt = { -- create metatable
      __index = tbl,
      __newindex = function(t, k, v) error("attempt to update a read-only table", 2) end,
    }
    setmetatable(proxy, mt)
    return proxy
  else
    return tbl
  end
end

return util
