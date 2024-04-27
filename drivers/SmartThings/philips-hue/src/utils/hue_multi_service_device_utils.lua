local utils = require "utils"

local lazy_disco_handlers = utils.lazy_handler_loader("disco")
---@class MultiServiceDeviceUtils
local multi_service_device_utils = {}

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

return multi_service_device_utils
