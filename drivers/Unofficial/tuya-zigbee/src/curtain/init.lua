-- Copyright 2025 SmartThings
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
local clusters = require "st.zigbee.zcl.clusters"
local utils = require "st.utils"
local device_management = require "st.zigbee.device_management"
local tuya_utils = require "tuya_utils"
local window_preset_defaults = require "st.zigbee.defaults.windowShadePreset_defaults"
local Basic = clusters.Basic
local packet_id = 0

local FINGERPRINTS = {
  { mfr = "_TZE284_nladmfvf", model = "TS0601"}
}

local function is_tuya_curtain(opts, driver, device)
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local function init_handler(self, device)
  if device:supports_capability_by_id(capabilities.windowShadePreset.ID) and
      device:get_latest_state("main", capabilities.windowShadePreset.ID, capabilities.windowShadePreset.position.NAME) == nil then

    -- These should only ever be nil once (and at the same time) for already-installed devices
    -- It can be removed after migration is complete
    device:emit_event(capabilities.windowShadePreset.supportedCommands({"presetPosition", "setPresetPosition"}, { visibility = { displayed = false }}))

    local preset_position = device:get_field(window_preset_defaults.PRESET_LEVEL_KEY) or
      (device.preferences ~= nil and device.preferences.presetPosition) or
      window_preset_defaults.PRESET_LEVEL

    device:emit_event(capabilities.windowShadePreset.position(preset_position, { visibility = {displayed = false}}))
    device:set_field(window_preset_defaults.PRESET_LEVEL_KEY, preset_position, {persist = true})
  end
end

local do_configure = function(driver, device)
  -- configure ApplicationVersion to keep device online, tuya hub also uses this attribute
  tuya_utils.send_magic_spell(device)
  device:send(Basic.attributes.ApplicationVersion:configure_reporting(device, 30, 300, 1))
  device:send(device_management.build_bind_request(device, Basic.ID, driver.environment_info.hub_zigbee_eui))
end

local function device_added(driver, device)
  device:emit_event(capabilities.windowShade.supportedWindowShadeCommands({ "open", "close", "pause" }, {visibility = {displayed = false}}))
  tuya_utils.emit_event_if_latest_state_missing(device, "main", capabilities.windowShadeLevel, capabilities.windowShadeLevel.shadeLevel.NAME, capabilities.windowShadeLevel.shadeLevel(0))
  tuya_utils.emit_event_if_latest_state_missing(device, "main", capabilities.windowShade, capabilities.windowShade.windowShade.NAME, capabilities.windowShade.windowShade.closed())
  device:emit_event(capabilities.windowShadePreset.supportedCommands({"presetPosition", "setPresetPosition"}, { visibility = { displayed = false }}))
  tuya_utils.emit_event_if_latest_state_missing(device, "main", capabilities.windowShadePreset, capabilities.windowShadePreset.position.NAME, window_preset_defaults.PRESET_LEVEL)
end

local function increase_packet_id(packet_id)
  packet_id = (packet_id + 1) % 65536
  return packet_id
end

local function device_info_changed(driver, device, event, args)
  if device.preferences ~= nil then
    local reverseCurtainDirectionPrefValue = device.preferences.reverse
    -- reverse direction
    if reverseCurtainDirectionPrefValue == true then
      tuya_utils.send_tuya_command(device, '\x05', tuya_utils.DP_TYPE_ENUM, '\x01', packet_id)
      packet_id = increase_packet_id(packet_id)
    else
      tuya_utils.send_tuya_command(device, '\x05', tuya_utils.DP_TYPE_ENUM, '\x00', packet_id)
      packet_id = increase_packet_id(packet_id)
    end
  end
end

local function window_shade_open(driver, device)
  tuya_utils.send_tuya_command(device, '\x01', tuya_utils.DP_TYPE_ENUM, '\x00', packet_id)
  packet_id = increase_packet_id(packet_id)
  device:emit_event(capabilities.windowShade.windowShade.opening())
end

local function window_shade_close(driver, device)
  tuya_utils.send_tuya_command(device, '\x01', tuya_utils.DP_TYPE_ENUM, '\x02', packet_id)
  packet_id = increase_packet_id(packet_id)
  device:emit_event(capabilities.windowShade.windowShade.closing())
end

local function window_shade_pause(driver, device)
  tuya_utils.send_tuya_command(device, '\x01', tuya_utils.DP_TYPE_ENUM, '\x01', packet_id)
  packet_id = increase_packet_id(packet_id)
end

local function window_shade_level(driver, device, command)
  local level = command.args.shadeLevel
  if level > 100 then
    level = 100
  end
  level = utils.round(level)
  if device:get_manufacturer() == "_TZE284_nladmfvf" then
    level = 100 - level   -- specific for _TZE284_nladmfvf
  end
  tuya_utils.send_tuya_command(device, '\x02', tuya_utils.DP_TYPE_VALUE, '\x00\x00'..string.pack(">I2", level), packet_id)
  packet_id = increase_packet_id(packet_id)
end

local function window_shade_preset(driver, device)
  local level = device:get_latest_state("main", "windowShadePreset", "position") or
    device:get_field(window_preset_defaults.PRESET_LEVEL_KEY) or
    (device.preferences ~= nil and device.preferences.presetPosition) or
    window_preset_defaults.PRESET_LEVEL
  tuya_utils.send_tuya_command(device, '\x02', tuya_utils.DP_TYPE_VALUE, '\x00\x00'..string.pack(">I2", level), packet_id)
  packet_id = increase_packet_id(packet_id)
end

local function tuya_cluster_handler(driver, device, zb_rx)
  local window_shade_level_event, window_shade_val_event
  local raw = zb_rx.body.zcl_body.body_bytes
  -- dp means data point in tuya payload format
  local dp = raw:byte(3)
  local dp_data = raw:byte(10)
  if dp == 0x03  then
    window_shade_level_event = capabilities.windowShadeLevel.shadeLevel(dp_data)
    if dp_data == 0 then
      window_shade_val_event = capabilities.windowShade.windowShade("open")
    elseif dp_data == 100 then
      window_shade_val_event = capabilities.windowShade.windowShade("closed")
    elseif dp_data > 0 and dp_data < 100 then
      window_shade_val_event = capabilities.windowShade.windowShade("partially open")
    end
  end
  if window_shade_level_event ~= nil and window_shade_val_event ~= nil then
    device:emit_event(window_shade_level_event)
    device:emit_event(window_shade_val_event)
  end
end

local tuya_curtain_driver = {
  NAME = "tuya curtain",
  lifecycle_handlers = {
    init = init_handler,
    added = device_added,
    infoChanged = device_info_changed,
    doConfigure = do_configure
  },
  capability_handlers = {
    [capabilities.windowShade.ID] = {
      [capabilities.windowShade.commands.open.NAME] = window_shade_open,
      [capabilities.windowShade.commands.close.NAME] = window_shade_close,
      [capabilities.windowShade.commands.pause.NAME] = window_shade_pause
    },
    [capabilities.windowShadeLevel.ID] = {
      [capabilities.windowShadeLevel.commands.setShadeLevel.NAME] = window_shade_level
    },
    [capabilities.windowShadePreset.ID] = {
      [capabilities.windowShadePreset.commands.presetPosition.NAME] = window_shade_preset
    }
  },
  zigbee_handlers = {
    cluster = {
      [tuya_utils.TUYA_PRIVATE_CLUSTER] = {
        [tuya_utils.TUYA_PRIVATE_CMD_RESPONSE] = tuya_cluster_handler
      }
    }
  },
  can_handle = is_tuya_curtain
}

return tuya_curtain_driver
