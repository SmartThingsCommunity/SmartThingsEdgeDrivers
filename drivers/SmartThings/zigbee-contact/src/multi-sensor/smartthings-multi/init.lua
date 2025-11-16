-- Copyright 2022 SmartThings
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

local battery_defaults = require "st.zigbee.defaults.battery_defaults"
local zcl_commands = require "st.zigbee.zcl.global_commands"
local multi_utils = require "multi-sensor/multi_utils"
local capabilities = require "st.capabilities"
local data_types = require "st.zigbee.data_types"
local zcl_clusters = require "st.zigbee.zcl.clusters"

local SMARTTHINGS_MFG = 0x110A

local battery_table = {
  [2.80] = 100,
  [2.70] = 100,
  [2.60] = 100,
  [2.50] = 90,
  [2.40] = 90,
  [2.30] = 70,
  [2.20] = 70,
  [2.10] = 50,
  [2.00] = 50,
  [1.90] = 30,
  [1.80] = 30,
  [1.70] = 15,
  [1.60] = 1,
  [1.50] = 0
}

local function multi_sensor_report_handler(driver, device, zb_rx)
  local x, y, z
  for i,v in ipairs(zb_rx.body.zcl_body.attr_records) do
    if (v.attr_id.value == multi_utils.AXIS_X_ATTR) then
      z = -v.data.value
    elseif (v.attr_id.value == multi_utils.AXIS_Y_ATTR) then
      y = v.data.value
    elseif (v.attr_id.value == multi_utils.AXIS_Z_ATTR) then
      x = v.data.value
    elseif (v.attr_id.value == multi_utils.ACCELERATION_ATTR) then
      multi_utils.handle_acceleration_report(device, v.data.value)
    end
  end
  multi_utils.handle_three_axis_report(device, x, y, z)
end

local function init_handler(driver, device)
  battery_defaults.enable_battery_voltage_table(device, battery_table)
  device:remove_configured_attribute(zcl_clusters.IASZone.ID, zcl_clusters.IASZone.attributes.ZoneStatus.ID)
  device:remove_monitored_attribute(zcl_clusters.IASZone.ID, zcl_clusters.IASZone.attributes.ZoneStatus.ID)
end

local function do_configure(self, device)
  device:configure()
  device:send(multi_utils.custom_write_attribute(device, multi_utils.MOTION_THRESHOLD_MULTIPLIER_ATTR, data_types.Uint8, 0x01, SMARTTHINGS_MFG))
  device:send(multi_utils.custom_write_attribute(device, multi_utils.MOTION_THRESHOLD_ATTR, data_types.Uint16, 0x0276, SMARTTHINGS_MFG))
  multi_utils.send_common_configuration(self, device, SMARTTHINGS_MFG)
end

local function do_refresh(self, device)
  device:refresh()
  device:send(multi_utils.custom_read_attribute(device, multi_utils.ACCELERATION_ATTR, SMARTTHINGS_MFG))
end

local smartthings_multi = {
  NAME = "SmartThings Multi Sensor",
  lifecycle_handlers = {
    init = init_handler,
    doConfigure = do_configure
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh,
    }
  },
  zigbee_handlers = {
    global = {
      [multi_utils.CUSTOM_ACCELERATION_CLUSTER] = {
        [zcl_commands.ReportAttribute.ID] = multi_sensor_report_handler,
        [zcl_commands.ReadAttributeResponse.ID] = multi_sensor_report_handler
      }
    }
  },
  can_handle = function(opts, driver, device, ...)
    return device:get_manufacturer() == "SmartThings"
  end
}

return smartthings_multi
