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
local cc = (require "st.zwave.CommandClass")
--- @type st.zwave.defaults
local defaults = require "st.zwave.defaults"
--- @type st.zwave.Driver
local ZwaveDriver = require "st.zwave.driver"
local Basic = (require "st.zwave.CommandClass.Basic")({version = 1})
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({version = 1})

local function do_refresh(self, device)
  device:send(SwitchBinary:Get({}))
end

local function device_added(self, device)
  do_refresh(self,device)
end

local function info_changed(self, device, event, args)
  do_refresh(self,device)
end

local function switch_off(driver, device)
  device:send(Basic:Set({value = SwitchBinary.value.OFF_DISABLE}))
  device:send(SwitchBinary:Get({}))
end

local function momentary_switch_on(driver, device)
  device:send(Basic:Set({value = SwitchBinary.value.ON_ENABLE}))
  device:send(SwitchBinary:Get({}))
  driver:call_with_delay(3, function() switch_off(driver, device) end)
end

-------------------------------------------------------------------------------------------
-- Register message handlers and run driver
-------------------------------------------------------------------------------------------
local driver_template = {
  supported_capabilities = {
    capabilities.momentary,
    capabilities.switch,
    capabilities.refresh
  },
  capability_handlers = {
    [capabilities.momentary.ID] = {
      [capabilities.momentary.commands.push.NAME] = momentary_switch_on
    },
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = momentary_switch_on,
      [capabilities.switch.commands.off.NAME] = switch_off
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh
    }
  },
  lifecycle_handlers = {
    added = device_added,
    infoChanged = info_changed
  }
}

defaults.register_for_default_handlers(driver_template, driver_template.supported_capabilities)
--- @type st.zwave.Driver
local switch = ZwaveDriver("zwave_virtual_momentary_switch", driver_template)
switch:run()
