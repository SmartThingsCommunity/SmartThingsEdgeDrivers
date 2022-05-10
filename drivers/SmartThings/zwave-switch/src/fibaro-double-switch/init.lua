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
--- @type st.utils
local utils = require "st.utils"
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.CentralScene
local CentralScene = (require "st.zwave.CommandClass.CentralScene")({version=1})

local FIBARO_DOUBLE_SWITCH_FINGERPRINTS = {
  {mfr = 0x010F, prod = 0x0203, model = 0x1000}, -- Fibaro Switch
  {mfr = 0x010F, prod = 0x0203, model = 0x2000}, -- Fibaro Switch
  {mfr = 0x010F, prod = 0x0203, model = 0x3000} -- Fibaro Switch
}

local function can_handle_fibaro_double_switch(opts, driver, device, ...)
  for _, fingerprint in ipairs(FIBARO_DOUBLE_SWITCH_FINGERPRINTS) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      return true
    end
  end
  return false
end

local function central_scene_notification_handler(self, device, cmd)
  local map_key_attribute_to_capability = {
    [CentralScene.key_attributes.KEY_PRESSED_1_TIME] = capabilities.button.button.pushed,
    [CentralScene.key_attributes.KEY_RELEASED] = capabilities.button.button.held,
    [CentralScene.key_attributes.KEY_HELD_DOWN] = capabilities.button.button.down_hold,
    [CentralScene.key_attributes.KEY_PRESSED_2_TIMES] = capabilities.button.button.double,
    [CentralScene.key_attributes.KEY_PRESSED_3_TIMES] = capabilities.button.button.pushed_3x
  }

  local event = map_key_attribute_to_capability[cmd.args.key_attributes]
  local button_number = 0
  if cmd.args.key_attributes == 0 or cmd.args.key_attributes == 1 or cmd.args.key_attributes == 2 then
    button_number = cmd.args.scene_number
  elseif cmd.args.key_attributes == 3 then
    button_number = cmd.args.scene_number + 2
  elseif cmd.args.key_attributes == 4 then
    button_number = cmd.args.scene_number + 4
  end

  local component = device.profile.components["button" .. button_number]

  if component ~= nil then
    device:emit_component_event(component, event({state_change = true}))
  end
end

local function component_to_endpoint(device, component_id)
  if component_id == "main" then
    return {1}
  else
    return {2}
  end
end

local function endpoint_to_component(device, ep)
  local switch_comp = string.format("switch%d", ep - 1)
  if device.profile.components[switch_comp] ~= nil then
    return switch_comp
  else
    return "main"
  end
end

local device_init = function(self, device)
  device:set_component_to_endpoint_fn(component_to_endpoint)
  device:set_endpoint_to_component_fn(endpoint_to_component)
end

local fibaro_double_switch = {
  NAME = "fibaro double switch",
  zwave_handlers = {
    [cc.CENTRAL_SCENE] = {
      [CentralScene.NOTIFICATION] = central_scene_notification_handler
    }
  },
  lifecycle_handlers = {
    init = device_init
  },
  can_handle = can_handle_fibaro_double_switch,
}

return fibaro_double_switch
