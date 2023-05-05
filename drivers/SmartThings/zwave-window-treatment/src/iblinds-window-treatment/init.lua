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
--- @type st.zwave.CommandClass.SwitchMultilevel
local SwitchMultilevel = (require "st.zwave.CommandClass.SwitchMultilevel")({ version=3 })

local IBLINDS_WINDOW_TREATMENT_FINGERPRINTS = {
  {mfr = 0x0287, prod = 0x0003, model = 0x000D}, -- iBlinds Window Treatment v1 / v2
  {mfr = 0x0287, prod = 0x0004, model = 0x0071}, -- iBlinds Window Treatment v3
  {mfr = 0x0287, prod = 0x0004, model = 0x0072}  -- iBlinds Window Treatment v3.1
}

--- Determine whether the passed device is iblinds window treatment
---
--- @param driver st.zwave.Driver
--- @param device st.zwave.Device
--- @return boolean true if the device is iblinds window treatment, else false
local function can_handle_iblinds_window_treatment(opts, driver, device, ...)
  for _, fingerprint in ipairs(IBLINDS_WINDOW_TREATMENT_FINGERPRINTS) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      return true
    end
  end
  return false
end

local capability_handlers = {}

function capability_handlers.open(driver, device)
  local value = device.preferences.defaultOnValue or 50
  device:emit_event(capabilities.windowShade.windowShade.open())
  device:emit_event(capabilities.windowShadeLevel.shadeLevel(value))
  device:send(SwitchMultilevel:Set({value = value}))
end

function capability_handlers.close(driver, device)
  local value = device.preferences.reverse and 99 or 0
  device:emit_event(capabilities.windowShade.windowShade.closed())
  device:emit_event(capabilities.windowShadeLevel.shadeLevel(value))
  device:send(SwitchMultilevel:Set({value = value}))
end

local function set_shade_level_helper(driver, device, value)
  value = math.max(math.min(value, 99), 0)
  value = device.preferences.reverse and 99 - value or value
  if value == 0 or value == 99 then
    device:emit_event(capabilities.windowShade.windowShade.closed())
  elseif value == 50 then
    device:emit_event(capabilities.windowShade.windowShade.open())
  else
    device:emit_event(capabilities.windowShade.windowShade.partially_open())
  end
  device:emit_event(capabilities.windowShadeLevel.shadeLevel(value))
  device:send(SwitchMultilevel:Set({value = value}))
end

function capability_handlers.set_shade_level(driver, device, command)
  set_shade_level_helper(driver, device, command.args.shadeLevel)
end

function capability_handlers.preset_position(driver, device)
  set_shade_level_helper(driver, device, device.preferences.presetPosition or 50)
end

local iblinds_window_treatment = {
  capability_handlers = {
    [capabilities.windowShade.ID] = {
      [capabilities.windowShade.commands.open.NAME] = capability_handlers.open,
      [capabilities.windowShade.commands.close.NAME] = capability_handlers.close
    },
    [capabilities.windowShadeLevel.ID] = {
      [capabilities.windowShadeLevel.commands.setShadeLevel.NAME] = capability_handlers.set_shade_level
    },
    [capabilities.windowShadePreset.ID] = {
      [capabilities.windowShadePreset.commands.presetPosition.NAME] = capability_handlers.preset_position
    }
  },
  sub_drivers = {
    require("iblinds-window-treatment.v3")
  },
  NAME = "iBlinds window treatment",
  can_handle = can_handle_iblinds_window_treatment
}

return iblinds_window_treatment
