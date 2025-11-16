local util = {}

function util.tablefind(t, path)
  local pathelements = string.gmatch(path, "([^.]+)%.?")
  local item = t

  for element in pathelements do
    if type(item) ~= "table" then item = nil; break end

    item = item[element]
  end

  return item
end

--- This alternate determination of MAC addrs being equal is
--- needed since wemo devices usually have a MAC on the network
--- one greater than what is reported by the device. Migrated
--- devices use the real network MAC, and devices joined to the
--- driver use the device reported MAC.
function util.mac_equal(m1, m2)
  local v1 = tonumber(m1, 16)
  local v2 = tonumber(m2, 16)
  if v1 == nil or v2 == nil then return false end
  return math.abs(v1 - v2) <= 1
end

return util
