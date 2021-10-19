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
--- @type st.zwave.defaults
local defaults = require "st.zwave.defaults"
--- @type st.zwave.CommandClass.Configuration
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version = 1 })

local EVERSPRING_ST814_FINGERPRINTS = {
  { manufacturerId = 0x0060, productType = 0x0006, productId = 0x0001 } -- Everspring ST814
}

--- Determine whether the passed device is everspring ST814
---
--- @param driver Driver driver instance
--- @param device Device device isntance
--- @return boolean true if the device proper, else false
local function can_handle_everspring_ST814_sensor(opts, driver, device, ...)
  for _, fingerprint in ipairs(EVERSPRING_ST814_FINGERPRINTS) do
    if device:id_match(fingerprint.manufacturerId, fingerprint.productType, fingerprint.productId) then
      return true
    end
  end
  return false
end

local function do_configure(self, device)
  device:send(Configuration:Set({parameter_number = 6, size = 2, configuration_value = 20})) -- Auto report time interval in minutes
  device:send(Configuration:Set({parameter_number = 7, size = 1, configuration_value = 2})) -- Auto report temperature change threshold
  device:send(Configuration:Set({parameter_number = 8, size = 1, configuration_value = 5})) -- Auto report humidity change threshold
end

local everspring_ST814_sensor = {
  lifecycle_handlers = {
    doConfigure = do_configure
  },
  NAME = "everspring ST814 sensor",
  can_handle = can_handle_everspring_ST814_sensor
}

return everspring_ST814_sensor
