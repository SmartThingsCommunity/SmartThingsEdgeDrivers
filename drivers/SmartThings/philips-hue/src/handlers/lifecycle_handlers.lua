local log = require "log"
local st_utils = require "st.utils"

local Fields = require "fields"
local utils = require "utils"

-- Lazy-load the lifecycle handlers so we only load the code we need
local inner_handlers = setmetatable(
  {},
  {
    __index = function(tbl, key)
      if rawget(tbl, key) == nil then
        rawset(tbl, key, require(string.format("handlers.lifecycle_handlers.%s", key)))
      end

      return rawget(tbl, key)
    end
  }
)

-- Lazy-load the migration handlers so we only load the code we need
local migration_handlers = setmetatable(
  {},
  {
    __index = function(tbl, key)
      if rawget(tbl, key) == nil then
        rawset(tbl, key, require(string.format("handlers.migration_handlers.%s", key)))
      end

      return rawget(tbl, key)
    end
  }
)

---@class LifecycleHandlers
local LifecycleHandlers = {}

---@param driver HueDriver
---@param device HueDevice
function LifecycleHandlers.device_init(driver, device, ...)
  local device_type = device:get_field(Fields.DEVICE_TYPE)
  log.info(
    string.format
    ("device_init for device %s, device_type: %s", (device.label or device.id or "unknown device"),
      device_type
    )
  )
  inner_handlers[device_type].init(driver, device, ...)
end

---@param driver HueDriver
---@param device HueDevice
function LifecycleHandlers.device_added(driver, device, ...)
  log.info(
    string.format("device_added for device %s", (device.label or device.id or "unknown device"))
  )
  if utils.is_dth_bridge(device) or utils.is_dth_light(device) then
    LifecycleHandlers.migrate_device(driver, device, ...)
  else
    local device_type = utils.determine_device_type(device)
    if not inner_handlers[device_type] then
      log.warn(
        st_utils.stringify_table(device,
          string.format("Device Added %s does not appear to be a bridge or bulb",
            device.label or device.id or "unknown device"), true)
      )
    end
    inner_handlers[device_type].added(driver, device, ...)
  end
end

function LifecycleHandlers.migrate_device(driver, device, ...)
  if utils.is_dth_bridge(device) then
    migration_handlers.bridge.migrate(driver, device, LifecycleHandlers, ...)
  elseif utils.is_dth_light(device) then
    migration_handlers.light.migrate(driver, device, LifecycleHandlers, ...)
    -- Don't do a refresh if it's a migration
    device:set_field(Fields._REFRESH_AFTER_INIT, false, { persist = true })
  end
end

--- Callback that is used for both `init` and `added` events. It will properly dispatch
--- to the correct handler based on the state of the device record.
---
--- This is currently in place as a workaround for situations where init will sometimes
--- be missed when onboarding lots of child devices at once.
---@param driver HueDriver
---@param device HueDevice
---@param event string?
---@param _args table? unused
function LifecycleHandlers.initialize_device(driver, device, event, _args, ...)
  local maybe_device = driver:get_device_by_dni(device.device_network_id)
  if not (
        maybe_device
        and maybe_device.id == device.id
      )
  then
    driver.datastore.dni_to_device_id[device.device_network_id] = device.id
  end

  log.info(
    string.format("_initialize handling event %s for device %s", event, (device.label or device.id or "unknown device")))
  if not device:get_field(Fields._ADDED) then
    log.debug(
      string.format(
        "_ADDED for device %s not set while _initialize is handling %s, performing added lifecycle operations",
        (device.label or device.id or "unknown device"), event))
    LifecycleHandlers.device_added(driver, device, ...)
  end

  if not device:get_field(Fields._INIT) then
    log.debug(
      string.format(
        "_INIT for device %s not set while _initialize is handling %s, performing device init lifecycle operations",
        (device.label or device.id or "unknown device"), event))
    LifecycleHandlers.device_init(driver, device, ...)
  end
end

return LifecycleHandlers
