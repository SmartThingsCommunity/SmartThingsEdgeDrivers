local log = require "log"

local Consts = require "consts"
local Fields = require "fields"
local HueDeviceTypes = require "hue_device_types"

---@class utils
local utils = {
  _lazy_loaders = {}
}

function utils.lazy_handler_loader(parent_module)
  if utils._lazy_loaders[parent_module] then
    return utils._lazy_loaders[parent_module]
  end
  local nils = {}
  local loader = setmetatable(
    {},
    {
      __index = function(tbl, key)
        if key == nil then return nil end
        if nils[key] then return nil end
        if rawget(tbl, key) == nil then
          local success, mod = pcall(require, string.format("%s.%s", parent_module, key))
          if success then
            rawset(tbl, key, mod)
          else
            nils[key] = true
            return nil
          end
        end

        return rawget(tbl, key)
      end
    }
  )
  utils._lazy_loaders[parent_module] = loader
  return loader
end

function utils.safe_wrap_handler(handler)
  return function(driver, device, ...)
    if device == nil or (device and device.id == nil) then
      log.warn("Tried to handle capability command for device that has been deleted")
      return
    end
    local success, result = pcall(handler, driver, device, ...)
    if not success then
      log.error_with({ hub_logs = true },
        string.format("Failed to invoke capability command handler. Reason: %s", result))
    end
    return result
  end
end

-- TODO: The Hue API itself doesn't have events for multipresses, however, it will
-- emit batched "short release" eventsource on the SSE stream if they're close together.
-- Right now the SSE stream handling is a relatively dumb pass-through that doesn't inspect
-- the data as it unpacks it; it just dispatches each event in the batch as it encounters it.
-- We could implement 2x-6x press if we add some smarts to the SSE stream handling.
function utils.get_supported_button_values(event_values)
  local values = { "pushed" }
  for _, event_value in ipairs(event_values) do
    if event_value == "long_press" then
      table.insert(values, "held")
      break
    end
  end

  return values
end

function utils.kelvin_to_mirek(kelvin) return 1000000 / kelvin end

function utils.mirek_to_kelvin(mirek)
  local raw_kelvin = 1000000 / mirek
  return Consts.KELVIN_STEP_SIZE * math.floor(raw_kelvin / Consts.KELVIN_STEP_SIZE)
end

