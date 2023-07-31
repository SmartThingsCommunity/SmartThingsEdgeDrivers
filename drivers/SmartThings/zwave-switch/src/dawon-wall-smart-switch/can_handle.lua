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
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.Basic
local Basic = (require "st.zwave.CommandClass.Basic")({ version = 1 })
--- @type st.zwave.CommandClass.Configuration
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version = 4 })
--- @type st.zwave.CommandClass.Notification
local Notification = (require "st.zwave.CommandClass.Notification")({ version = 3 })
--- @type st.zwave.CommandClass.SensorMultilevel
local SensorMultilevel = (require "st.zwave.CommandClass.SensorMultilevel")({ version = 5 })

local DAWON_WALL_SMART_SWITCH_FINGERPRINTS = {
  {mfr = 0x018C, prod = 0x0061, model = 0x0001}, -- Dawon Multipurpose Sensor + Smart Switch endpoint 1 KR
  {mfr = 0x018C, prod = 0x0062, model = 0x0001}, -- Dawon Multipurpose Sensor + Smart Switch endpoint 2 KR
  {mfr = 0x018C, prod = 0x0063, model = 0x0001}, -- Dawon Multipurpose Sensor + Smart Switch endpoint 3 KR
  {mfr = 0x018C, prod = 0x0064, model = 0x0001}, -- Dawon Multipurpose Sensor + Smart Switch endpoint 1 US
  {mfr = 0x018C, prod = 0x0065, model = 0x0001}, -- Dawon Multipurpose Sensor + Smart Switch endpoint 2 US
  {mfr = 0x018C, prod = 0x0066, model = 0x0001} -- Dawon Multipurpose Sensor + Smart Switch endpoint 3 US
}

--- Determine whether the passed device is Dawon wall smart switch
---
--- @param driver Driver driver instance
--- @param device Device device isntance
--- @return boolean true if the device proper, else false
local function can_handle_dawon_wall_smart_switch(opts, driver, device, ...)
  for _, fingerprint in ipairs(DAWON_WALL_SMART_SWITCH_FINGERPRINTS) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      local subdriver = require("dawon-wall-smart-switch")
      return true, subdriver
    end
  end
  return false
end

local dawon_wall_smart_switch = {
  NAME = "Dawon Wall Smart Switch",
  can_handle = can_handle_dawon_wall_smart_switch
}

return dawon_wall_smart_switch
