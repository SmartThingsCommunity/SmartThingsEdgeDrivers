local log = require "log"
local socket = require "cosock".socket
local st_utils = require "st.utils"
-- trick to fix the VS Code Lua Language Server typechecking
---@type fun(val: any?, name: string?, multi_line: boolean?): string
st_utils.stringify_table = st_utils.stringify_table

local HueDeviceTypes = require "hue_device_types"

---@class DiscoveredMotionSensorHandler: DiscoveredChildDeviceHandler
local M = {}

-- TODO This should be generalizable to all "sensors", including buttons.
---@param driver HueDriver
---@param api_instance PhilipsHueApi
---@param device_service_info HueDeviceInfo
---@param bridge_network_id string
---@param cache table?
---@return table<string,any>? description nil on error
---@return string? err nil on success
local function _do_update(driver, api_instance, device_service_info, bridge_network_id, cache)
  log.debug("------------ _do_update")
  local rid_by_rtype = {}
  for _, svc in ipairs(device_service_info.services) do
    rid_by_rtype[svc.rtype] = svc.rid
  end

  local motion, motion_err = api_instance:get_motion_by_id(rid_by_rtype[HueDeviceTypes.MOTION])
  if motion_err then return nil, motion_err end

  local temperature, temp_err = api_instance:get_temperature_by_id(rid_by_rtype[HueDeviceTypes.TEMPERATURE])
  if temp_err then return nil, temp_err end

  local illuminance, illuminance_err = api_instance:get_light_level_by_id(rid_by_rtype[HueDeviceTypes.LIGHT_LEVEL])
  if illuminance_err then return nil, illuminance_err end

  local battery, battery_err = api_instance:get_device_power_by_id(rid_by_rtype[HueDeviceTypes.DEVICE_POWER])
  if battery_err then return nil, battery_err end

  local resource_id = rid_by_rtype[HueDeviceTypes.MOTION]
  local bridge_device = driver:get_device_by_dni(bridge_network_id) --[[@as HueBridgeDevice]]
  local motion_sensor_description = {
    hue_provided_name = device_service_info.metadata.name,
    id = resource_id,
    parent_device_id = bridge_device.id,
    hue_device_id = device_service_info.id,
    hue_device_data = device_service_info,
  }

  if motion and motion.data and motion.data[1] then
    motion_sensor_description.motion = motion.data[1].motion
    motion_sensor_description.motion_enabled = motion.data[1].enabled

  end

  if battery and battery.data and battery.data[1] then
    motion_sensor_description.power_id = battery.data[1].id
    motion_sensor_description.power_state = battery.data[1].power_state
  end

  if temperature and temperature.data and temperature.data[1] then
    motion_sensor_description.temperature_id = temperature.data[1].id
    motion_sensor_description.temperature = temperature.data[1].temperature
    motion_sensor_description.temperature_enabled = temperature.data[1].enabled
  end

  if illuminance and illuminance.data and illuminance.data[1] then
    motion_sensor_description.light_level_id = illuminance.data[1].id
    motion_sensor_description.light = illuminance.data[1].light
    motion_sensor_description.light_level_enabled = illuminance.data[1].enabled
  end

  motion_sensor_description.sensor_list = {
    id = HueDeviceTypes.MOTION,
    power_id = HueDeviceTypes.DEVICE_POWER,
    temperature_id = HueDeviceTypes.TEMPERATURE,
    light_level_id = HueDeviceTypes.LIGHT_LEVEL
  }

  if type(cache) == "table" then
    cache[resource_id] = motion_sensor_description
    if device_service_info.id_v1 then
      cache[device_service_info.id_v1] = motion_sensor_description
    end
  end

  return motion_sensor_description
end

---@param driver HueDriver
---@param api_instance PhilipsHueApi
---@param device_service_id string
---@param bridge_network_id string
---@param cache table?
---@return table<string,any>? description nil on error
---@return string? err nil on success
function M.update_state_for_all_device_services(driver, api_instance, device_service_id, bridge_network_id, cache)
  log.debug("----------- Calling REST API")
  local device_service_info, err = api_instance:get_device_by_id(device_service_id)
  if err or not (device_service_info and device_service_info.data) then
    log.error("Couldn't get device info for sensor, error: " .. st_utils.stringify_table(err))
    return
  end

  return _do_update(driver, api_instance, device_service_info.data[1], bridge_network_id, cache)
end

---@param driver HueDriver
---@param bridge_network_id string
---@param api_instance PhilipsHueApi
---@param primary_services table<HueDeviceTypes,HueServiceInfo[]>
---@param device_service_info HueDeviceInfo
---@param device_state_disco_cache table<string, table>
---@param st_metadata_callback fun(driver: HueDriver, metadata: table)?
function M.handle_discovered_device(
    driver, bridge_network_id, api_instance,
    primary_services, device_service_info,
    device_state_disco_cache, st_metadata_callback
)
  local err = select(2,
    _do_update(
      driver, api_instance, device_service_info, bridge_network_id, device_state_disco_cache
    )
  )
  if err then
    log.error("Error updating motion sensor initial state: " .. st_utils.stringify_table(err))
    return
  end

  if type(st_metadata_callback) == "function" then
    local resource_id = primary_services[HueDeviceTypes.MOTION][1].rid
    local bridge_device = driver:get_device_by_dni(bridge_network_id) or {}
    local st_metadata = {
      type = "EDGE_CHILD",
      label = device_service_info.metadata.name,
      vendor_provided_label = device_service_info.product_data.product_name,
      profile = "motion-sensor",
      manufacturer = device_service_info.product_data.manufacturer_name,
      model = device_service_info.product_data.model_id,
      parent_device_id = bridge_device.id,
      parent_assigned_child_key = string.format("%s:%s", HueDeviceTypes.MOTION, resource_id)
    }

    log.debug(st_utils.stringify_table(st_metadata, "motion sensor create", true))

    st_metadata_callback(driver, st_metadata)
    -- rate limit ourself.
    socket.sleep(0.1)
  end
end

return M
