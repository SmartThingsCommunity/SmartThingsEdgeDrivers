local net_helpers = require "test.helpers.net"
---@class test.helpers.hue_bridge
local m = {}

---Generate a random Hue Application Key/"username"
---@param len number? Number between 10 and 40 for the desired length of the application key. Selected randomly from the range if omitted.
---@return string key the hue application key
function m.random_hue_bridge_key(len)
  local charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890-_"
  len = (type(len) == "number" and len > 10 and len) or math.random(10, 40)

  local key = ""
  for i = 1, len do
    local idx = math.random(1, #charset)
    local random_char = charset:sub(idx, idx)
    key = key .. random_char
  end
  return key
end

---@class MockHueBridgeInfo
--- @field public name string?
--- @field public mac_addr string?
--- @field public datastoreversion string?
--- @field public swversion string?
--- @field public apiversion string?
--- @field public factorynew boolean?
--- @field public replacesbridgeid string?
--- @field public modelid string?
--- @field public starterkitid string?
--- @field public ip string?

---Generate partiall random Hue Bridge Info
---@param override_info MockHueBridgeInfo? Optional, overrides for the generated fields; can be a partial table.
---@return HueBridgeInfo bridge_info
function m.random_bridge_info(override_info)
  override_info = override_info or {}
  local mac_addr = override_info.mac_addr or net_helpers.random_mac_address(':', false)

  return {
    name = override_info.name or "Philips Hue",
    datastoreversion = override_info.datastoreversion or "166",
    swversion = override_info.swversion or "1963089030",
    apiversion = override_info.apiversion or "1.63.0",
    mac = mac_addr,
    bridge_id = mac_addr:upper():gsub(':', ''),
    factorynew = override_info.factorynew or false,
    replacesbridgeid = override_info.replacesbridgeid or false,
    modelid = override_info.modelid or "BSB002",
    starterkitid = override_info.starterkitid or "",
    ip = override_info.ip or net_helpers.random_private_ip_address()
  }
end

---Asserts values in the expected MockHueBridgeInfo against the actual
---HueBridgeInfo returned from the REST API.
---@param expected HueBridgeInfo
---@param actual HueBridgeInfo
function m.assert_bridge_info(expected, actual)
  for k, v in pairs(expected) do
    local err_str = string.format(
      "Expected bridge info [%s] with value [%s], received [%s]",
      k, v, actual[k]
    )
    assert(v == actual[k], err_str)
  end
end

return m
