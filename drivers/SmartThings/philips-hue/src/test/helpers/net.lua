---@class test.helpers.net
local m = {}

local private_cidr_strings = {
  ["192.168.0.0/16"] = true,
  ["172.16.0.0/12"] = true,
  ["10.0.0.0/8"] = true
}

---Generate a random IP address for the given CIDR string
---@param cidr_string string? Optional, must be a CIDR string identifying one of the three private network spaces. Defaults to "192.168.0.0/16"
---@return string ip a random IP address.
function m.random_private_ip_address(cidr_string)
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
function m.random_mac_address(separator, cisco_format)
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


return m
