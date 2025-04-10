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

-- @type st.zwave.CommandClass.Configuration
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version=4 })
-- @type st.zwave.CommandClass.Association
local Association = (require "st.zwave.CommandClass.Association")({ version=2 })

local SHELLY_WAVE_i4_FINGERPRINTS = {
  {mfr = 0x0460, prod = 0x0009, model = 0x0081}, -- Shelly Wave i4
  {mfr = 0x0460, prod = 0x0009, model = 0x0082}  -- Shelly Wave i4 DC
}

local function can_handle_shelly_wave_i4(opts, driver, device, ...)
  for _, fingerprint in ipairs(SHELLY_WAVE_i4_FINGERPRINTS) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      return true
    end
  end
  return false
end

local do_configure = function(self, device)
  device:refresh()
  device:send(Configuration:Set({ configuration_value = 0, parameter_number = 1, size = 1 }))
  device:send(Configuration:Set({ configuration_value = 0, parameter_number = 2, size = 1 }))
  device:send(Configuration:Set({ configuration_value = 0, parameter_number = 3, size = 1 }))
  device:send(Configuration:Set({ configuration_value = 0, parameter_number = 4, size = 1 }))
  device:send(Association:Set({grouping_identifier = 1, node_ids = {self.environment_info.hub_zwave_id}}))
end

local shelly_wave_i4 = {
  NAME = "Shelly Wave i4",
  lifecycle_handlers = {
    doConfigure = do_configure
  },
  can_handle = can_handle_shelly_wave_i4,
}

return shelly_wave_i4