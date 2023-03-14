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
--- @type st.zwave.CommandClass.CentralScene
local CentralScene = (require "st.zwave.CommandClass.CentralScene")({version=3})

local INOVELLI_MANUFACTURER_ID = 0x031E
local INOVELLI_LZW31SN_PRODUCT_TYPE = 0x0001
local INOVELLI_DIMMER_PRODUCT_ID = 0x0001
local LED_BAR_COMPONENT_NAME = "LEDColorConfiguration"

local supported_button_values = {
  ["button1"] = {"pushed", "pushed_2x", "pushed_3x", "pushed_4x", "pushed_5x"},
  ["button2"] = {"pushed", "pushed_2x", "pushed_3x", "pushed_4x", "pushed_5x"},
  ["button3"] = {"pushed"}
}

local function device_added(driver, device)
  for _, component in pairs(device.profile.components) do
    if component.id ~= "main" and component.id ~= LED_BAR_COMPONENT_NAME then
      device:emit_component_event(
        component,
        capabilities.button.supportedButtonValues(
          supported_button_values[component.id],
          { visibility = { displayed = false } }
        )
      )
      device:emit_component_event(
        component,
        capabilities.button.numberOfButtons({value = 1}, { visibility = { displayed = false } })
      )
    end
  end
  device:refresh()
end

local map_scene_number_to_component = {
  [1] = "button2",
  [2] = "button1",
  [3] = "button3"
}


local map_key_attribute_to_capability = {
  [CentralScene.key_attributes.KEY_PRESSED_1_TIME] = capabilities.button.button.pushed,
  [CentralScene.key_attributes.KEY_PRESSED_2_TIMES] = capabilities.button.button.pushed_2x,
  [CentralScene.key_attributes.KEY_PRESSED_3_TIMES] = capabilities.button.button.pushed_3x,
  [CentralScene.key_attributes.KEY_PRESSED_4_TIMES] = capabilities.button.button.pushed_4x,
  [CentralScene.key_attributes.KEY_PRESSED_5_TIMES] = capabilities.button.button.pushed_5x,
}

local function central_scene_notification_handler(self, device, cmd)
  if ( cmd.args.scene_number ~= nil and cmd.args.scene_number ~= 0 ) then
    local capability_attribute = map_key_attribute_to_capability[cmd.args.key_attributes]
    local additional_fields = {
      state_change = true
    }

    local event
    if capability_attribute ~= nil then
      event = capability_attribute(additional_fields)
    end

    if event ~= nil then
      -- device reports scene notifications from endpoint 0 (main) but central scene events have to be emitted for button components: 1,2,3
      local comp = device.profile.components[map_scene_number_to_component[cmd.args.scene_number]]
      if comp ~= nil then
        device:emit_component_event(comp, event)
      end
    end
  end
end

local function can_handle_inovelli_lzw31sn(opts, driver, device, ...)
  if device:id_match(
    INOVELLI_MANUFACTURER_ID,
    INOVELLI_LZW31SN_PRODUCT_TYPE,
    INOVELLI_DIMMER_PRODUCT_ID
  ) then
    return true
  end
  return false
end

local inovelli_led_lzw31sn = {
  NAME = "Inovelli LED LZW 31SN",
  zwave_handlers = {
    [cc.CENTRAL_SCENE] = {
      [CentralScene.NOTIFICATION] = central_scene_notification_handler
    }
  },
  lifecycle_handlers = {
    added = device_added
  },
  can_handle = can_handle_inovelli_lzw31sn
}

return inovelli_led_lzw31sn
