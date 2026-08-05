local log = require "log"
local st_utils = require "st.utils"

local PlayerFields = require "fields".SonosPlayerFields

---@class utils
local utils = {}

--- Returns the properly concatenated and formatted string for the a key that
--- uniquely identifies a Sonos speaker on the network via its household ID and
--- player ID.
---@param household_id HouseholdId?
---@param player_id PlayerId?
---@return UniqueKey? unique_key the unique key, as long as the inputs are valid, nil otherwise
---@return "HouseholdId"|"PlayerId"|nil invalid_key_name which key argument was bad, nil otherwise
function utils.sonos_unique_key(household_id, player_id)
  if type(household_id) ~= "string" then
    return nil, "HouseholdId"
  end
  if type(player_id) ~= "string" then
    return nil, "PlayerId"
  end

  return string.format("%s/%s", household_id:lower(), player_id:lower())
end
---
--- Gets a string that uniquely identifies the player in the Sonos topology by combining
--- both Player ID and Household ID
---@param device SonosDevice
function utils.sonos_unique_key_from_device_record(device)
  local cached_key = device:get_field(PlayerFields.UNIQUE_KEY)
  if cached_key then
    return cached_key
  end
  local player_id = device:get_field(PlayerFields.PLAYER_ID)
  local household_id = device:get_field(PlayerFields.HOUSEHOLD_ID)
  if not (player_id or household_id) then
    local driver = device.driver
    local _player_id, _household_id = driver.sonos:get_player_for_device(device)
    if not (player_id or _player_id) then
      return nil,
        string.format(
          "unable to determine Player ID for device %s",
          (device.label or device.id or "<incomplete device record>")
        )
    end
    player_id = player_id or _player_id
    device:set_field(PlayerFields.PLAYER_ID, player_id, { persist = true })

    if not (household_id or _household_id) then
      return nil,
        string.format(
          "unable to determine Household ID for device %s",
          (device.label or device.id or "<incomplete device record>")
        )
    end
    household_id = household_id or _household_id
    device:set_field(PlayerFields.HOUSEHOLD_ID, household_id, { persist = true })
  end

  local unique_key = utils.sonos_unique_key(household_id, player_id)
  device:set_field(PlayerFields.UNIQUE_KEY, unique_key)
  return unique_key
end

--- [TODO:description]
---@param ssdp_info SonosSSDPInfo
function utils.sonos_unique_key_from_ssdp(ssdp_info)
  return utils.sonos_unique_key(ssdp_info.household_id, ssdp_info.player_id)
end

---@param device SonosDevice
---@param field_key string
---@param new_value any
---@param opts table?
---@return boolean
function utils.update_field_if_changed(device, field_key, new_value, opts)
  if
    not (
      device
      and device.id
      and type(device.get_field) == "function"
      and type(device.set_field) == "function"
    )
  then
    log.error(
      string.format(
        "[device %s] table is incomplete",
        (device and device.label or device.id or "<unknown device>")
      )
    )
  end

  local old_value = device:get_field(field_key)
  local changed = (type(old_value) ~= type(new_value))
    or (not utils.deep_table_eq(old_value, new_value))
  if changed then
    device:set_field(field_key, new_value, opts)
    return true
  end
  return false
end

local function __normalize_mac_key_index(tbl, key)
  assert(type(key) == "string", "DNI must be a string!")
  return rawget(tbl, utils.normalize_mac_address(key))
end

local function __normalize_mac_key_newindex(tbl, key, value)
  assert(type(key) == "string", "DNI must be a string!")
  rawset(tbl, utils.normalize_mac_address(key), value)
end

local _mac_addr_key_mt = {
  __index = __normalize_mac_key_index,
  __newindex = __normalize_mac_key_newindex,
}

---creates a table that takes MAC addresses as a key. The table itself is mostly normal,
---but it uses special `__index` and `__newindex` metamethods to perform MAC address normalization
---on the keys before performing lookups.
function utils.new_mac_address_keyed_table()
  return setmetatable({}, _mac_addr_key_mt)
end

---@param tbl table<string,any>
---@param key string
local function __case_insensitive_key_index(tbl, key)
  if type(key) ~= "string" then
    local fmt_val
    if type(key) == "table" then
      fmt_val = st_utils.stringify_table(key)
    else
      fmt_val = key or "<nil>"
    end
    log.warn_with(
      { hub_logs = false },
      string.format(
        "Expected `string` key for CaseInsensitiveKeyTable, received (%s: %s)",
        fmt_val,
        type(key)
      )
    )
    return nil
  else
    local lowercase = key:lower()
    return rawget(tbl, lowercase)
  end
end

