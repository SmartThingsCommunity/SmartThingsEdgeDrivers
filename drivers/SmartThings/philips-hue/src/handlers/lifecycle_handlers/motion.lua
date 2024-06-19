local log = require "log"
local st_utils = require "st.utils"

local refresh_handler = require("handlers.commands").refresh_handler

local Discovery = require "disco"
local Fields = require "fields"
local HueDeviceTypes = require "hue_device_types"
local StrayDeviceHelper = require "stray_device_helper"

local motion_sensor_disco = require "disco.motion"
local hue_multi_service_device_utils = require "utils.hue_multi_service_device_utils"
local utils = require "utils"

---@class MotionLifecycleHandlers
local MotionLifecycleHandlers = {}

---@param driver HueDriver
---@param device HueChildDevice
---@param parent_device_id string?
---@param resource_id string?
function MotionLifecycleHandlers.added(driver, device, parent_device_id, resource_id)
  log.info(
    string.format("Motion Sensor Added for device %s", (device.label or device.id or "unknown device")))
  local device_sensor_resource_id = resource_id or utils.get_hue_rid(device)
  if not device_sensor_resource_id then
    log.error(
      string.format(
        "Could not determine the Hue Resource ID for added motion sensor %s",
        (device and device.label) or "unknown sensor"
      )
    )
    return
  end

  local sensor_info = Discovery.device_state_disco_cache[device_sensor_resource_id]
  if not sensor_info then
    log.error(
      string.format(
        "Expected sensor info to be cached, sending motion sensor %s to stray resolver",
        (device and device.label) or "unknown sensor"
      )
    )
    driver.stray_device_tx:send({
      type = StrayDeviceHelper.MessageTypes.NewStrayDevice,
      driver = driver,
      device = device
    })
    return
  end

  driver.hue_identifier_to_device_record[sensor_info.power_id] = device
  driver.hue_identifier_to_device_record[sensor_info.temperature_id] = device
  driver.hue_identifier_to_device_record[sensor_info.light_level_id] = device

  device:set_field(Fields.DEVICE_TYPE, HueDeviceTypes.MOTION, { persist = true })
  device:set_field(Fields.HUE_DEVICE_ID, sensor_info.hue_device_id, { persist = true })
  device:set_field(Fields.PARENT_DEVICE_ID, sensor_info.parent_device_id, { persist = true })
  device:set_field(Fields.RESOURCE_ID, device_sensor_resource_id, { persist = true })
  device:set_field(Fields._ADDED, true, { persist = true })
  device:set_field(Fields._REFRESH_AFTER_INIT, true, { persist = true })

  driver.hue_identifier_to_device_record[device_sensor_resource_id] = device
end

---@param driver HueDriver
---@param device HueChildDevice
function MotionLifecycleHandlers.init(driver, device)
  log.info(
    string.format("Init Motion Sensor for device %s", (device and device.label or device.id or "unknown sensor")))
  device:set_field(Fields.IS_MULTI_SERVICE, true, { persist = true })
  local device_sensor_resource_id =
      utils.get_hue_rid(device) or
      device.device_network_id

  log.debug("resource id " .. tostring(device_sensor_resource_id))

  local hue_device_id = device:get_field(Fields.HUE_DEVICE_ID)
  if not driver.hue_identifier_to_device_record[device_sensor_resource_id] then
    driver.hue_identifier_to_device_record[device_sensor_resource_id] = device
  end
  local sensor_info, err
  sensor_info = Discovery.device_state_disco_cache[device_sensor_resource_id]
  if not sensor_info then
    log.debug("no sensor info")
    local parent_bridge = utils.get_hue_bridge_for_device(
      driver, device, device.parent_device_id or device:get_field(Fields.PARENT_DEVICE_ID)
    )
    local api_instance = (parent_bridge and parent_bridge:get_field(Fields.BRIDGE_API))

    if parent_bridge and api_instance then
      log.debug("--------------------- update all start")
      sensor_info, err = motion_sensor_disco.update_state_for_all_device_services(
        driver,
        api_instance,
        hue_device_id,
        parent_bridge.device_network_id,
        Discovery.device_state_disco_cache
      )
      log.debug("--------------------- update all complete")
      if err then
        log.error(
          st_utils.stringify_table(
            err,
            string.format(
              "Error populating initial state for sensor %s",
              (device and device.label) or "unknown sensor"
            ),
            true
          )
        )
      end
    end
  end
  if not sensor_info then
    log.warn(string.format("Motion Sensor %s parent bridge not ready, queuing refresh", device and device.label))
    driver._devices_pending_refresh[device.id] = device
  else
    hue_multi_service_device_utils.update_multi_service_device_maps(
      driver, device, hue_device_id, sensor_info, HueDeviceTypes.CONTACT
    )
  end
  device:set_field(Fields._INIT, true, { persist = false })
  if device:get_field(Fields._REFRESH_AFTER_INIT) then
    refresh_handler(driver, device)
    device:set_field(Fields._REFRESH_AFTER_INIT, false, { persist = true })
  end
end

return MotionLifecycleHandlers
