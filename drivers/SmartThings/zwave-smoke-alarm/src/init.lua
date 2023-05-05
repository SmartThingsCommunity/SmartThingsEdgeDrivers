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
local preferencesMap = require "preferences"

--- Update preference
---
--- @param device st.zwave.Device
--- @param args
local function update_preferences(self, device, args)
  local preferences = preferencesMap.get_device_parameters(device)
  for id, value in pairs(device.preferences) do
    if not (args and args.old_st_store) or (args.old_st_store.preferences[id] ~= value and preferences and preferences[id]) then
      local new_parameter_value = preferencesMap.to_numeric_value(device.preferences[id])
      device:send(Configuration:Set({parameter_number = preferences[id].parameter_number, size = preferences[id].size, configuration_value = new_parameter_value}))
    end
  end
end

--- Initialize device
---
--- @param self st.zwave.Driver
--- @param device st.zwave.Device
local device_init = function(self, device)
  device:set_update_preferences_fn(update_preferences)
end

--- Add device
---
--- @param self st.zwave.Driver
--- @param device st.zwave.Device
local device_added = function(self, device)
  -- if device:supports_capability_by_id("smokeDetector") then
  --   device:emit_event(capabilities.smokeDetector.smoke.clear())
  -- end
  -- if device:supports_capability_by_id("carbonMonoxideDetector") then
  --   device:emit_event(capabilities.carbonMonoxideDetector.carbonMonoxide.clear())
  -- end
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

local function do_configure(driver, device)
  update_preferences(driver, device)
end

local driver_template = {
  supported_capabilities = {
    capabilities.smokeDetector,
    capabilities.carbonMonoxideDetector,
    capabilities.battery,
    capabilities.tamperAlert,
    capabilities.temperatureAlarm,
    capabilities.temperatureMeasurement
  },
  sub_drivers = {
    require("zwave-smoke-co-alarm-v1"),
    require("zwave-smoke-co-alarm-v2"),
    require("fibaro-smoke-sensor")
  },
  lifecycle_handlers = {
    init = device_init,
    infoChanged = info_changed,
    doConfigure = do_configure,
    added = device_added
  }
}

defaults.register_for_default_handlers(driver_template, driver_template.supported_capabilities)
local detector = ZwaveDriver("zwave_smoke_co_detector", driver_template)
detector:run()
