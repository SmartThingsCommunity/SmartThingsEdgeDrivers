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

local cc = (require "st.zwave.CommandClass")
local Basic = (require "st.zwave.CommandClass.Basic")({ version=1 })
local SwitchMultilevel = (require "st.zwave.CommandClass.SwitchMultilevel")({version=3})

local WindowShadeDefaults = require "st.zwave.defaults.windowShade"
local WindowShadeLevelDefaults = require "st.zwave.defaults.windowShadeLevel"

local WINDOW_TREATMENT_VENETIAN_FINGERPRINTS = {
  {mfr = 0x010F, prod = 0x1D01, model = 0x1000}, -- Fibaro Walli Roller Shutter
  {mfr = 0x0159, prod = 0x0003, model = 0x0052}, -- Qubino Flush Shutter AC
  {mfr = 0x0159, prod = 0x0003, model = 0x0053}, -- Qubino Flush Shutter DC
}

local function can_handle_window_treatment_venetian(opts, driver, device, ...)
  for _, fingerprint in ipairs(WINDOW_TREATMENT_VENETIAN_FINGERPRINTS) do
    if device:id_match( fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      return true
    end
  end
  return false
end

local function shade_event_handler(self, device, cmd)
  WindowShadeDefaults.zwave_handlers[cc.SWITCH_MULTILEVEL][SwitchMultilevel.REPORT](self, device, cmd)
  WindowShadeLevelDefaults.zwave_handlers[cc.SWITCH_MULTILEVEL][SwitchMultilevel.REPORT](self, device, cmd)
end

local function endpoint_to_component(device, endpoint)
  if endpoint == 2 then
    return "venetianBlind"
  else
    return "main"
  end
end

local function component_to_endpoint(device, component)
  if component == "venetianBlind" then
    return {2}
  else
    return {}
  end
end

local function map_components(self, device)
  device:set_endpoint_to_component_fn(endpoint_to_component)
  device:set_component_to_endpoint_fn(component_to_endpoint)
end

local window_treatment_venetian = {
  NAME = "window treatment venetian",
  zwave_handlers = {
    [cc.BASIC] = {
      [Basic.REPORT] = shade_event_handler
    },
    [cc.SWITCH_MULTILEVEL] = {
      [SwitchMultilevel.REPORT] = shade_event_handler
    }
  },
  can_handle = can_handle_window_treatment_venetian,
  lifecycle_handlers = {
    init = map_components
  },
  sub_drivers = {
    require("window-treatment-venetian/fibaro-roller-shutter"),
    require("window-treatment-venetian/qubino-flush-shutter")
  }
}

return window_treatment_venetian
