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

local zcl_commands = require "st.zigbee.zcl.global_commands"
local multi_utils = require "multi-sensor/multi_utils"

local THIRDREALITY_ACCELERATION_CLUSTER = 0xFFF1
local X_ATTR = 0x0001
local Y_ATTR = 0x0002
local Z_ATTR = 0x0003
local ACCEL_ATTR = 0x0000

local function multi_sensor_report_handler(driver, device, zb_rx)
  local x, y, z
  for i,v in ipairs(zb_rx.body.zcl_body.attr_records) do
    if (v.attr_id.value == X_ATTR) then
      x = v.data.value
    elseif (v.attr_id.value == Y_ATTR) then
      y = v.data.value
    elseif (v.attr_id.value == Z_ATTR) then
      z = v.data.value
    elseif (v.attr_id.value == ACCEL_ATTR) then
      multi_utils.handle_acceleration_report(device, v.data.value)
    end
  end
  multi_utils.handle_three_axis_report(device, x, y, z)
end

local thirdreality_multi = {
  NAME = "ThirdReality Vibration Sensor",
  zigbee_handlers = {
    global = {
      [THIRDREALITY_ACCELERATION_CLUSTER] = {
        [zcl_commands.ReportAttribute.ID] = multi_sensor_report_handler,
        [zcl_commands.ReadAttributeResponse.ID] = multi_sensor_report_handler
      }
    }
  },
  can_handle = function(opts, driver, device, ...)
    return device:get_manufacturer() == "Third Reality, Inc"
  end
}

return thirdreality_multi
