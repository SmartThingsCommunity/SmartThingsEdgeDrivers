-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0



local capabilities = require "st.capabilities"
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.CentralScene
local CentralScene = (require "st.zwave.CommandClass.CentralScene")({ version=1 })
--- @type st.zwave.CommandClass.SceneActivation
local SceneActivation = (require "st.zwave.CommandClass.SceneActivation")({ version=1 })



local map_key_attribute_to_capability = {
  [CentralScene.key_attributes.KEY_PRESSED_1_TIME] = capabilities.button.button.pushed,
  [CentralScene.key_attributes.KEY_RELEASED] = capabilities.button.button.held,
  [CentralScene.key_attributes.KEY_HELD_DOWN] = capabilities.button.button.down_hold,
  [CentralScene.key_attributes.KEY_PRESSED_2_TIMES] = capabilities.button.button.double,
  [CentralScene.key_attributes.KEY_PRESSED_3_TIMES] = capabilities.button.button.pushed_3x,
  [CentralScene.key_attributes.KEY_PRESSED_4_TIMES] = capabilities.button.button.pushed_4x,
  [CentralScene.key_attributes.KEY_PRESSED_5_TIMES] = capabilities.button.button.pushed_5x
}

local function central_scene_notification_handler(self, device, cmd)
  local event = map_key_attribute_to_capability[cmd.args.key_attributes]({state_change = true})
  if event ~= nil then
    local supportedEvents = device:get_latest_state(
      device:endpoint_to_component(cmd.args.scene_number),
      capabilities.button.ID,
      capabilities.button.supportedButtonValues.NAME,
      {capabilities.button.button.pushed.NAME, capabilities.button.button.held.NAME} -- default value
    )
    for _, event_name in pairs(supportedEvents) do
      if event.value.value == event_name then
        device:emit_event_for_endpoint(cmd.args.scene_number, event)
        device:emit_event(event)
      end
    end
  end
end

local function scene_activation_handler(self, device, cmd)
  local scene_id = cmd.args.scene_id
  local event = scene_id % 2 == 0 and capabilities.button.button.held or capabilities.button.button.pushed
  device:emit_event_for_endpoint((scene_id + 1) // 2, event({state_change = true}))
  device:emit_event(event({state_change = true}))
end

local function component_to_endpoint(device, component_id)
  local ep_num = component_id:match("button(%d)")
  return { ep_num and tonumber(ep_num) }
end

local function endpoint_to_component(device, ep)
  local button_comp = string.format("button%d", ep)
  if device.profile.components[button_comp] ~= nil then
    return button_comp
  else
    return "main"
  end
end

local function device_init(self, device)
  device:set_component_to_endpoint_fn(component_to_endpoint)
  device:set_endpoint_to_component_fn(endpoint_to_component)
end

local zwave_multi_button = {
  NAME = "Z-Wave multi button",
  zwave_handlers = {
    [cc.CENTRAL_SCENE] = {
      [CentralScene.NOTIFICATION] = central_scene_notification_handler
    },
    [cc.SCENE_ACTIVATION] = {
      [SceneActivation.SET] = scene_activation_handler
    }
  },
  lifecycle_handlers = {
    init = device_init
  },
  can_handle = require("zwave-multi-button.can_handle"),
  sub_drivers = require("zwave-multi-button.sub_drivers"),
}

return zwave_multi_button
