local utils = require "utils"

local SensorMultiServiceHelper = {}
function SensorMultiServiceHelper.update_multi_service_device_maps(driver, device, hue_device_id, sensor_info)
  local svc_rids_for_device = driver.services_for_device_rid[hue_device_id] or {}

  if type(sensor_info.sensor_list) == "table" then
    for id_key, sensor_type in pairs(sensor_info.sensor_list) do
      if
        sensor_info and
        sensor_info[id_key] and
        not svc_rids_for_device[sensor_info[id_key]]
      then
        svc_rids_for_device[sensor_info[id_key]] = sensor_type
      end
    end
  end

  driver.services_for_device_rid[hue_device_id] = svc_rids_for_device
  local hue_id_to_device = utils.get_hue_id_to_device_table_by_bridge(driver, device)
  for rid, _ in pairs(driver.services_for_device_rid[hue_device_id]) do
    hue_id_to_device[rid] = device
  end
end

return SensorMultiServiceHelper
