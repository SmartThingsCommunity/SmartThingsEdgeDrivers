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

local capabilities = require "st.capabilities"
local cc = require "st.zwave.CommandClass"
local Association = (require "st.zwave.CommandClass.Association")({ version=2 })
local Battery = (require "st.zwave.CommandClass.Battery")({ version = 1 })
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version=2 })
local SensorAlarm = (require "st.zwave.CommandClass.SensorAlarm")({ version = 1 })
local SensorBinary = (require "st.zwave.CommandClass.SensorBinary")({ version = 1 })
local configurationsMap = require "configurations"

local FIBARO_DOOR_WINDOW_SENSOR_1_FINGERPRINTS = {
  { manufacturerId = 0x010F, prod = 0x0501, productId = 0x1002 }
}

local function can_handle_fibaro_door_window_sensor_1(opts, driver, device, cmd, ...)
  for _, fingerprint in ipairs(FIBARO_DOOR_WINDOW_SENSOR_1_FINGERPRINTS) do
    if device:id_match( fingerprint.manufacturerId, fingerprint.productType, fingerprint.productId) then
      return true
    end
  end
  return false
end

local function sensor_alarm_report_handler(driver, device, cmd)
  if (cmd.args.sensor_state == SensorAlarm.sensor_state.ALARM) then
    device:emit_event(capabilities.tamperAlert.tamper.detected())
  elseif (cmd.args.sensor_state == SensorAlarm.sensor_state.NO_ALARM) then
    device:emit_event(capabilities.tamperAlert.tamper.clear())
  end
end

local function do_refresh(driver, device)
  device:send(Battery:Get({}))
  device:send(SensorAlarm:Get({}))
  device:send(SensorBinary:Get({}))
end

local function do_configure(driver, device)
  local configuration = configurationsMap.get_device_configuration(device)
  if configuration ~= nil then
    for _, value in ipairs(configuration) do
      device:send(Configuration:Set(value))
    end
  end
  local association = configurationsMap.get_device_association(device)
  if association ~= nil then
    for _, value in ipairs(association) do
      local _node_ids = value.node_ids or {driver.environment_info.hub_zwave_id}
      device:send(Association:Set({grouping_identifier = value.grouping_identifier, node_ids = _node_ids}))
    end
  end

  device:send(Association:Remove({grouping_identifier = 1, node_ids = driver.environment_info.hub_zwave_id}))
end

local function device_added(driver, device)
  do_refresh(driver, device)
  -- device:emit_event(capabilities.tamperAlert.tamper.clear())
  -- device:emit_event(capabilities.contactSensor.contact.open())
end


local fibaro_door_window_sensor_1 = {
  NAME = "fibaro door window sensor 1",
  lifecycle_handlers = {
    added = device_added,
    doConfigure = do_configure
  },
  zwave_handlers = {
    [cc.SENSOR_ALARM ] = {
      [SensorAlarm.REPORT] = sensor_alarm_report_handler
    }
  },
  [capabilities.refresh.ID] = {
    [capabilities.refresh.commands.refresh.NAME] = do_refresh
  },
  can_handle = can_handle_fibaro_door_window_sensor_1
}

return fibaro_door_window_sensor_1
