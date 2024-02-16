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
local cc = require "st.zwave.CommandClass"
local CentralScene = (require "st.zwave.CommandClass.CentralScene")({ version = 1 })
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({ version = 2, strict = true })
local SwitchMultilevel = (require "st.zwave.CommandClass.SwitchMultilevel")({ version = 4, strict = true })
local Version = (require "st.zwave.CommandClass.Version")({ version = 2 })
local constants = require "st.zwave.constants"
local log = require "log"
local utils = require "st.utils"

local PROFILE_CHANGED = "profile_changed"
local LAST_SEQ_NUMBER_KEY = -1

local BUTTON_VALUES = {
  "up_hold", "down_hold", "held",
  "up", "up_2x", "up_3x", "up_4x", "up_5x",
  "down", "down_2x", "down_3x", "down_4x", "down_5x",
  "pushed", "pushed_2x", "pushed_3x", "pushed_4x", "pushed_5x"
}

local ENDPOINTS = {
  dimmer = 0,
  relay = 1
}

local map_key_attribute_to_capability = {
  [CentralScene.key_attributes.KEY_PRESSED_1_TIME] = {
    [0x01] = capabilities.button.button.up({state_change = true}),
    [0x02] = capabilities.button.button.down({state_change = true}),
    [0x03] = capabilities.button.button.pushed({state_change = true})
  },
  [CentralScene.key_attributes.KEY_PRESSED_2_TIMES] = {
    [0x01] = capabilities.button.button.up_2x({state_change = true}),
    [0x02] = capabilities.button.button.down_2x({state_change = true}),
    [0x03] = capabilities.button.button.pushed_2x({state_change = true})
  },
  [CentralScene.key_attributes.KEY_PRESSED_3_TIMES] = {
    [0x01] = capabilities.button.button.up_3x({state_change = true}),
    [0x02] = capabilities.button.button.down_3x({state_change = true}),
    [0x03] = capabilities.button.button.pushed_3x({state_change = true})
  },
  [CentralScene.key_attributes.KEY_PRESSED_4_TIMES] = {
    [0x01] = capabilities.button.button.up_4x({state_change = true}),
    [0x02] = capabilities.button.button.down_4x({state_change = true}),
    [0x03] = capabilities.button.button.pushed_4x({state_change = true})
  },
  [CentralScene.key_attributes.KEY_PRESSED_5_TIMES] = {
    [0x01] = capabilities.button.button.up_5x({state_change = true}),
    [0x02] = capabilities.button.button.down_5x({state_change = true}),
    [0x03] = capabilities.button.button.pushed_5x({state_change = true})
  },
  [CentralScene.key_attributes.KEY_HELD_DOWN] = {
    [0x01] = capabilities.button.button.up_hold({state_change = true}),
    [0x02] = capabilities.button.button.down_hold({state_change = true}),
    [0x03] = capabilities.button.button.held({state_change = true})
  }
}

local ZOOZ_ZEN_30_DIMMER_RELAY_FINGERPRINTS = {
  { mfr = 0x027A, prod = 0xA000, model = 0xA008 } -- Zooz Zen 30 Dimmer Relay Double Switch
}

local function can_handle_zooz_zen_30_dimmer_relay_double_switch(opts, driver, device, ...)
  for _, fingerprint in ipairs(ZOOZ_ZEN_30_DIMMER_RELAY_FINGERPRINTS) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      local subdriver = require("zooz-zen-30-dimmer-relay")
      return true, subdriver
    end
  end
  return false
end

local function find_child(parent, src_channel)
  if src_channel == 0 then
    return parent
  else
    return parent:get_child_by_parent_assigned_key(string.format("%02X", src_channel))
  end
end

local function component_to_endpoint(device, component)
  return { ENDPOINTS.dimmer }
end

local function do_refresh(driver, device, cmd)
  local component = cmd and cmd.component and cmd.component or "main"

  if device:supports_capability(capabilities.switchLevel) then
    device:send_to_component(SwitchMultilevel:Get({}), component)
    device:send(Version:Get({}))
  elseif device:supports_capability(capabilities.switch) then
    device:send_to_component(SwitchBinary:Get({}), component)
  end
