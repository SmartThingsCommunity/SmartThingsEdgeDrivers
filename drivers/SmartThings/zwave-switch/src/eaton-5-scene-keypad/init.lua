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

--- @type st.capabilities
local capabilities = require "st.capabilities"
--- @type st.zwave.constants
local constants = require "st.zwave.constants"
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.Indicator
local Indicator = (require "st.zwave.CommandClass.Indicator")({ version=1 })
--- @type st.zwave.CommandClass.Basic
local Basic = (require "st.zwave.CommandClass.Basic")({ version=1 })
--- @type st.zwave.CommandClass.SceneActivation
local SceneActivation = (require "st.zwave.CommandClass.SceneActivation")({ version=1 })
--- @type st.zwave.CommandClass.SceneControllerConf
local SceneControllerConf = (require "st.zwave.CommandClass.SceneControllerConf")({ version=1 })

local INDICATOR_SWITCH_STATES = "Indicator_switch_states"

local EATON_5_SCENE_KEYPAD_FINGERPRINT = {
  {mfr = 0x001A, prod = 0x574D, model = 0x0000}, -- Eaton 5-Scene Keypad
}

local function upsert_after_bit_update_at_index(device, bit_position, new_bit)
  local old_value = device:get_field(INDICATOR_SWITCH_STATES) or 0
  local mask = ~(0x1 << (bit_position - 1))
  local new_value = (old_value & mask) | ((new_bit and 1 or 0) << (bit_position - 1))
  device:set_field(INDICATOR_SWITCH_STATES, new_value, { persist = true})
  return new_value
end

local function component_to_index(device, component_id)
  local index = component_id:match("switch(%d)")
  return index and tonumber(index) or 1
end

local function switch_capability_set_helper(capability_switch_value)
  return function(driver, device, command)
    local index = component_to_index(device, command.component)
    local new_value = upsert_after_bit_update_at_index(device, index, capability_switch_value)
    device:send(Indicator:Set({
      value = new_value
    }))

    local query_device = function()
      device:send(Indicator:Get({}))
    end
    device.thread:call_with_delay(constants.DEFAULT_GET_STATUS_DELAY, query_device)
  end
end

local function do_refresh(self, device)
  device:send(Indicator:Get({}))
end

local function zwave_handlers_basic_set(self, device, cmd)
  if cmd.args.value == 0 then
    --[[From DTH (eaton-5-scene-keypad.groovy)
      Device sends this command, BasicSet(cmd.value=0) when any switch is turned off
      Most reliable way to know which switches are still "on" is to check their status
      Indicator returns number which is a bit representation of current state of switch
    --]]
    device:send(Indicator:Get({}))
  end
end

local function zwave_handlers_scene_activation_set(self, device, cmd)
  if cmd.args.scene_id > 5 then
    return
  end

  upsert_after_bit_update_at_index(device, cmd.args.scene_id, capabilities.switch.switch.on())
  device:emit_event_for_endpoint(cmd.args.scene_id, capabilities.switch.switch.on())
end

local function zwave_handlers_indicator_report(self, device, cmd)
  local reported_value = cmd.args.value
  device:set_field(INDICATOR_SWITCH_STATES, reported_value, { persist = true })
  for i = 1,5 do
    local mask = (0x1 << (i-1))
    local bit_enabled = (mask & reported_value) ~= 0
    device:emit_event_for_endpoint(i,
      bit_enabled and capabilities.switch.switch.on() or capabilities.switch.switch.off())
  end
end

local function zwave_handlers_scene_controller_conf_report(self, device, cmd)
  if cmd.args.group_id ~= cmd.args.scene_id then
    -- scene_id should be set as group_id
    device:send(SceneControllerConf:Set(
        { dimming_duration = 0, group_id = cmd.args.group_id, scene_id = cmd.args.group_id}))
  end
end

local function do_configure(self, device)
  device:set_field(INDICATOR_SWITCH_STATES, 0, { persist = true})
end

local function can_handle_eaton_5_scene_keypad(opts, driver, device, ...)
  for _, fingerprint in ipairs(EATON_5_SCENE_KEYPAD_FINGERPRINT) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      return true
    end
  end
  return false
end

local eaton_5_scene_keypad = {
  NAME = "Eaton 5-Scene Keypad",
  zwave_handlers = {
    [cc.BASIC] = {
      [Basic.SET] = zwave_handlers_basic_set
    },
    [cc.INDICATOR] = {
      [Indicator.REPORT] = zwave_handlers_indicator_report
    },
    [cc.SCENE_ACTIVATION] = {
      [SceneActivation.SET] = zwave_handlers_scene_activation_set
    },
    [cc.SCENE_CONTROLLER_CONF] = {
      [SceneControllerConf.REPORT] = zwave_handlers_scene_controller_conf_report
    },
  },
  capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = switch_capability_set_helper(true),
      [capabilities.switch.commands.off.NAME] = switch_capability_set_helper(false),
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh
    }
  },
  lifecycle_handlers = {
    doConfigure = do_configure,
  },
  can_handle = can_handle_eaton_5_scene_keypad,
}

return eaton_5_scene_keypad
