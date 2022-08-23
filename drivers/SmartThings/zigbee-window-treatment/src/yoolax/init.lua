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
local zcl_clusters = require "st.zigbee.zcl.clusters"
local window_shade_defaults = require "st.zigbee.defaults.windowShade_defaults"
local WindowCovering = zcl_clusters.WindowCovering

local YOOLAX_WINDOW_SHADE_FINGERPRINTS = {
    { mfr = "Yookee", model = "D10110" },                                 -- Yookee Window Treatment
    { mfr = "yooksmart", model = "D10110" }                               -- yooksmart Window Treatment
}

local is_yoolax_window_shade = function(opts, driver, device)
  for _, fingerprint in ipairs(YOOLAX_WINDOW_SHADE_FINGERPRINTS) do
      if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
          return true
      end
  end
  return false
end

local set_window_shade_level = function(level)
  return function(driver, device, cmd)
    device:send_to_component(cmd.component, WindowCovering.server.commands.GoToLiftPercentage(device, level))
  end
end

local yoolax_window_shade = {
  NAME = "yoolax window shade",
  capability_handlers = {
    [capabilities.windowShade.ID] = {
      [capabilities.windowShade.commands.open.NAME] = set_window_shade_level(100),
      [capabilities.windowShade.commands.close.NAME] = set_window_shade_level(0),
    }
  },
  can_handle = is_yoolax_window_shade
}

return yoolax_window_shade
