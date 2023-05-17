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
--- @type st.zwave.CommandClass.Battery
local Battery = (require "st.zwave.CommandClass.Battery")({ version=1 })
--- @type st.zwave.CommandClass.SensorMultilevel
local SensorMultilevel = (require "st.zwave.CommandClass.SensorMultilevel")({ version=5 })
--- @type st.zwave.CommandClass.WakeUp
local WakeUp = (require "st.zwave.CommandClass.WakeUp")({version=1})

local FIBARO_SMOKE_SENSOR_WAKEUP_INTERVAL = 21600 --seconds

local FIBARO_SMOKE_SENSOR_FINGERPRINTS = {
  { manufacturerId = 0x010F, productType = 0x0C02, productId = 0x1002 }, -- Fibaro Smoke Sensor
  { manufacturerId = 0x010F, productType = 0x0C02, productId = 0x1003 }, -- Fibaro Smoke Sensor
  { manufacturerId = 0x010F, productType = 0x0C02, productId = 0x3002 }, -- Fibaro Smoke Sensor
  { manufacturerId = 0x010F, productType = 0x0C02, productId = 0x4002 } -- Fibaro Smoke Sensor
}

--- Determine whether the passed device is fibaro smoke sensro
---
--- @param driver st.zwave.Driver
--- @param device st.zwave.Device
--- @return boolean true if the device is fibaro smoke sensor
local function can_handle_fibaro_smoke_sensor(opts, driver, device, cmd, ...)
  for _, fingerprint in ipairs(FIBARO_SMOKE_SENSOR_FINGERPRINTS) do
    if device:id_match( fingerprint.manufacturerId, fingerprint.productType, fingerprint.productId) then
      return true
    end
  end
  return false
end

local function device_added(self, device)
  device:send(WakeUp:IntervalSet({node_id = self.environment_info.hub_zwave_id, seconds = FIBARO_SMOKE_SENSOR_WAKEUP_INTERVAL}))
  -- device:emit_event(capabilities.smokeDetector.smoke.clear())
  -- device:emit_event(capabilities.tamperAlert.tamper.clear())
  -- device:emit_event(capabilities.temperatureAlarm.temperatureAlarm.cleared())
  device:send(Battery:Get({}))
  device:send(SensorMultilevel:Get({sensor_type = SensorMultilevel.sensor_type.TEMPERATURE}))
end

local function wakeup_notification_handler(self, device, cmd)
  device:emit_event(capabilities.smokeDetector.smoke.clear())
  device:send(Battery:Get({}))
  device:send(SensorMultilevel:Get({sensor_type = SensorMultilevel.sensor_type.TEMPERATURE}))
end

local fibaro_smoke_sensor = {
  zwave_handlers = {
    [cc.WAKE_UP] = {
      [WakeUp.NOTIFICATION] = wakeup_notification_handler
    }
  },
  lifecycle_handlers = {
    added = device_added
  },
  NAME = "fibaro smoke sensor",
  can_handle = can_handle_fibaro_smoke_sensor,
}

return fibaro_smoke_sensor
