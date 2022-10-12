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
local st_device = require "st.device"
local clusters = require "st.zigbee.zcl.clusters"
local OnOff = clusters.OnOff
local SimpleMetering = clusters.SimpleMetering

local CURRENT_STATUS = "current_status"

local ZIGBEE_DUAL_METERING_SWITCH_FINGERPRINT = {
  {mfr = "Aurora", model = "DoubleSocket50AU"}
}

local function can_handle_zigbee_dual_metering_switch(opts, driver, device, ...)
  for _, fingerprint in ipairs(ZIGBEE_DUAL_METERING_SWITCH_FINGERPRINT) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local function device_added(driver, device, event)
  if device.network_type == st_device.NETWORK_TYPE_ZIGBEE then
    local name = "AURORA Outlet 2"
    local metadata = {
      type = "EDGE_CHILD",
      label = name,
      profile = "switch-power-2",
      parent_device_id = device.id,
      parent_assigned_child_key = string.format("%02X", 1),
      vendor_provided_label = name,
    }
    driver:try_create_device(metadata)
  end
end

local function find_child(parent, ep_id)
  return parent:get_child_by_parent_assigned_key(string.format("%02X", ep_id))
end

local function device_init(driver, device)
  if device.network_type == st_device.NETWORK_TYPE_ZIGBEE then
    device:set_find_child(find_child)
  end
end

local function switch_on_command_handler(driver, device, command)
  device:send(OnOff.server.commands.On(device))
  
end

local function switch_off_command_handler(driver, device, command)
  device:send(OnOff.server.commands.Off(device))
end

local function on_off_command_handler(driver, device, value, zb_rx)
  local event
  
  if value == OnOff.server.commands.On.ID then
    event = capabilities.switch.switch.on()
    device:set_field(CURRENT_STATUS, "on")
  elseif value == OnOff.server.commands.Off.ID then
    event = capabilities.switch.switch.off()
    device:set_field(CURRENT_STATUS, "off")
  end
  
  if event ~= nil then
    device:emit_event(event)
  end
end

local function do_refresh(self, device)
  device:send(OnOff.attributes.OnOff:read(device))
  device:send(SimpleMetering.attributes.Divisor:read(device))
  device:send(SimpleMetering.attributes.Multiplier:read(device))
end

local zigbee_dual_metering_switch = {
  NAME = "zigbee dual metering switch",
  zigbee_handlers = {
    cluster = {
      [OnOff.ID] = {
        [OnOff.server.commands.On.ID] = on_off_command_handler,
        [OnOff.server.commands.Off.ID] = on_off_command_handler
      }
    }
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh
    },
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = switch_on_command_handler,
      [capabilities.switch.commands.off.NAME] = switch_off_command_handler
    }
  },
  lifecycle_handlers = {
    init = device_init,
    added = device_added
  },
  can_handle = can_handle_zigbee_dual_metering_switch
}

return zigbee_dual_metering_switch
