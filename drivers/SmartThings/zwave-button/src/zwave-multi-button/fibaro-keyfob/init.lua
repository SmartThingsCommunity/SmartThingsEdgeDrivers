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
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version = 4 })

local ZWAVE_FIBARO_KEYFOB_FINGERPRINTS = {
  {mfr = 0x010F, prod = 0x1001, model = 0x1000}, -- Fibaro KeyFob EU
  {mfr = 0x010F, prod = 0x1001, model = 0x2000}, -- Fibaro KeyFob US
  {mfr = 0x010F, prod = 0x1001, model = 0x3000} -- Fibaro KeyFob AU
}

local function can_handle_fibaro_keyfob(opts, driver, device, ...)
  for _, fingerprint in ipairs(ZWAVE_FIBARO_KEYFOB_FINGERPRINTS) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      return true
    end
  end
  return false
end

local function do_configure(self, device)
  device:refresh()
  --configuration value : 1 (pressed), 2(double), 4(pushed_3x), 8(held & down_hold)
  device:send(Configuration:Set({ configuration_value = 15, parameter_number = 21, size = 1 }))
  device:send(Configuration:Set({ configuration_value = 15, parameter_number = 22, size = 1 }))
  device:send(Configuration:Set({ configuration_value = 15, parameter_number = 23, size = 1 }))
  device:send(Configuration:Set({ configuration_value = 15, parameter_number = 24, size = 1 }))
  device:send(Configuration:Set({ configuration_value = 15, parameter_number = 25, size = 1 }))
  device:send(Configuration:Set({ configuration_value = 15, parameter_number = 26, size = 1 }))
end

local fibaro_keyfob = {
  NAME = "Fibaro keyfob",
  lifecycle_handlers = {
    doConfigure = do_configure
  },
  can_handle = can_handle_fibaro_keyfob,
}

return fibaro_keyfob
