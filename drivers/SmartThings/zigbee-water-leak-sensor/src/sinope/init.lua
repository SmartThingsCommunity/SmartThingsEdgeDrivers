-- Copyright 2023 SmartThings
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

local capabilities = require "st.capabilities"
local zcl_clusters = require "st.zigbee.zcl.clusters"
local IASZone = zcl_clusters.IASZone

local SINOPE_TECHNOLOGIES_MFR_STRING = "Sinope Technologies"

local generate_event_from_zone_status = function(driver, device, zone_status, zb_rx)
  local event
  if zone_status:is_alarm1_set() then
    event = capabilities.waterSensor.water.wet()
  else
    event = capabilities.waterSensor.water.dry()
  end

  if event ~= nil then
    device:emit_event(event)
  end
end

local ias_zone_status_attr_handler = function(driver, device, zone_status, zb_rx)
  generate_event_from_zone_status(driver, device, zone_status, zb_rx)
end

local ias_zone_status_change_handler = function(driver, device, zb_rx)
  generate_event_from_zone_status(driver, device, zb_rx.body.zcl_body.zone_status, zb_rx)
end

local is_sinope_water_sensor = function(opts, driver, device)
  if device:get_manufacturer() == SINOPE_TECHNOLOGIES_MFR_STRING then
    return true
  else
    return false
  end
end

local sinope_water_sensor = {
  NAME = "Sinope Water Leak Sensor",
  zigbee_handlers = {
    attr = {
      [IASZone.ID] = {
        [IASZone.attributes.ZoneStatus.ID] = ias_zone_status_attr_handler
      }
    },
    cluster = {
      [IASZone.ID] = {
        [IASZone.client.commands.ZoneStatusChangeNotification.ID] = ias_zone_status_change_handler
      }
    }
  },
  can_handle = is_sinope_water_sensor
}

return sinope_water_sensor