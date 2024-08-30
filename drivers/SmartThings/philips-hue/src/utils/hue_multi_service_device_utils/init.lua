local log = require "log"
local utils = require "utils"

local HueDeviceTypes = require "hue_device_types"

local lazy_disco_handlers = utils.lazy_handler_loader("disco")
local lazy_map_helpers = utils.lazy_handler_loader("utils.hue_multi_service_device_utils")

local lookup_transforms = {
  [HueDeviceTypes.MOTION] = "sensor",
  [HueDeviceTypes.CONTACT] = "sensor",
  [HueDeviceTypes.BUTTON] = "sensor"
}

---@class MultiServiceDeviceUtils
local multi_service_device_utils = {}

-- TODO refactor this to be generalized for all sensors, similar to the multi service map update.
---@param driver HueDriver
---@param sensor_device_type HueDeviceTypes
---@param api_instance PhilipsHueApi
---@param device_service_id string
---@param bridge_network_id string
---@return table<string,any>? nil on error
---@return string? err nil on success
function multi_service_device_utils.get_all_service_states(driver, sensor_device_type, api_instance, device_service_id, bridge_network_id)
  return lazy_disco_handlers[sensor_device_type].update_state_for_all_device_services(driver, api_instance, device_service_id, bridge_network_id)
end

function multi_service_device_utils.update_multi_service_device_maps(driver, device, hue_device_id, device_info, device_type)
  device_type = device_type or utils.determine_device_type(device)
  device_type = lookup_transforms[device_type] or device_type
  if not lazy_map_helpers[device_type] then
    log.warn(
      string.format(
        "No multi-service device mapping helper for device %s with type %s",
        (device and device.label) or "unknown device",
        device_type or "unknown type"
      )
    )
  end
  return lazy_map_helpers[device_type].update_multi_service_device_maps(driver, device, hue_device_id, device_info)
end

return multi_service_device_utils
