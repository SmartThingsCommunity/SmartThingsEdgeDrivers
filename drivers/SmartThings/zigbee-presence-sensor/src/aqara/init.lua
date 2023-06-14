-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy ofF the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

local capabilities = require "st.capabilities"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local PresenceSensor = capabilities.presenceSensor
local MovementSensor = capabilities["stse.movementSensor"]

local PRIVATE_CLUSTER_ID = 0xFCC0
local PRIVATE_ATTRIBUTE_ID = 0x0009
local MFG_CODE = 0x115F

local MONITORING_MODE = 0x0144
local RESET_MODE = 0x0157

local MOVEMENT_TIMER = "movement_timer"
local MOVEMENT_TIME = 5

local SENSITIVITY = "stse.sensitivity"
local RESET_PRESENCE = "stse.resetPresence"
local APP_DISTANCE = "stse.approachDistance"

local FINGERPRINTS = {
  { mfr = "aqara", model = "lumi.motion.ac01" }
}

local is_aqara_products = function(opts, driver, device, ...)
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local function device_init(driver, device)
  -- no action
end

local function device_added(driver, device)
  -- private protocol enable
  device:send(cluster_base.write_manufacturer_specific_attribute(device,
    PRIVATE_CLUSTER_ID, PRIVATE_ATTRIBUTE_ID, MFG_CODE, data_types.Uint8, 1))
  -- init
  device:send(cluster_base.write_manufacturer_specific_attribute(device,
    PRIVATE_CLUSTER_ID, MONITORING_MODE, MFG_CODE, data_types.Uint8, 0))
  device:send(cluster_base.write_manufacturer_specific_attribute(device,
    PRIVATE_CLUSTER_ID, RESET_MODE, MFG_CODE, data_types.Uint8, 1))
  device:emit_event(PresenceSensor.presence("not present"))
  device:emit_event(MovementSensor.movement("noMovement"))
end

local function device_info_changed(driver, device, event, args)
  if device.preferences ~= nil then
    if device.preferences[SENSITIVITY] ~= args.old_st_store.preferences[SENSITIVITY] then
      device:send(cluster_base.write_manufacturer_specific_attribute(device,
        PRIVATE_CLUSTER_ID, 0x010C, MFG_CODE, data_types.Uint8, tonumber(device.preferences[SENSITIVITY])))
    end
    if device.preferences[RESET_PRESENCE] ~= args.old_st_store.preferences[RESET_PRESENCE] then
      device:send(cluster_base.write_manufacturer_specific_attribute(device,
        PRIVATE_CLUSTER_ID, RESET_MODE, MFG_CODE, data_types.Uint8, 0x01))
    end
    if device.preferences[APP_DISTANCE] ~= args.old_st_store.preferences[APP_DISTANCE] then
      device:send(cluster_base.write_manufacturer_specific_attribute(device,
        PRIVATE_CLUSTER_ID, 0x0146, MFG_CODE, data_types.Uint8, tonumber(device.preferences[APP_DISTANCE])))
    end
  end
end

local function presence_monitor_handler(driver, device, value, zb_rx)
  local val = value.value

  if val == 0 then
    device:emit_event(PresenceSensor.presence("not present"))
  elseif val == 1 then
    device:emit_event(PresenceSensor.presence("present"))
  end
end

local function move_monitor_handler(driver, device, value, zb_rx)
  local val = value.value

  if val < 2 or val == 6 or val == 7 then
    if val == 0 then
      device:emit_event(MovementSensor.movement("enter"))
    elseif val == 1 then
      device:emit_event(MovementSensor.movement("leave"))
    elseif val == 6 then
      device:emit_event(MovementSensor.movement("approaching"))
    elseif val == 7 then
      device:emit_event(MovementSensor.movement("goingAway"))
    end
    local movement_timer = device:get_field(MOVEMENT_TIMER)
    if movement_timer then
      device.thread:cancel_timer(movement_timer)
      device:set_field(MOVEMENT_TIMER, nil, { persist = true })
    end

    local no_movement = function()
      device:emit_event(MovementSensor.movement("noMovement"))
    end
    device:set_field(MOVEMENT_TIMER, device.thread:call_with_delay(MOVEMENT_TIME, no_movement))
  end
end

local aqara_fp1_handler = {
  NAME = "Aqara Presence Senser FP1 Handler",
  zigbee_handlers = {
    attr = {
      [0xFCC0] = {
        [0x0142] = presence_monitor_handler,
        [0x0143] = move_monitor_handler
      }
    }
  },
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
    infoChanged = device_info_changed
  },
  can_handle = is_aqara_products
}

return aqara_fp1_handler
