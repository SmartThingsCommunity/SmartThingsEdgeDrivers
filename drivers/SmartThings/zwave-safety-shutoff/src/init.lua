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

local preferences = require "preferences"

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

--- Handle preference changes
---
--- @param driver st.zwave.Driver
--- @param device st.zwave.Device
--- @param event table
--- @param args
local function info_changed(self, device, event, args)
  preferences.update_preferences(self, device, args)
end

local function device_init(self, device)
  device:set_update_preferences_fn(preferences.update_preferences)
end

local function do_configure(driver, device)
  device:refresh()
  preferences.update_preferences(driver, device)
end

local initial_events_map = {
  [capabilities.soundDetection.ID] = capabilities.soundDetection.soundDetected.noSound(),
}

local function added_handler(self, device)
  for id, event in pairs(initial_events_map) do
    if device:supports_capability_by_id(id) then
      device:emit_event(event)
    end
  end
end

local driver_template = {
  supported_capabilities = {
    capabilities.soundDetection
  },
  sub_drivers = {
    lazy_load_if_possible("fireavert-appliance-shutoff-gas"),
    lazy_load_if_possible("fireavert-appliance-shutoff-electric"),
  },
  lifecycle_handlers = {
    added = added_handler,
    init = device_init,
    infoChanged = info_changed,
    doConfigure = do_configure
  },
}

defaults.register_for_default_handlers(driver_template,
  driver_template.supported_capabilities,
  {native_capability_attrs_enabled = true})
--- @type st.zwave.Driver
local safety_shutoff = ZwaveDriver("zwave_appliance_safety", driver_template)
safety_shutoff:run()
