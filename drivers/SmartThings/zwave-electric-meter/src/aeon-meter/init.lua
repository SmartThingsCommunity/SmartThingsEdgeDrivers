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

--- @type st.zwave.CommandClass.Configuration
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version=1 })

local AEON_FINGERPRINTS = {
  {mfr = 0x0086, prod = 0x0002, model = 0x0009},  -- DSB09xxx-ZWUS
  {mfr = 0x0086, prod = 0x0002, model = 0x0001},  -- DSB28-ZWEU
}

local function can_handle_aeon_meter(opts, driver, device, ...)
  for _, fingerprint in ipairs(AEON_FINGERPRINTS) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      return true
    end
  end
  return false
end

local do_configure = function (self, device)
  device:send(Configuration:Set({parameter_number = 101, size = 4, configuration_value = 4}))   -- combined power in watts...
  device:send(Configuration:Set({parameter_number = 111, size = 4, configuration_value = 300})) -- ...every 5 min
  device:send(Configuration:Set({parameter_number = 102, size = 4, configuration_value = 8}))   -- combined energy in kWh...
  device:send(Configuration:Set({parameter_number = 112, size = 4, configuration_value = 300})) -- ...every 5 min
  device:send(Configuration:Set({parameter_number = 103, size = 4, configuration_value = 0}))   -- no third report
end

local aeon_meter = {
  lifecycle_handlers = {
    doConfigure = do_configure
  },
  NAME = "aeon meter",
  can_handle = can_handle_aeon_meter
}

return aeon_meter
