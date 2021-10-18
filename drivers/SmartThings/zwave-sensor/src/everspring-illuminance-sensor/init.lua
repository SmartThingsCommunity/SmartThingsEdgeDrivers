-- Copyright 2021 SmartThings
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
--- @type st.zwave.CommandClass.Battery
local Battery = (require "st.zwave.CommandClass.Battery")({ version = 1 })
--- @type st.zwave.CommandClass.Configuration
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version = 1 })

local EVERSPRING_ILLUMINANCE_FINGERPRINTS = {
  { manufacturerId = 0x0060, productType = 0x0007, productId = 0x0001 } -- Everspring Illuminance Sensor
}

--- Determine whether the passed device is everspring_illuminance_sensor
---
--- @param driver Driver driver instance
--- @param device Device device isntance
--- @return boolean true if the device proper, else false
local function can_handle_everspring_illuminace_sensor(opts, driver, device, ...)
  for _, fingerprint in ipairs(EVERSPRING_ILLUMINANCE_FINGERPRINTS) do
    if device:id_match(fingerprint.manufacturerId, fingerprint.productType, fingerprint.productId) then
      return true
    end
  end
  return false
end

local function do_configure(self, device)
  -- Auto report time interval in minutes
  device:send(Configuration:Set({parameter_number = 5, size = 2, configuration_value = 20}))
  -- Auto report lux change threshold
  device:send(Configuration:Set({parameter_number = 6, size = 2, configuration_value = 30}))
end

local everspring_illuminance_sensor = {
  lifecycle_handlers = {
    doConfigure = do_configure
  },
  NAME = "everspring illuminance sensor",
  can_handle = can_handle_everspring_illuminace_sensor
}

return everspring_illuminance_sensor
