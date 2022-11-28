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

local device_management = require "st.zigbee.device_management"
local zcl_clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"

local Level = zcl_clusters.Level
local OnOff = zcl_clusters.OnOff
local Scenes = zcl_clusters.Scenes

local Switch = capabilities.switch
local SwitchLevel = capabilities.switchLevel

local DEFAULT_LEVEL = 100
local DEFAULT_STATUS = "on"
local CURRENT_LEVEL = "current_level"
local CURRENT_STATUS = "current_status"
local STEP = 10

local ZIGBEE_ACCESSORY_DIMMER_FINGERPRINTS = {
    { mfr = "Aurora", model = "Remote50AU" },
    { mfr = "LDS", model = "ZBT-DIMController-D0800" }
}

local generate_switch_onoff_event = function(device, value)
  if value == "on" then
    device:emit_event(capabilities.switch.switch.on())
    device:set_field(CURRENT_STATUS, "on")
  else
    device:emit_event(capabilities.switch.switch.off())
    device:set_field(CURRENT_STATUS, "off")
  end
end

local generate_switch_level_event = function(device, value)
  device:emit_event(capabilities.switchLevel.level(value))
  device:set_field(CURRENT_LEVEL, value)
end

local on_off_command_handler = function(driver, device, value, zb_rx)
  local level = device:get_field(CURRENT_LEVEL) or DEFAULT_LEVEL
  local status = device:get_field(CURRENT_STATUS) or DEFAULT_STATUS
  if level == 0 then
    generate_switch_level_event(device, STEP)
  end

  generate_switch_onoff_event(device, status == "on" and "off" or "on")
end

local level_step_command_handler = function(driver, device, zb_rx)
  local level = device:get_field(CURRENT_LEVEL) or DEFAULT_LEVEL
  local status = device:get_field(CURRENT_STATUS) or DEFAULT_STATUS
  local value

  if zcl_clusters.Level.types.MoveStepMode.UP == zb_rx.body.zcl_body.step_mode.value then
    value = math.min(level + STEP, 100)
  else
    value = math.max(level - STEP, 0)
  end

  if value == 0 then
    generate_switch_onoff_event(device, "off")
  elseif status == "off" then
      generate_switch_onoff_event(device, "on")
  end

  generate_switch_level_event(device, value)
end

local level_move_command_handler = function(driver, device, zb_rx)
  if zcl_clusters.Level.types.MoveStepMode.UP ==  zb_rx.body.zcl_body.move_mode.value then
    generate_switch_level_event(device, 100)
  else
    generate_switch_level_event(device, STEP)
  end

  generate_switch_onoff_event(device, "on")
end

local scenes_store_command_handler = function(driver, device, zb_rx)
  device:emit_event(capabilities.button.button.held({state_change = true}))
end

local level_recall_command_handler = function(driver, device, zb_rx)
  device:emit_event(capabilities.button.button.pushed({state_change = true}))
end

local function switch_on_command_handler(driver, device, command)
  device:emit_event(capabilities.switch.switch.on({ state_change = true }))
end

local switch_off_command_handler = function(driver, device, command)
  device:emit_event(capabilities.switch.switch.off({ state_change = true }))
end

local switch_level_set_level_command_handler = function(driver, device, command)
  local level = command.args.level

  if level == 0 then
    -- TBD: do we need to send zigbee cmd to change device status?
    --device:send_to_component(command.component, zcl_clusters.OnOff.server.commands.Off(device))
    level = device:get_field(CURRENT_LEVEL)
  else
    --device:send_to_component(command.component, zcl_clusters.OnOff.server.commands.On(device))
  end

  device.thread:call_with_delay(1, function()
    generate_switch_level_event(device, level)
  end)
end

local device_added = function(self, device)
  -- generate_switch_onoff_event(device, "on")
  -- generate_switch_level_event(device, 100)
  device:emit_event(capabilities.button.numberOfButtons({value = 1}, { visibility = { displayed = false } }))
  device:emit_event(capabilities.button.supportedButtonValues({"pushed", "held"}, { visibility = { displayed = false } }))
  -- device:emit_event(capabilities.button.button.pushed({state_change = true}))
end

local do_configure = function(self, device)
  device:send(device_management.build_bind_request(device, Scenes.ID, self.environment_info.hub_zigbee_eui))
  device:send(device_management.build_bind_request(device, OnOff.ID, self.environment_info.hub_zigbee_eui))
  device:send(device_management.build_bind_request(device, Level.ID, self.environment_info.hub_zigbee_eui))
end


local is_zigbee_accessory_dimmer = function(opts, driver, device)
    for _, fingerprint in ipairs(ZIGBEE_ACCESSORY_DIMMER_FINGERPRINTS) do
        if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
            return true
        end
    end

    return false
end

local zigbee_accessory_dimmer = {
  NAME = "zigbee accessory dimmer",
  zigbee_handlers = {
    cluster = {
      [OnOff.ID] = {
        [OnOff.server.commands.On.ID] = on_off_command_handler,
        [OnOff.server.commands.Off.ID] = on_off_command_handler
      },
      [Level.ID] = {
        [Level.server.commands.Move.ID] = level_move_command_handler,
        [Level.server.commands.Step.ID] = level_step_command_handler
      },
      [Scenes.ID] = {
        [Scenes.server.commands.StoreScene.ID] = scenes_store_command_handler,
        [Scenes.server.commands.RecallScene.ID] = level_recall_command_handler
      }
    }
  },
  capability_handlers = {
    [Switch.ID] = {
      [Switch.commands.on.NAME] = switch_on_command_handler,
      [Switch.commands.off.NAME] = switch_off_command_handler
    },
    [SwitchLevel.ID] = {
      [SwitchLevel.commands.setLevel.NAME] = switch_level_set_level_command_handler
    }
  },
  lifecycle_handlers = {
    added = device_added,
    doConfigure = do_configure
  },
  can_handle = is_zigbee_accessory_dimmer
}

return zigbee_accessory_dimmer
