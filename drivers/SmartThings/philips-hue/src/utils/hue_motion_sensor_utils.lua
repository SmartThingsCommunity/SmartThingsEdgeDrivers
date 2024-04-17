local utils = require "utils"

local lazy_disco_handlers = utils.lazy_handler_loader("disco")
---@class SensorUtils
local motion_sensor_utils = {}

---@param sensor_device_type HueDeviceTypes
---@param api_instance PhilipsHueApi
---@param device_service_id string
---@param bridge_id string
---@return table<string,any>? nil on error
---@return string? err nil on success
function motion_sensor_utils.get_all_service_states(sensor_device_type, api_instance, device_service_id, bridge_id)
  return lazy_disco_handlers[sensor_device_type].update_all_services_for_sensor(api_instance, device_service_id, bridge_id)
end

return motion_sensor_utils
