---@class spec_utils
local test_helpers = {}

local private_cidr_strings = {
  ["192.168.0.0/16"] = true,
  ["172.16.0.0/12"] = true,
  ["10.0.0.0/8"] = true
}

---Generate a random IP address for the given CIDR string
---@param cidr_string string? Optional, must be a CIDR string identifying one of the three private network spaces. Defaults to "192.168.0.0/16"
---@return string ip a random IP address.
function test_helpers.random_private_ip_address(cidr_string)
  cidr_string = cidr_string or "192.168.0.0/16"

  local valid_strings = {}
  for k, _ in pairs(private_cidr_strings) do
    table.insert(valid_strings, k)
  end

  assert(
    private_cidr_strings[cidr_string],
    "CIDR string is not a valid private network string, must be one of %s, %s, or %s",
    table.unpack(valid_strings)
  )
  if cidr_string == "172.16.0.0/12" then
    return string.format(
      "172.%d.%d.%d",
      math.random(16, 31),
      math.random(255),
      math.random(255)
    )
  end

  if cidr_string == "10.0.0.1/8" then
    return string.format(
      "10.%d.%d.%d",
      math.random(255),
      math.random(255),
      math.random(255)
    )
  end

  return string.format(
    "192.168.%d.%d",
    math.random(255),
    math.random(255)
  )
end

---Generate a random MAC address
---@param separator string? Optional, separator to use in between MAC address segments. Can be '.', ':', '-', or ''. Defaults to ':'
---@param cisco_format boolean? if true, use 3 segments of 4 hex characters instead of 6 segments of 2 characters.
---@return string mac Random MAC address.
function test_helpers.random_mac_address(separator, cisco_format)
  separator = separator or ':'
  assert(
    separator == '.' or
    separator == ':' or
    separator == '-' or
    separator == '',
    "Invalid separator for random mac addr: " .. tostring(separator)
  )
  local segments = {}

  local num_segments
  if cisco_format == true then
    num_segments = 3
  else
    num_segments = 6
  end

  local chars_per_segment
  if cisco_format == true then
    chars_per_segment = 4
  else
    chars_per_segment = 2
  end

  local function make_segment()
    local segment = ""
    for _ = 1, chars_per_segment do
      segment = segment .. string.format("%x", math.random(0xF))
    end

    return segment
  end

  for i = 1, num_segments do
    table.insert(segments, i, make_segment())
  end

  return table.concat(segments, separator):upper()
end


---Generate a random Hue Application Key/"username"
---@param len number? Number between 10 and 40 for the desired length of the application key. Selected randomly from the range if omitted.
---@return string key the hue application key
function test_helpers.random_hue_bridge_key(len)
  local charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890-_"
  len = (type(len) == "number" and len > 10 and len) or math.random(10, 40)

  local key = ""
  for i=1,len do
    key = key .. charset:sub(math.random(1, #charset), 1)
  end
  return key
end

---Generate partiall random Hue Bridge Info
---@param override_info HueBridgeInfo? Optional, overrides for the generated fields; can be a partial table.
---@return HueBridgeInfo bridge_info
function test_helpers.random_bridge_info(override_info)
  override_info = override_info or {}
  local mac_addr = override_info.mac_addr or test_helpers.random_mac_address(':', false)

  return {
    name = override_info.name or "Philips Hue",
    datastoreversion = override_info.datastoreversion or "166",
    swversion = override_info.swversion or "1963089030",
    apiversion = override_info.apiversion or "1.63.0",
    mac = mac_addr,
    bridge_id = mac_addr:upper():gsub(':', ''),
    factorynew = override_info.factoryenw or false,
    replacesbridgeid = override_info.replacesbridgeid or false,
    modelid = override_info.modelid or "BSB002",
    starterkitid = override_info.starterkitid or "",
    ip = override_info.ip or test_helpers.random_private_ip_address()
  }
end

return test_helpers
