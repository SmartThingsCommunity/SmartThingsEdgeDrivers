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
--- @type st.zwave.CommandClass.WakeUp
local WakeUp = (require "st.zwave.CommandClass.WakeUp")({ version = 1 })

local HOMESEER_MULTI_SENSOR_FINGERPRINTS = {
  { manufacturerId = 0x001E, productType = 0x0002, productId = 0x0001 }, -- Homeseer multi sensor HSM100
}

--- Determine whether the passed device is homeseer multi sensor
---
--- @param driver Driver driver instance
--- @param device Device device instance
--- @return boolean true if the device proper, else false
local function can_handle_homeseer_multi_sensor(opts, driver, device, ...)
  for _, fingerprint in ipairs(HOMESEER_MULTI_SENSOR_FINGERPRINTS) do
    if device:id_match(fingerprint.manufacturerId, fingerprint.productType, fingerprint.productId) then
      return true
    end
  end
  return false
end

local function basic_set_handler(self, device, cmd)
  if cmd.args.value ~= nil then
    device:emit_event(cmd.args.value == 0xFF and capabilities.motionSensor.motion.active() or capabilities.motionSensor.motion.inactive())
  end
end

local function added_handler(self, device)
  device:send(WakeUp:IntervalSet({node_id = self.environment_info.hub_zwave_id, seconds = 1200}))
end

local function update_preferences(self, device, args)
  if args.old_st_store.preferences.reportingInterval ~= device.preferences.reportingInterval then
    device:send(WakeUp:IntervalSet({node_id = self.environment_info.hub_zwave_id, seconds = device.preferences.reportingInterval * 60}))
  end
end

local function device_init(self, device)
  device:set_update_preferences_fn(update_preferences)
end

local function info_changed(self, device, event, args)
end

local homeseer_multi_sensor = {
  zwave_handlers = {
    [cc.BASIC] = {
      [Basic.SET] = basic_set_handler
    }
  },
  lifecycle_handlers = {
    added = added_handler,
    init = device_init,
    infoChanged = info_changed
  },
  NAME = "homeseer multi sensor",
  can_handle = can_handle_homeseer_multi_sensor
}

return homeseer_multi_sensor