local function __case_insensitive_key_newindex(tbl, key, value)
  if type(key) ~= "string" then
    local fmt_val
    if type(key) == "table" then
      fmt_val = st_utils.stringify_table(key)
    else
      fmt_val = key or "<nil>"
    end
    log.warn_with(
      { hub_logs = false },
      string.format(
        "Expected `string` key for CaseInsensitiveKeyTable, received (%s: %s)",
        fmt_val,
        type(key)
      )
    )
  else
    rawset(tbl, key:lower(), value)
  end
end

local _case_insensitive_key_mt = {
  __index = __case_insensitive_key_index,
  __newindex = __case_insensitive_key_newindex,
  __metatable = "CaseInsensitiveKeyTable",
}

function utils.new_case_insensitive_table()
  return setmetatable({}, _case_insensitive_key_mt)
end

---@param sonos_device_info SonosDeviceInfoObject
function utils.extract_mac_addr(sonos_device_info)
  if type(sonos_device_info) ~= "table" or type(sonos_device_info.serialNumber) ~= "string" then
    log.error_with(
      { hub_logs = false },
      string.format("Bad sonos device info passed to `extract_mac_addr`: %s", sonos_device_info)
    )
  end
  local mac, _ = sonos_device_info.serialNumber:match("(.*):.*"):gsub("-", "")
  return utils.normalize_mac_address(mac)
end

---normalizes a MAC address by removing all `-` and `:` characters, then
---unifying on uppercase letters.
---
---@param mac_addr string
---@return string
function utils.normalize_mac_address(mac_addr)
  return mac_addr:gsub("-", ""):gsub(":", ""):upper()
end

function utils.mac_address_eq(a, b)
  if not (type(a) == "string" and type(b) == "string") then
    return false
  end
  local a_normalized = utils.normalize_mac_address(a)
  local b_normalized = utils.normalize_mac_address(b)
  return a_normalized == b_normalized
end

function utils.read_only(tbl)
  if type(tbl) == "table" then
    local proxy = {}
    local mt = { -- create metatable
      __index = tbl,
      __newindex = function(t, k, v)
        error("attempt to update a read-only table", 2)
      end,
    }
    setmetatable(proxy, mt)
    return proxy
  else
    return tbl
  end
end

-- build a exponential backoff time value generator
--
-- max: the maximum wait interval (not including `rand factor`)
-- inc: the rate at which to exponentially back off
-- rand: a randomization range of (-rand, rand) to be added to each interval
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
    if max then
      base = math.min(base, max)
    end

    -- ensure total backoff is >= 0
    return math.max(base + randval, 0)
  end
end

function utils.labeled_socket_builder(label)
  local socket = require "cosock.socket"
  local ssl = require "cosock.ssl"

  label = (label or "")
  if #label > 0 then
    label = label .. " "
  end

  local function make_socket(host, port, wrap_ssl)
    log.trace(string.format("%sCreating TCP socket for REST Connection", label))
    local _ = nil
    local sock, err = socket.tcp()
    if err ~= nil or not sock then
      return nil, (err or "unknown error creating TCP socket")
    end

    log.trace(string.format("%sSetting TCP socket timeout for REST Connection", label))
    _, err = sock:settimeout(60)
    if err ~= nil then
      return nil, "settimeout error: " .. err
    end

    log.trace(string.format("%sConnecting TCP socket for REST Connection", label))
    _, err = sock:connect(host, port)

    if err then
      return nil, err
    end

    log.trace(string.format("%sSet Keepalive for TCP socket for REST Connection", label))
    err = select(2, sock:setoption("keepalive", true))
    if err ~= nil then
      return nil, "Setoption error: " .. err
    end

    if wrap_ssl then
      log.trace(string.format("%sCreating SSL wrapper for for REST Connection", label))
      sock, err =
        ssl.wrap(sock, { mode = "client", protocol = "any", verify = "none", options = "all" })
      if err ~= nil then
        return nil, "SSL wrap error: " .. err
      end
      log.trace(string.format("%sSetting SSL socket timeout for REST Connection", label))
      -- Re-set timeout due to cosock not carrying timeout over in some Lua library versions
      err = select(2, sock:settimeout(60))
      if err ~= nil then
        return nil, "settimeout error: " .. err
      end
      log.trace(string.format("%sPerforming SSL handshake for for REST Connection", label))
      _, err = sock:dohandshake()
      if err ~= nil then
        return nil, "Error with SSL handshake: " .. err
      end
    end

    return sock, err
  end
  return make_socket
end

--- From https://gist.github.com/sapphyrus/fd9aeb871e3ce966cc4b0b969f62f539
--- MIT licensed
function utils.deep_table_eq(tbl1, tbl2)
  if tbl1 == tbl2 then
    return true
  elseif type(tbl1) == "table" and type(tbl2) == "table" then
    for key1, value1 in pairs(tbl1 or {}) do
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
    for key2, _ in pairs(tbl2 or {}) do
      if tbl1[key2] == nil then
        return false
      end
    end

    return true
  end

  return false
end

return utils
