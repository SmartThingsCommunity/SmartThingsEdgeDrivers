--- Table with metamethods to track the number of items inside of a table including KV pairs.
local KVCounter = {}

-- Helper function to implement next on KVCounter.
-- There is no metamethod to do this but is useful for getting a value without knowing the keys.
local function kv_counter_next(t, index)
  local mt = getmetatable(t)
  return next(mt.inner, index)
end

local function kv_counter_index(t, k)
  local mt = getmetatable(t)

  if k == "next" then
    return kv_counter_next
  end

  return mt.inner[k]
end

local function kv_counter_newindex(t, k, v)
  assert(k ~= "next", "next is an unallowed key in KVCounter")

  local mt = getmetatable(t)
  local existed = mt.inner[k] ~= nil
  if existed and v == nil then
    mt.count = mt.count - 1
  elseif not existed and v ~= nil then
    mt.count = mt.count + 1
  end
  mt.inner[k] = v
end

local function kv_counter_pairs(t)
  local mt = getmetatable(t)
  return pairs(mt.inner)
end

local function kv_counter_len(t)
  local mt = getmetatable(t)
  return mt.count
end

local function kv_counter_factory()
  local mt = {
    -- Avoid blowing up lua closures by defining these outside of the function.
    __index = kv_counter_index,
    __newindex = kv_counter_newindex,
    __pairs = kv_counter_pairs,
    __len = kv_counter_len,
    count = 0,
    inner = {}
  }
  return setmetatable({}, mt)
end

setmetatable(KVCounter, {
  __call = kv_counter_factory
})

return KVCounter
