-- Copyright 2023 SmartThings
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
--- @type st.zwave.CommandClass.WakeUp
local WakeUp = (require "st.zwave.CommandClass.WakeUp")({ version = 1 })
--- @type st.zwave.CommandClass.SensorBinary
local SensorBinary = (require "st.zwave.CommandClass.SensorBinary")({version = 2})
--- @type st.zwave.CommandClass.Battery
local Battery = (require "st.zwave.CommandClass.Battery")({ version = 1 })

local fingerprint = {manufacturerId = 0x014F, productType = 0x2001, productId = 0x0102} -- NorTek open/close sensor

local function can_handle(opts, driver, device, ...)
  return device:id_match(fingerprint.manufacturerId, fingerprint.productType, fingerprint.productId)
end

-- Nortek open/closed sensors _always_ respond with "open" when polled, and they are polled after wakeup
local function wakeup_notification(driver, device, cmd)
  --Note sending WakeUpIntervalGet the first time a device wakes up will happen by default in Lua libs 0.49.x and higher
  --This is done to help the hub correctly set the checkInterval for migrated devices.
  if not device:get_field("__wakeup_interval_get_sent") then
    device:send(WakeUp:IntervalGetV1({}))
    device:set_field("__wakeup_interval_get_sent", true)
  end
  if device:get_latest_state("main", capabilities.contactSensor.ID, capabilities.contactSensor.contact.NAME) == nil then
    device:send(SensorBinary:Get({sensor_type = SensorBinary.sensor_type.DOOR_WINDOW}))
  end
  device:send(Battery:Get({}))
end

local wakeup_no_poll = {
  NAME = "wakeup no poll",
  zwave_handlers = {
    [cc.WAKE_UP] = {
      [WakeUp.NOTIFICATION] = wakeup_notification
    }
  },
  can_handle = can_handle
}

return wakeup_no_poll