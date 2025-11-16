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

local STEP = 5
local DOUBLE_STEP = 10

local SENGLED_MFR_SPECIFIC_CLUSTER = 0xFC10
local SENGLED_MFR_SPECIFIC_COMMAND = 0x00

local SENGLED_FINGERPRINTS = {
  { mfr = "sengled", model = "E1E-G7F" }
}

local generate_switch_level_event = function(device, value)
  device:emit_event(capabilities.switchLevel.level(value))
end

local generate_switch_onoff_event = function(device, value, state_change_value)
  local additional_fields = {
    state_change = state_change_value
  }
  if value == "on" then
    device:emit_event(capabilities.switch.switch.on(additional_fields))
  else
    device:emit_event(capabilities.switch.switch.off(additional_fields))
  end
end

local sengled_mfr_specific_command_handler = function(driver, device, zb_rx)
  local cmd = zb_rx.body.zcl_body.body_bytes:byte(1)
  local sub_cmd = string.byte(zb_rx.body.zcl_body.body_bytes:sub(3, 3))
  local current_level = device:get_latest_state("main", capabilities.switchLevel.ID, capabilities.switchLevel.level.NAME) or 0
  local level

  if cmd == 0x01 then
    generate_switch_onoff_event(device, "on", false)
  elseif cmd == 0x02 then
    if sub_cmd == 0x02 then
      level = math.min(current_level + DOUBLE_STEP, 100)
    elseif sub_cmd == 0x01 then
      level = math.min(current_level + STEP, 100)
    else
      level = current_level
    end

    generate_switch_onoff_event(device, "on", false)
    generate_switch_level_event(device, level)
  elseif cmd == 0x03 then
    if sub_cmd == 0x02 then
      level = math.max(current_level - DOUBLE_STEP, 0)
    elseif sub_cmd == 0x01 then
      level = math.max(current_level - STEP, 0)
    else
      level = current_level
    end

    if level == 0 then
      generate_switch_onoff_event(device, "off", false)
    else
      generate_switch_onoff_event(device, "on", false)
      generate_switch_level_event(device, level)
    end
  elseif cmd == 0x04 then
    generate_switch_onoff_event(device, "off", false)
  elseif cmd == 0x06 then
    generate_switch_onoff_event(device, "on", false)
  elseif cmd == 0x08 then
    generate_switch_onoff_event(device, "off", false)
  else
    return
  end
end

local is_sengled = function(opts, driver, device)
  for _, fingerprint in ipairs(SENGLED_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end

  return false
end

local sengled = {
  NAME = "sengled",
  zigbee_handlers = {
    cluster = {
      [SENGLED_MFR_SPECIFIC_CLUSTER] = {
        [SENGLED_MFR_SPECIFIC_COMMAND] = sengled_mfr_specific_command_handler
      }
    }
  },
  can_handle = is_sengled
}

return sengled
