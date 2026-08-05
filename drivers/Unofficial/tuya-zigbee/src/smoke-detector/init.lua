-- Copyright 2025 SmartThings
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
local device_management = require "st.zigbee.device_management"
local clusters = require "st.zigbee.zcl.clusters"
local tuya_utils = require "tuya_utils"
local Basic = clusters.Basic

local FINGERPRINTS = {
  { mfr = "_TZE200_ioxkjvuz", model = "TS0601"},
  { mfr = "_TZE204_mby4kbtq", model = "TS0601"},
  { mfr = "_TZE200_uebojraa", model = "TS0601"}
}

local function is_tuya_smoke(opts, driver, device)
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local function device_added(self, device)
  device:emit_event(capabilities.smokeDetector.smoke.clear())
  device:emit_event(capabilities.batteryLevel.battery.normal())
end

local do_configure = function(driver, device)
  -- configure ApplicationVersion to keep device online, tuya hub also uses this attribute
  tuya_utils.send_magic_spell(device)
  device:send(Basic.attributes.ApplicationVersion:configure_reporting(device, 30, 300, 1))
  device:send(device_management.build_bind_request(device, Basic.ID, driver.environment_info.hub_zigbee_eui))
end

local function tuya_cluster_handler(driver, device, zb_rx)
  local event
  local raw = zb_rx.body.zcl_body.body_bytes
  local dp = raw:byte(3)
  local dp_data = raw:byte(7)
  if dp == 0x01 and dp_data == 0x00 then
    event = capabilities.smokeDetector.smoke.detected()
    device.thread:call_with_delay(10, function(d)
      device:emit_event(capabilities.smokeDetector.smoke.clear())
    end)
  elseif dp == 0x01 and dp_data == 0x01 then
    event = capabilities.smokeDetector.smoke.clear()
  elseif dp == 0x0e and dp_data == 0x02 then
    event = capabilities.batteryLevel.battery.normal()
  elseif dp == 0x0e and dp_data == 0x01 then
    event = capabilities.batteryLevel.battery.warning()
  elseif dp == 0x0e and dp_data == 0x00 then
    event = capabilities.batteryLevel.battery.critical()
  end
  if event ~= nil then
    device:emit_event(event)
  end
end

local function tuya_meian_cluster_handler(driver, device, zb_rx)
  local rx = zb_rx.body.zcl_body.body_bytes
  local dp_data = rx:byte(7)
  if dp_data == 0x01 then
    device:emit_event(capabilities.smokeDetector.smoke.detected())
    device.thread:call_with_delay(10, function(d)
      device:emit_event(capabilities.smokeDetector.smoke.clear())
    end)
  elseif dp_data == 0x00 then
    device:emit_event(capabilities.smokeDetector.smoke.clear())
  end
end

local tuya_smoke_detector_driver = {
  NAME = "tuya smoke detector",
  zigbee_handlers = {
    cluster = {
      [tuya_utils.TUYA_PRIVATE_CLUSTER] = {
        [tuya_utils.TUYA_PRIVATE_CMD_RESPONSE] = tuya_meian_cluster_handler,
        [tuya_utils.TUYA_PRIVATE_CMD_REPORT] = tuya_cluster_handler
      }
    }
  },
  lifecycle_handlers = {
    added = device_added,
    doConfigure = do_configure
  },
  can_handle = is_tuya_smoke
}

return tuya_smoke_detector_driver