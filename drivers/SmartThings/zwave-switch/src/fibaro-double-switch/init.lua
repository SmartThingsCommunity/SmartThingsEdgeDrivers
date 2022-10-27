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

local st_device = require "st.device"
local capabilities = require "st.capabilities"
local switch_defaults = require "st.zwave.defaults.switch"
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.CentralScene
local CentralScene = (require "st.zwave.CommandClass.CentralScene")({version=1, strict = true})
--- @type st.zwave.CommandClass.Basic
local Basic = (require "st.zwave.CommandClass.Basic")({ version = 1, strict = true })
--- @type st.zwave.CommandClass.SwitchBinary
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({ version = 2, strict = true })
--- @type st.zwave.CommandClass.Meter
local Meter = (require "st.zwave.CommandClass.Meter")({ version = 3 })

local ENDPOINTS = {
  parent = 1,
  child = 2
}

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

local function do_refresh(driver, device, command)
  local component = command and command.component and command.component or "main"
  device:send_to_component(SwitchBinary:Get({}), component)
  device:send_to_component(Basic:Get({}), component)
  device:send_to_component(Meter:Get({ scale = Meter.scale.electric_meter.WATTS }), component)
  device:send_to_component(Meter:Get({ scale = Meter.scale.electric_meter.KILOWATT_HOURS }), component)
end

local function device_added(driver, device, event)
  if device.network_type == st_device.NETWORK_TYPE_ZWAVE then
    local name = string.format("%s %s", device.label, "(CH2)")
    local metadata = {
      type = "EDGE_CHILD",
      label = name,
      profile = "metering-switch",
      parent_device_id = device.id,
      parent_assigned_child_key = string.format("%02X", ENDPOINTS.child),
      vendor_provided_label = name,
    }
    driver:try_create_device(metadata)
  end
  do_refresh(driver, device)
end

local function find_child(parent, ep_id)
  if ep_id == ENDPOINTS.parent then
    return parent
  else
    return parent:get_child_by_parent_assigned_key(string.format("%02X", ep_id))
  end
end

local function component_to_endpoint(device, component)
  return { ENDPOINTS.parent }
end

local function device_init(driver, device, event)
  if device.network_type == st_device.NETWORK_TYPE_ZWAVE then
    device:set_find_child(find_child)
    device:set_component_to_endpoint_fn(component_to_endpoint)
  end
end

local function switch_report(driver, device, cmd)
  switch_defaults.zwave_handlers[cc.SWITCH_BINARY][SwitchBinary.REPORT](driver, device, cmd)
  
  if device:supports_capability_by_id(capabilities.powerMeter.ID) then
    device:send(Meter:Get({ scale = Meter.scale.electric_meter.WATTS }, { dst_channels = { cmd.src_channel } }))
  end
end

local fibaro_double_switch = {
  NAME = "fibaro double switch",
  zwave_handlers = {
    [cc.CENTRAL_SCENE] = {
      [CentralScene.NOTIFICATION] = central_scene_notification_handler
    },
    [cc.BASIC] = {
      [Basic.REPORT] = switch_report
    },
    [cc.SWITCH_BINARY] = {
      [SwitchBinary.REPORT] = switch_report
    }
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh
    }
  },
  lifecycle_handlers = {
    init = device_init,
    added = device_added
  },
  can_handle = can_handle_fibaro_double_switch,
}

return fibaro_double_switch