function utils.str_starts_with(str, start)
  return str:sub(1, #start) == start
end

function utils.is_nan(number)
  -- IEEE 754 dictates that NaN compares falsey to everything, including itself.
  if number ~= number then
    return true
  end

  -- If someone passes in something that isn't a Number type, it'll pass the above check.
  -- Philosophical question: Something that isn't a number can't technicaly have the value
  -- of "nan" but "nan" stands for "not a number", so what do we do here?
  if type(number) ~= "number" then
    log.warn(string.format("utils.is_nan received value of type %s as argument, returning true", type(number)))
    return true
  end

  -- In the event that something goes wrong with the above two things,
  -- we simply compare the tostring against a known NaN value.
  return tostring(number) == tostring(0 / 0)
end

--- Validate whether or not a string is valid UUIDv4.
--- This only validates the format that uses hex digits with hyphen separators;
--- less common formats such as the no sepatator format, or the curly braces format,
--- or a 128-bit integer, are not accounted for.
---
--- Hue uses what appears to be UUIDv4. But the validation regexes provided in their API
--- reference don't have the typical constraints on the 4-bit version or 2-bit
--- variant fields. So we use a relaxed validation here to match up with their provided
--- regexes, instead of making it a strict UUIDv4 check.
---@param uuid_string string
---@return boolean
function utils.is_hue_id_string(uuid_string)
  if type(uuid_string) ~= "string" then
    return false
  end
  local pattern = string.format(
    "^%s%%-%s%%-%s%%-%s%%-%s$",
    ("%x"):rep(8),
    ("%x"):rep(4),
    ("%x"):rep(4),
    ("%x"):rep(4),
    ("%x"):rep(12)
  )
  return uuid_string:match(pattern) ~= nil
end

--- Parse the parent-assigned child key and extract the Hue resource ID and resource type.
--- Not all parent-assigned child keys have a resource type encoded in them. They *do* always
--- have the resource ID encoded in them.
---
--- The first return value will be true on success, false on failure. The second will be the RID or the error message,
--- and on success the third will be the resource type if it's encoded, or nil if it's not encoded or on error.
---@param device HueDevice
---@return boolean success true if an RID was able to be extracted, false otherwise
---@return string? rid_or_err the hue resource ID, or an error message if success is false
---@return string? maybe_rtype the resource type, if encoded. Some lights that were joined on older driver versions won't have this encoded.
function utils.parse_parent_assigned_key(device)
  local uuid_pattern = string.format(
    "(%s%%-%s%%-%s%%-%s%%-%s)",
    ("%x"):rep(8),
    ("%x"):rep(4),
    ("%x"):rep(4),
    ("%x"):rep(4),
    ("%x"):rep(12)
  )
  local key = (device and device.parent_assigned_child_key) or ""
  local rtype = key:match("([^:]+):")
  local rid = key:match(uuid_pattern)
  if not rid then
    return false, "parent-assigned child key not in the correct format", nil
  end
  return true, rid, (rtype or HueDeviceTypes.LIGHT)
end

--- Determine whether or not a string is a valid MAC Address.
--- This function makes the following assumptions:
---
--- - The input is a string
--- - The address may or may not have separators between the octets
--- - The only valid separators if present are '.', ':', or '-'
--- - If separators are used, then the address must take the form of either
---   six groups of two hex digits (octets) with separators, *or* three groups of four
---   hex digits with separators, which is an odd Cisco format.
--- - In the form with octets, each octet must have two characters. Meaning they
---   must include a leading 0 when necessary.
---@param mac_str string
---@return boolean
function utils.is_valid_mac_addr_string(mac_str)
  -- If the argument is not a string, it's not valid
  if type(mac_str) ~= "string" then
    return false
  end

  -- Get the first separator we encounter
  local separator = mac_str:match('[:%-%.]')

  local separators_removed = mac_str
  -- if there is a separator, make sure that there's only 2 or 5 occurrences.
  if separator then
    -- escape special characters for use in patterns
    if separator == "." then separator = "%." end
    if separator == "-" then separator = "%-" end

    -- We strip the first found separator from the string
    separators_removed = mac_str:gsub(separator, '')

    -- if other separators remain, we have more than one separator character
    -- in use at once, which isn't valid
    if separators_removed:match('[:%-%.]') then
      return false
    end

    -- we count the separator occurrences to make sure it's 2 or 5 as we
    -- expect for the appropriate formats
    local separator_count = select(2, mac_str:gsub(separator, ''))
    if not (separator_count == 2 or separator_count == 5) then
      return false
    end
  end

  -- whatever is left at this point *should* just be 12 hex characters.
  -- If that's what we find, then we're a MAC Address based on our
  -- given assumptions.
  local found = separators_removed:match(('%x'):rep(12))
  return found == separators_removed
end

--- Get the Hue RID from a Child Device
---@param device HueChildDevice
---@return string? resource_id the Hue RID, or nil on error
---@return string? err
function utils.get_hue_rid(device)
  if
    device == nil
    or (device and (device.id == nil or device.get_field == nil or device.device_network_id == nil))
  then
    return nil, string.format("nil or incomplete device record passed to get_hue_rid, device has likely been deleted")
  end

  local resource_id = device:get_field(Fields.RESOURCE_ID)
  if resource_id then
    return resource_id
  end

  if utils.is_dth_light(device) then
    return nil,
        string.format("Can't get the Hue RID of migrated DTH light %s that hasn't completed migration", device.label)
  end

  local success, rid, _ = utils.parse_parent_assigned_key(device)
  if success and rid then
    return rid
  end

  return
      nil,
      string.format(
        "error establishing Hue RID from parent assigned key [%s]",
        (device and device.parent_assigned_child_key) or "Parent Assigned Key Not Available"
      )
end

--- Get the HueDeviceType value for a device. If available on the device field, then it
--- will use that, otherwise, it falls back by parsing SmartThings Device Record metadata
--- such as the DNI or parent_assigned_child_key
---@param device HueDevice
---@return string? device_type the device type, which is a CLIPv2 Resource Type string. Nil on error.
---@return string? err
function utils.determine_device_type(device)
  -- If the device type is already stored on the device record and it's valid, used that.
  if HueDeviceTypes.is_valid_device_type(device:get_field(Fields.DEVICE_TYPE) or "") then
    return device:get_field(Fields.DEVICE_TYPE)
  end

  -- Devices w/ a MAC Address for their DNI are always Hue Bridges.
  if utils.is_valid_mac_addr_string(device.device_network_id) then
    return HueDeviceTypes.BRIDGE
  end

  -- Special-case lookup for migrated DTH lights. Since their parent-assigned
  -- child keys are out of our control, we look at this before we do anything
  -- else.
  if utils.is_dth_light(device) then
    return HueDeviceTypes.LIGHT
  end

  local success, rid, rtype = utils.parse_parent_assigned_key(device)
  -- If the resource type is encoded in the key, we return that.
  if success and rtype then
    return rtype
  end

  -- If the resource is not encoded but the parent assigned key is a
  -- valid UUID, then we can safely assume that we're looking at a Light
  -- that was joined when that was the only device type we supported.
  if success and rid and utils.is_hue_id_string(rid) then
    return HueDeviceTypes.LIGHT
  end

  return
      nil,
      string.format(
        "Couldn't determine device type for device %s",
        (device and device.label) or "Unknown Device"
      )
end

--- Attempts an exhaustive check of all the ways a device
--- can indicate that it represents a Hue Bridge.
---@param driver HueDriver
---@param device HueDevice
---@return boolean is_bridge true if the device record represents a Hue Bridge
function utils.is_bridge(driver, device)
  return (device:get_field(Fields.DEVICE_TYPE) == "bridge")
      or (driver.datastore.bridge_netinfo[device.device_network_id] ~= nil)
      or utils.is_edge_bridge(device) or utils.is_dth_bridge(device)
      or (device.parent_assigned_child_key == nil)
end

--- Only checked during `added` callback, or as a later
--- fallback check in the chain of booleans used in `is_bridge`.
---
---@see utils.is_bridge
---@param device HueDevice
---@return boolean
function utils.is_edge_bridge(device)
  return
      device.device_network_id and
      utils.is_valid_mac_addr_string(device.device_network_id) and
      not (device.data and device.data.username)
end

--- Only checked during `added` callback
---@param device HueDevice
---@return boolean
function utils.is_dth_bridge(device)
  return device.data ~= nil
      and not device.data.bulbId
      and device.data.username ~= nil
end

--- Only checked during `added` callback
---@param device HueDevice
---@return boolean
function utils.is_dth_light(device)
  if string.find(device.device_network_id, "/") then
    return true
  end

  return device.data ~= nil
      and device.data.bulbId ~= nil
      and device.data.username ~= nil
end

--- Get the Hue Bridge for a Device; useful when you don't know if you have a child
--- or a grandchild device and you need to walk up the family tree. Will return the
--- passed argument if the argument is a bridge.
---@param driver HueDriver
---@param device HueDevice
---@param parent_device_id string?
---@return HueBridgeDevice? bridge_device
function utils.get_hue_bridge_for_device(driver, device, parent_device_id)
  log.trace(string.format("------------------------ Looking for bridge for %s with parent_device_id %s", device.label, device.parent_device_id))
  if utils.is_bridge(driver, device) then
    log.trace(string.format("------------------------- %s is a bridge", device.label))
    return device --[[ @as HueBridgeDevice ]]
  end

  local parent_device_id = parent_device_id or device.parent_device_id or device:get_field(Fields.PARENT_DEVICE_ID)
  local parent_device = driver:get_device_info(parent_device_id)
  if not parent_device then
    log.trace(string.format("------------------------- get_device_info for %s was nil", parent_device_id))
    return nil
  end

  log.trace(string.format("------------------------- parent_device label is %s, checking if bridge", parent_device.label))
  if parent_device and utils.is_bridge(driver, parent_device) then
    return parent_device --[[ @as HueBridgeDevice ]]
  end

  return utils.get_hue_bridge_for_device(driver, parent_device)
end

--- build a exponential backoff time value generator
---
---@param max number the maximum wait interval (not including `rand factor`)
---@param inc number the rate at which to exponentially back off
---@param rand number a randomization range of (-rand, rand) to be added to each interval
---@return fun(): number backoff generator function that returns a growing backoff each time it's called based on the params
function utils.backoff_builder(max, inc, rand)
  local count = 0
  inc = inc or 1
  return function()
    local randval = 0
    if rand then
      randval = math.random() * rand * 2 - rand
    end

    local base = inc * (2 ^ count - 1)
    count = count + 1

    -- ensure base backoff (not including random factor) is less than max
    if max then base = math.min(base, max) end

    -- ensure total backoff is >= 0
    return math.max(base + randval, 0)
  end
end

---Wrapper around the socket builder pattern that prepends log messages with a label
---@param label string?
---@return fun(host: string, port: number|string, wrap_ssl: boolean?) sock_builder
function utils.labeled_socket_builder(label)
  local socket = require "cosock.socket"
  local ssl = require "cosock.ssl"

  label = (label or "")
  if #label > 0 then
    label = label .. " "
  end

  local function make_socket(host, port, wrap_ssl)
    log.info(
      string.format(
        "%sCreating TCP socket for Hue REST Connection", label
      )
    )

    local sock, err = socket.tcp()

    if err ~= nil or (not sock) then
      return nil, (err or "unknown error creating TCP socket")
    end

    log.info(
      string.format(
        "%sSetting TCP socket timeout for Hue REST Connection", label
      )
    )
    err = select(2, sock:settimeout(60))
    if err ~= nil then
      return nil, "settimeout error: " .. err
    end

    log.info(
      string.format(
        "%sConnecting TCP socket for Hue REST Connection", label
      )
    )
    err = select(2, sock:connect(host, port))
    if err ~= nil then
      return nil, "Connect error: " .. err
    end

    log.info(
      string.format(
        "%sSet Keepalive for TCP socket for Hue REST Connection", label
      )
    )
    err = select(2, sock:setoption("keepalive", true))
    if err ~= nil then
      return nil, "Setoption error: " .. err
    end

    if wrap_ssl then
      log.info(
        string.format(
          "%sCreating SSL wrapper for for Hue REST Connection", label
        )
      )
      sock, err =
          ssl.wrap(sock, { mode = "client", protocol = "any", verify = "none", options = "all" })
      if not sock or err ~= nil then
        return nil, (err and "SSL wrap error: " .. err) or "Unexpected nil socket returned from ssl.wrap"
      end
      log.info(
        string.format(
          "%sPerforming SSL handshake for for Hue REST Connection", label
        )
      )
      err = select(2, sock:dohandshake())
      if err ~= nil then
        return nil, "Error with SSL handshake: " .. err
      end
    end

    log.info(
      string.format(
        "%sSuccessfully created TCP connection for Hue", label
      )
    )
    return sock, err
  end
  return make_socket
end

--- From https://gist.github.com/sapphyrus/fd9aeb871e3ce966cc4b0b969f62f539
--- MIT licensed
---@param tbl1 table<any,any>
---@param tbl2 table<any,any>
---@return boolean
function utils.deep_table_eq(tbl1, tbl2)
  if tbl1 == tbl2 then
    return true
  elseif type(tbl1) == "table" and type(tbl2) == "table" then
    for key1, value1 in pairs(tbl1) do
      local value2 = tbl2[key1]

      if value2 == nil then
        -- avoid the type call for missing keys in tbl2 by directly comparing with nil
        return false
      elseif value1 ~= value2 then
        if type(value1) == "table" and type(value2) == "table" then
          if not utils.deep_table_eq(value1, value2) then
            return false
          end
        else
          return false
        end
      end
    end

    -- check for missing keys in tbl1
    for key2, _ in pairs(tbl2) do
      if tbl1[key2] == nil then
        return false
      end
    end

    return true
  end

  return false
end

return utils