end

local function device_init(driver, device)
  if device.network_type ~= st_device.NETWORK_TYPE_CHILD then
    device:set_find_child(find_child)
    device:set_component_to_endpoint_fn(component_to_endpoint)
  end
end

local function device_added(driver, device)
  if device.network_type ~= st_device.NETWORK_TYPE_CHILD then
    if not (device.child_ids and utils.table_size(device.child_ids) ~= 0) then
      if find_child(device, ENDPOINTS.relay) == nil then
        local child_metadata = {
          type = "EDGE_CHILD",
          label = string.format("%s Relay", device.label),
          profile = "child-switch",
          parent_device_id = device.id,
          parent_assigned_child_key = string.format("%02X", ENDPOINTS.relay),
          vendor_provided_label = string.format("%s Relay", device.label)
        }
        driver:try_create_device(child_metadata)
      end
    end

    device:emit_event(capabilities.button.supportedButtonValues(BUTTON_VALUES, { visibility = { displayed = false } }))
    device:emit_event(capabilities.button.numberOfButtons({ value = 3 }, { visibility = { displayed = false } }))
  end
  do_refresh(driver, device)
end

local function version_report_handler(driver, device, cmd)
  if (cmd.args.firmware_0_version > 1 or (cmd.args.firmware_0_version == 1 and cmd.args.firmware_0_sub_version > 4)) and
      device:get_field(PROFILE_CHANGED) ~= true then
    local new_profile = "zooz-zen-30-dimmer-relay-new"
    device:try_update_metadata({ profile = new_profile })
    device:set_field(PROFILE_CHANGED, true, { persist = true })
  end
end

local function central_scene_notification_handler(driver, device, cmd)
  if (cmd.args.key_attributes == 0x01) then
    log.error("Button Value 'released' is not supported by SmartThings")
    return
  end

  if device:get_field(LAST_SEQ_NUMBER_KEY) ~= cmd.args.sequence_number then
    device:set_field(LAST_SEQ_NUMBER_KEY, cmd.args.sequence_number)
    local event_map = map_key_attribute_to_capability[cmd.args.key_attributes]
    local event = event_map and event_map[cmd.args.scene_number]
    if event ~= nil then
      device:emit_event_for_endpoint(cmd.src_channel, event)
    end
  end
end

local function switch_set_on_off_handler(value)
  return function(driver, device, command)
    local get, set

    if device:supports_capability(capabilities.switchLevel) then
      set = SwitchMultilevel:Set({ value = value, duration = constants.DEFAULT_DIMMING_DURATION })
      get = SwitchMultilevel:Get({})
    elseif device:supports_capability(capabilities.switch) then
      set = SwitchBinary:Set({ target_value = value, duration = 0 })
      get = SwitchBinary:Get({})
    end

    local query_device = function()
      device:send_to_component(get, command.component)
    end

    device:send_to_component(set, command.component)
    device.thread:call_with_delay(constants.DEFAULT_GET_STATUS_DELAY, query_device)
  end
end

local zooz_zen_30_dimmer_relay_double_switch = {
  NAME = "Zooz Zen 30",
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh
    },
    [capabilities.switch.ID] = {
      [capabilities.switch.switch.on.NAME] = switch_set_on_off_handler(SwitchBinary.value.ON_ENABLE),
      [capabilities.switch.switch.off.NAME] = switch_set_on_off_handler(SwitchBinary.value.OFF_DISABLE)
    }
  },
  zwave_handlers = {
    [cc.CENTRAL_SCENE] = {
      [CentralScene.NOTIFICATION] = central_scene_notification_handler
    },
    [cc.VERSION] = {
      [Version.REPORT] = version_report_handler
    }
  },
  lifecycle_handlers = {
    init = device_init,
    added = device_added
  },
  can_handle = can_handle_zooz_zen_30_dimmer_relay_double_switch
}

return zooz_zen_30_dimmer_relay_double_switch
