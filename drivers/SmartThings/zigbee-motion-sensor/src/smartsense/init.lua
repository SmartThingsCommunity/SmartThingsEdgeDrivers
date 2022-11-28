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
local utils = require "st.utils"

local motion = capabilities.motionSensor.motion
local signalStrength = capabilities.signalStrength

local SMARTSENSE_MFR = "SmartThings"
local SMARTSENSE_MODEL = "PGC314"
local SMARTSENSE_PROFILE_ID = 0xFC01
local SMARTSENSE_MOTION_CLUSTER = 0xFC04
local SMARTSENSE_MOTION_STATUS_CMD = 0x00
local SMARTSENSE_MOTION_STATUS_REPORT_CMD = 0x02
local MOTION_MASK = 0x02
local POWER_SOURCE_MASK = 0x01
local battery_table = {
  [28] = 100, -- [volt*10] = perc
  [27] = 100,
  [26] = 100,
  [25] = 90,
  [24] = 90,
  [23] = 70,
  [22] = 70,
  [21] = 50,
  [20] = 50,
  [19] = 30,
  [18] = 30,
  [17] = 15,
  [16] = 1,
  [15] = 0,
  [0] = 0
}

local function device_added(driver, device)
  -- device:emit_event(motion.inactive())
  -- device:emit_event(signalStrength.lqi(0))
  -- device:emit_event(signalStrength.rssi({ value = -100, unit = 'dBm' }))
end

local function handle_battery(device, value, zb_rx)
  local batt_perc
  for volt, perc in utils.rkeys(battery_table) do
    if value >= volt then
      batt_perc = perc
      break
    end
  end
  if batt_perc ~= nil then
    device:emit_event_for_endpoint(
      zb_rx.address_header.src_endpoint.value,
      capabilities.battery.battery(batt_perc)
    )
  end
end

local function legacy_motion_status_handler(driver, device, zb_rx)
  local payload = string.byte(zb_rx.body.zcl_body.body_bytes)
  if payload & POWER_SOURCE_MASK == 0 then
    handle_battery(device, payload >> 2, zb_rx)
  end
  device:emit_event(payload & MOTION_MASK == 0 and motion.inactive() or motion.active())
  device:emit_event(signalStrength.lqi(zb_rx.lqi.value))
  device:emit_event(signalStrength.rssi({ value = zb_rx.rssi.value, unit = 'dBm' }))
end

local smartsense_motion = {
  NAME = "SmartSense Motion Sensor",
  zigbee_handlers = {
    cluster = {
      [SMARTSENSE_MOTION_CLUSTER] = {
        [SMARTSENSE_MOTION_STATUS_CMD] = legacy_motion_status_handler
      }
    }
  },
  lifecycle_handlers = {
    added = device_added
  },
  can_handle = function(opts, driver, device, ...)
    return device:get_manufacturer() == SMARTSENSE_MFR and device:get_model() == SMARTSENSE_MODEL
  end
}

return smartsense_motion
