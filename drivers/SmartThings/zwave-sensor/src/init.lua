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
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.Driver
local ZwaveDriver = require "st.zwave.driver"
--- @type st.zwave.defaults
local defaults = require "st.zwave.defaults"
--- @type st.zwave.CommandClass.Configuration
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version=4 })
--- @type st.zwave.CommandClass.Association
local Association = (require "st.zwave.CommandClass.Association")({ version=2 })
--- @type st.zwave.CommandClass.Notification
local Notification = (require "st.zwave.CommandClass.Notification")({ version=3 })
--- @type st.zwave.CommandClass.WakeUp
local WakeUp = (require "st.zwave.CommandClass.WakeUp")({ version = 2 })
local preferencesMap = require "preferences"
local configurationsMap = require "configurations"

local function initial_configuration(driver, device)
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
  local notification = configurationsMap.get_device_notification(device)
  if notification ~= nil then
    for _, value in ipairs(notification) do
      device:send(Notification:Set(value))
    end
  end
  local wake_up = configurationsMap.get_device_wake_up(device)
  if wake_up ~= nil then
    for _, value in ipairs(wake_up) do
      local _node_id = value.node_id or driver.environment_info.hub_zwave_id
      device:send(WakeUp:IntervalSet({seconds = value.seconds, node_id = _node_id}))
    end
  end
end

local function update_preferences(driver, device, args)
  local preferences = preferencesMap.get_device_parameters(device)
  for id, value in pairs(device.preferences) do
    if not (args and args.old_st_store) or (args.old_st_store.preferences[id] ~= value and preferences and preferences[id]) then
      local new_parameter_value = preferencesMap.to_numeric_value(device.preferences[id])
      device:send(Configuration:Set({parameter_number = preferences[id].parameter_number, size = preferences[id].size, configuration_value = new_parameter_value}))
    end
  end
end

--- Handle preference changes
---
--- @param driver st.zwave.Driver
--- @param device st.zwave.Device
--- @param event table
--- @param args
local function info_changed(self, device, event, args)
  if not device:is_cc_supported(cc.WAKE_UP) then
    update_preferences(self, device, args)
  end
end

local function device_init(self, device)
  device:set_update_preferences_fn(update_preferences)
end

local function do_configure(driver, device)
  initial_configuration(driver, device)
  device:refresh()
  if not device:is_cc_supported(cc.WAKE_UP) then
    update_preferences(driver, device)
  end
end

local function added_handler(self, device)
  if device:supports_capability_by_id(capabilities.tamperAlert.ID) then
    device:emit_event(capabilities.tamperAlert.tamper.clear())
  end
  if device:supports_capability_by_id(capabilities.waterSensor.ID) then
    device:emit_event(capabilities.waterSensor.water.dry())
  end
  if device:supports_capability_by_id(capabilities.moldHealthConcern.ID) then
    device:emit_event(capabilities.moldHealthConcern.moldHealthConcern.good())
  end
end

local driver_template = {
  supported_capabilities = {
    capabilities.waterSensor,
    capabilities.colorControl,
    capabilities.contactSensor,
    capabilities.motionSensor,
    capabilities.relativeHumidityMeasurement,
    capabilities.illuminanceMeasurement,
    capabilities.battery,
    capabilities.tamperAlert,
    capabilities.temperatureAlarm,
    capabilities.temperatureMeasurement,
    capabilities.switch,
    capabilities.moldHealthConcern,
    capabilities.dewPoint,
    capabilities.ultravioletIndex,
    capabilities.accelerationSensor,
    capabilities.threeAxis
  },
  sub_drivers = {
    require("zooz-4-in-1-sensor"),
    require("vision-motion-detector"),
    require("fibaro-flood-sensor"),
    require("zwave-water-temp-humidity-sensor"),
    require("glentronics-water-leak-sensor"),
    require("homeseer-multi-sensor"),
    require("fibaro-door-window-sensor"),
    require("sensative-strip"),
    require("enerwave-motion-sensor"),
    require("aeotec-multisensor"),
    require("zwave-water-leak-sensor")
  },
  lifecycle_handlers = {
    added = added_handler,
    init = device_init,
    infoChanged = info_changed,
    doConfigure = do_configure
  },
}

defaults.register_for_default_handlers(driver_template, driver_template.supported_capabilities)
--- @type st.zwave.Driver
local sensor = ZwaveDriver("zwave_sensor", driver_template)
sensor:run()
