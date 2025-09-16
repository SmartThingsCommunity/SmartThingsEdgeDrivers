-- Copyright 2025 SmartThings
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

local defaults = require "st.zigbee.defaults"
local capabilities = require "st.capabilities"

local is_motion_illuminance = function(opts, driver, device)
  if device:supports_capability(capabilities.motionSensor) and device:supports_capability(capabilities.illuminanceMeasurement) then
    return true
  end
end

local generic_motion_illuminance = {
  NAME = "Generic Motion illuminance",
  supported_capabilities = {
    capabilities.illuminanceMeasurement,
    capabilities.motionSensor
  },
  can_handle = is_motion_illuminance
}
defaults.register_for_default_handlers(generic_motion_illuminance, generic_motion_illuminance.supported_capabilities)
return generic_motion_illuminance
