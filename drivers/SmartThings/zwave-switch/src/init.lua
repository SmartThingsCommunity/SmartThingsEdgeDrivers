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
--- @type st.Device
local st_device = require "st.device"
--- @type st.zwave.Driver
local ZwaveDriver = require "st.zwave.driver"
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.Configuration
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version = 4 })
--- @type st.zwave.CommandClass.SwitchMultilevel
local SwitchMultilevel = (require "st.zwave.CommandClass.SwitchMultilevel")({ version = 4 })
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
  if device.network_type == st_device.NETWORK_TYPE_ZWAVE then
    device:set_component_to_endpoint_fn(component_to_endpoint)
    device:set_endpoint_to_component_fn(endpoint_to_component)
  end
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
      device:send(Configuration:Set({ parameter_number = preferences[id].parameter_number, size = preferences[id].size, configuration_value = new_parameter_value }))
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
      device:send(Configuration:Set({ parameter_number = value.parameter_number, size = value.size, configuration_value = value.configuration_value }))
    end
  end
end

local function device_added(driver, device)
  device:refresh()
end

-- This functionality was present in "Z-Wave Dimmer Switch Generic" and, while non-standard,
-- appears to be important for some devices.
local function switch_multilevel_stop_level_change_handler(driver, device, cmd)
  device:emit_event_for_endpoint(cmd.src_channel, capabilities.switch.switch.on())
  device:send(SwitchMultilevel:Get({}))
end

local function lazy_load_if_possible(sub_driver_name)
  -- gets the current lua libs api version
  local version = require "version"

  -- version 9 will include the lazy loading functions
  if version.api >= 9 then
    return ZwaveDriver.lazy_load_sub_driver(require(sub_driver_name))
  else
    return require(sub_driver_name)
  end

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
    capabilities.relativeHumidityMeasurement,
    capabilities.illuminanceMeasurement,
    capabilities.contactSensor,
    capabilities.motionSensor,
    capabilities.smokeDetector,
    capabilities.waterSensor,
    capabilities.zwMultichannel
  },
  zwave_handlers = {
    [cc.SWITCH_MULTILEVEL] = {
      [SwitchMultilevel.STOP_LEVEL_CHANGE] = switch_multilevel_stop_level_change_handler
    }
  },
  sub_drivers = {
    lazy_load_if_possible("eaton-accessory-dimmer"),
    lazy_load_if_possible("inovelli-LED"),
    lazy_load_if_possible("dawon-smart-plug"),
    lazy_load_if_possible("inovelli-2-channel-smart-plug"),
    lazy_load_if_possible("zwave-dual-switch"),
    lazy_load_if_possible("eaton-anyplace-switch"),
    lazy_load_if_possible("fibaro-wall-plug-us"),
    lazy_load_if_possible("dawon-wall-smart-switch"),
    lazy_load_if_possible("zooz-power-strip"),
    lazy_load_if_possible("aeon-smart-strip"),
    lazy_load_if_possible("qubino-switches"),
    lazy_load_if_possible("fibaro-double-switch"),
    lazy_load_if_possible("fibaro-single-switch"),
    lazy_load_if_possible("eaton-5-scene-keypad"),
    lazy_load_if_possible("ecolink-switch"),
    lazy_load_if_possible("multi-metering-switch"),
    lazy_load_if_possible("zooz-zen-30-dimmer-relay"),
    lazy_load_if_possible("multichannel-device"),
    lazy_load_if_possible("aeotec-smart-switch")
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
