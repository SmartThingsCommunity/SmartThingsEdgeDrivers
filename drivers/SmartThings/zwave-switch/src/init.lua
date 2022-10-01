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
--- @type st.zwave.defaults
local defaults = require "st.zwave.defaults"
--- @type st.zwave.Driver
local ZwaveDriver = require "st.zwave.driver"
--- @type st.zwave.CommandClass.Configuration
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version=4 })
local preferencesMap = require "preferences"
local configurationsMap = require "configurations"

--- Map component to end_points(channels)
---
--- @param device st.zwave.Device
--- @param component_id string ID
--- @return table dst_channels destination channels e.g. {2} for Z-Wave channel 2 or {} for unencapsulated
local function component_to_endpoint(device, component_id)
  local ep_num = component_id:match("switch(%d)")
  return { ep_num and tonumber(ep_num) }
end

--- Map end_point(channel) to Z-Wave endpoint 9 channel)
---
--- @param device st.zwave.Device
--- @param ep number the endpoint(Z-Wave channel) ID to find the component for
--- @return string the component ID the endpoint matches to
local function endpoint_to_component(device, ep)
  local switch_comp = string.format("switch%d", ep)
  if device.profile.components[switch_comp] ~= nil then
    return switch_comp
  else
    return "main"
  end
end

--- Initialize device
---
--- @param self st.zwave.Driver
--- @param device st.zwave.Device
local device_init = function(self, device)
  device:set_component_to_endpoint_fn(component_to_endpoint)
  device:set_endpoint_to_component_fn(endpoint_to_component)
end

--- Handle preference changes
---
--- @param driver st.zwave.Driver
--- @param device st.zwave.Device
--- @param event table
--- @param args
local function info_changed(driver, device, event, args)
  local preferences = preferencesMap.get_device_parameters(device)
  for id, value in pairs(device.preferences) do
    if args.old_st_store.preferences[id] ~= value and preferences and preferences[id] then
      local new_parameter_value = preferencesMap.to_numeric_value(device.preferences[id])
      if preferences[id].size == 2 and new_parameter_value > 32767 and new_parameter_value < 65536 then
        new_parameter_value = new_parameter_value - 65536
      elseif preferences[id].size == 1 and new_parameter_value > 127 and new_parameter_value < 256 then
        new_parameter_value = new_parameter_value - 256
      end
      device:send(Configuration:Set({parameter_number = preferences[id].parameter_number, size = preferences[id].size, configuration_value = new_parameter_value}))
    end
  end
end

--- Configure device
---
--- @param driver st.zwave.Driver
--- @param device st.zwave.Device
local function do_configure(driver, device)
  local configuration = configurationsMap.get_device_configuration(device)
  if configuration ~= nil then
    for _, value in ipairs(configuration) do
      device:send(Configuration:Set({parameter_number = value.parameter_number, size = value.size, configuration_value = value.configuration_value}))
    end
  end
end

local function device_added(driver, device)
  device:refresh()
end

-------------------------------------------------------------------------------------------
-- Register message handlers and run driver
-------------------------------------------------------------------------------------------
local driver_template = {
  supported_capabilities = {
    capabilities.switch,
    capabilities.switchLevel,
    capabilities.battery,
    capabilities.energyMeter,
    capabilities.powerMeter,
    capabilities.colorControl,
    capabilities.button,
    capabilities.temperatureMeasurement,
    capabilities.relativeHumidityMeasurement
  },
  sub_drivers = {
    require("eaton-accessory-dimmer"),
    require("inovelli-LED"),
    require("dawon-smart-plug"),
    require("inovelli-2-channel-smart-plug"),
    require("zwave-dual-switch"),
    require("eaton-anyplace-switch"),
    require("fibaro-wall-plug-us"),
    require("dawon-wall-smart-switch"),
    require("zooz-power-strip"),
    require("aeon-smart-strip"),
    require("qubino-switches"),
    require("fibaro-double-switch"),
    require("fibaro-single-switch"),
    require("eaton-5-scene-keypad"),
    require("ecolink-switch"),
    require("zooz-zen-30-dimmer-relay")
  },
  lifecycle_handlers = {
    init = device_init,
    infoChanged = info_changed,
    doConfigure = do_configure,
    added = device_added
  }
}

defaults.register_for_default_handlers(driver_template, driver_template.supported_capabilities)
--- @type st.zwave.Driver
local switch = ZwaveDriver("zwave_switch", driver_template)
switch:run()
