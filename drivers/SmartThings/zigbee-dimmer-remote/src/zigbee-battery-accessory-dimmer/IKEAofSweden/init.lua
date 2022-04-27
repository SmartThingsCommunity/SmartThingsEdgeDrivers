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

local zcl_clusters = require "st.zigbee.zcl.clusters"
local Level = zcl_clusters.Level

local capabilities = require "st.capabilities"

local DEFAULT_LEVEL = 100
local DOUBLE_STEP = 10

local IKEA_OF_SWEDEN_FINGERPRINTS = {
  { mfr = "IKEA of Sweden", model = "TRADFRI wireless dimmer" }
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

local handleStepEvent = function(device, direction)
  local level = device:get_latest_state("main", capabilities.switchLevel.ID, capabilities.switchLevel.level.NAME) or DEFAULT_LEVEL
  local value = 0

  if direction == zcl_clusters.Level.types.MoveStepMode.UP  then
    value = math.min(level + DOUBLE_STEP, 100)
  elseif direction == zcl_clusters.Level.types.MoveStepMode.DOWN then
    value = math.max(level - DOUBLE_STEP, 0)
  end

  if value == 0 then
    generate_switch_onoff_event(device, "off", false)
  else
    generate_switch_onoff_event(device, "on", false)
    generate_switch_level_event(device, value)
  end
end

local level_move_command_handler = function(driver, device, zb_rx)
  local move_mode = zb_rx.body.zcl_body.move_mode.value
  handleStepEvent(device, move_mode)
end

local level_move_with_onoff_command_handler = function(driver, device, zb_rx)
  local move_mode = zb_rx.body.zcl_body.move_mode.value
  handleStepEvent(device, move_mode)
end

local level_move_to_level_with_onoff_command_handler = function(driver, device, zb_rx)
  local level = zb_rx.body.zcl_body.level.value

  if level == 0x00 then
    generate_switch_onoff_event(device, "on", true)
  elseif level == 0xFF then
    local current_level = device:get_latest_state("main", capabilities.switchLevel.ID, capabilities.switchLevel.level.NAME) or DEFAULT_LEVEL
    if current_level == 0 then
      generate_switch_level_event(device, DOUBLE_STEP)
    end

    generate_switch_onoff_event(device, "on", true)
  else
    generate_switch_onoff_event(device, "on", true)

    device:send(zcl_clusters.Level.server.commands.MoveToLevelWithOnOff(device, level))
  end
  handleStepEvent(device, level)
end

local level_step_command_handler = function(driver, device, zb_rx)
  local move_mode = zb_rx.body.zcl_body.step_mode.value
  handleStepEvent(device, move_mode)
end

local is_ikea_of_sweden = function(opts, driver, device)
  for _, fingerprint in ipairs(IKEA_OF_SWEDEN_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end

  return false
end

local ikea_of_sweden = {
  NAME = "IKEA of Sweden",
  zigbee_handlers = {
    cluster = {
      [Level.ID] = {
        [Level.server.commands.Move.ID] = level_move_command_handler,
        [Level.server.commands.MoveWithOnOff.ID] = level_move_with_onoff_command_handler,
        [Level.server.commands.MoveToLevelWithOnOff.ID] = level_move_to_level_with_onoff_command_handler,
        [Level.server.commands.Step.ID] = level_step_command_handler
      }
    }
  },
  can_handle = is_ikea_of_sweden
}

return ikea_of_sweden
