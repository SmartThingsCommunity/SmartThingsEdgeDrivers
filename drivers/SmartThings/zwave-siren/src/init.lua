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
-- local cap_defaults = require "st.capabilities.defaults"
--- @type st.zwave.defaults
local defaults = require "st.zwave.defaults"
--- @type st.zwave.Driver
local ZwaveDriver = require "st.zwave.driver"
local configurationsMap = require "configurations"
local preferencesMap = require "preferences"
local Basic = (require "st.zwave.CommandClass.Basic")({version=1})
local Configuration = (require "st.zwave.CommandClass.Configuration")({version=1})

--- Handle preference changes
---
--- @param driver st.zwave.Driver
--- @param device st.zwave.Device
--- @param event table
--- @param args
local function info_changed(driver, device, event, args)
  local preferences = preferencesMap.get_device_parameters(device)

  if preferences then
    local did_configuration_change = false
    for id, value in pairs(device.preferences) do
      if args.old_st_store.preferences[id] ~= value and preferences[id] then
        local new_parameter_value = preferencesMap.to_numeric_value(device.preferences[id])
        device:send(Configuration:Set({parameter_number = preferences[id].parameter_number, size = preferences[id].size, configuration_value = new_parameter_value}))
        did_configuration_change = true
      end
    end

    if did_configuration_change then
      local delayed_command = function()
        device:send(Basic:Set({value=0x00}))
      end
      device.thread:call_with_delay(1, delayed_command)
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

    local delayed_command = function()
      device:send(Basic:Set({value=0x00}))
    end
    device.thread:call_with_delay(1, delayed_command)
  end
end

--- Handle device added
---
--- @param self st.zwave.Driver
--- @param device st.zwave.Device
local function added_handler(self, device)
  -- cap_defaults.emit_default_events(device, self.supported_capabilities)
end

--------------------------------------------------------------------------------------------
-- Register message handlers and run driver
--------------------------------------------------------------------------------------------

local driver_template = {
  supported_capabilities = {
    capabilities.alarm,
    capabilities.battery,
    capabilities.soundSensor,
    capabilities.switch,
    capabilities.tamperAlert,
    capabilities.temperatureMeasurement,
    capabilities.relativeHumidityMeasurement,
    capabilities.chime
  },
  sub_drivers = {
    require("multifunctional-siren"),
    require("zwave-sound-sensor"),
    require("ecolink-wireless-siren"),
    require("philio-sound-siren"),
    require("aeotec-doorbell-siren"),
    require("aeon-siren"),
    require("yale-siren"),
    require("zipato-siren"),
    require("utilitech-siren"),
    require("fortrezz")
  },
  lifecycle_handlers = {
    infoChanged = info_changed,
    doConfigure = do_configure,
    added = added_handler
  }
}

defaults.register_for_default_handlers(driver_template, driver_template.supported_capabilities)
--- @type st.zwave.Driver
local siren = ZwaveDriver("zwave_siren", driver_template)
siren:run()
