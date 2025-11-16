local st_utils = require "st.utils"
-- trick to fix the VS Code Lua Language Server typechecking
---@type fun(val: any?, name: string?, multi_line: boolean?): string
st_utils.stringify_table = st_utils.stringify_table

local log = require "log"
local utils = require "utils"

local Discovery = require "disco"
local HueDeviceTypes = require "hue_device_types"

local lazy_handlers = utils.lazy_handler_loader("handlers")

local hue_debug = {}

local _log = function(msg)
  log.debug("*****>> " .. msg)
end

local function _setup_delayed_bridges(template, delay_time)
  _log("Debug Configuration: Delayed Bridges enabled.")
  local lifecycle_handlers = lazy_handlers.lifecycle_handlers
  local _init = lifecycle_handlers.initialize_device

  local added_bridges = {}
  ---@diagnostic disable-next-line: duplicate-set-field
  lifecycle_handlers.initialize_device = function (driver, device, event, ...)
    local device_type = utils.determine_device_type(device)
    if device_type == HueDeviceTypes.BRIDGE then
      if event == "added" then
        added_bridges[device.id] = true
      end

      if added_bridges[device.id] and event == "init" then
        _log(string.format("Ignoring init event for %s due to emulating delayed added", device.label))
        return
      end

      _log(string.format("------------------------ Wrapped init bridge for event %s", event))
      _log(string.format("Delaying bridge initialization for [%s] by %s seconds", device.label, delay_time))
      local maybe_device = driver:get_device_by_dni(device.device_network_id)
      if not (
            maybe_device
            and maybe_device.id == device.id
          )
      then
        driver.datastore.dni_to_device_id[device.device_network_id] = device.id
      end
      local args = table.pack(...)
      driver:call_with_delay(
        delay_time,
        function(_)
          _log(string.format("Performing initialization for bridge [%s]", device.label))
          _init(driver, device, event, table.unpack(args))
        end,
        "Delayed Bridge Initialize"
      )
      return
    end

    _init(driver, device, event, ...)
  end

  template.lifecycle_handlers.added = utils.safe_wrap_handler(lifecycle_handlers.initialize_device)
  template.lifecycle_handlers.init = utils.safe_wrap_handler(lifecycle_handlers.initialize_device)
end

local function _setup_forced_strays(forced_stray_types)
  _log(
    st_utils.stringify_table(
      forced_stray_types,
      "Debug Configuration: Forced Stray Devices enabled for the following",
      true
    )
  )
  local type_map = {}
  for _, device_type in ipairs(forced_stray_types) do
    type_map[device_type] = HueDeviceTypes.is_valid_device_type(device_type)
  end
  local added = lazy_handlers.lifecycle_handlers.device_added
  local forced_devices = {}
  lazy_handlers.lifecycle_handlers.device_added = function(driver, device, ...)
    local device_type = utils.determine_device_type(device)
    local device_rid = utils.get_hue_rid(device)
    if device_rid and type_map[device_type] and not forced_devices[device.id] then
      _log(string.format("Forcing device [%s] as stray by removing its device state disco cache", device.label))
      forced_devices[device.id] = true
      Discovery.device_state_disco_cache[device_rid] = nil
      added(driver, device, ...)
    end
  end
end

function hue_debug.enable_dbg_config(template, config)
  assert(template.__running ~= true, "enable_dbg_config must be called before driver run and only once")

  config = config or {}
  if config.delay_bridges then
    _setup_delayed_bridges(template, config.bridge_delay_time or 10)
  end

  if type(config.force_stray_for_device_type) == "table" then
    _setup_forced_strays(config.force_stray_for_device_type)
  end
end

return hue_debug
