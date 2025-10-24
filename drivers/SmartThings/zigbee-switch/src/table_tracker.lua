--- This function allows for tracking table accesses for a table

-- create private index to be used to access the original table
-- from the proxy
local index = {}

-- metatable for the proxy tracking and printing functionality
local mt = {
  __index = function (t,k)
    -- print("*access to element " .. tostring(k))
    t.__reads[k] = true
    return t[index][k]   -- access the original table
  end,

  __newindex = function (t,k,v)
    -- print("*update of element " .. tostring(k) ..
    --                      " to " .. tostring(v))
    t.__writes[k] = true
    t[index][k] = v   -- update original table
  end,
}

local track = function(t)
  local proxy = {
    __reads = {},
    __writes = {},
  }
  proxy[index] = t

  function proxy:accesses()
    local res = {
      no_access = {}
    }
    for k, v in pairs(self.__reads) do
      res[k] = {}
      table.insert(res[k], "read")
    end
    for k, v in pairs(self.__writes) do
      res[k] = res[k] or {}
      table.insert(res[k], "write")
    end
    for k, v in pairs(self[index]) do
      if res[k] == nil then
        table.insert(res.no_access, k)
      end
    end
    return res
  end

  setmetatable(proxy, mt)
  return proxy
end

return track