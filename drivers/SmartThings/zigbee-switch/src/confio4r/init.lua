-- Copyright 2023 SmartThings
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

local stDevice = require "st.device"
local zcl_clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"

local OnOff = zcl_clusters.OnOff

local FINGERPRINTS = {
  { mfr = "Confio", model = "CT4RZB", children = 4 }
}

local function can_handle_confio4r_switch(opts, driver, device, ...)
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      local subdriver = require("confio4r")
      return true, subdriver
    end
  end
  return false
end

local function get_children_amount(device)
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_model() == fingerprint.model then
      return fingerprint.children
    end
  end
end

local function find_child(parent, ep_id)
  return parent:get_child_by_parent_assigned_key(string.format("%02X", ep_id))
end

local function create_child_devices(driver, device)
  local children_amount = get_children_amount(device)
  for i = 2, children_amount + 1, 1 do
    local device_name_without_number = string.sub(device.label, 0, -2)
    local name
    if i == 5 then
      name = string.format("%sAll OnOff", device_name_without_number)
    else
      name = string.format("%s%d", device_name_without_number, i)
    end
    if find_child(device, i) == nil then
      local metadata = {
        type = "EDGE_CHILD",
        label = name,
        profile = "basic-switch",
        parent_device_id = device.id,
        parent_assigned_child_key = string.format("%02X", i),
        vendor_provided_label = name,
      }
      driver:try_create_device(metadata)
    end
  end
  device:refresh()
end


local function switch_All_On_Off_handler(driver, device, command)
  local ep_num = 1
  if command == "All On" then
    device:send(OnOff.server.commands.On(device):to_endpoint(ep_num))
    device:send(OnOff.server.commands.On(device):to_endpoint(ep_num+1))
    device:send(OnOff.server.commands.On(device):to_endpoint(ep_num+2))
    device:send(OnOff.server.commands.On(device):to_endpoint(ep_num+3))
    device:emit_event(capabilities.switch.switch.on())
  else
    device:send(OnOff.server.commands.Off(device):to_endpoint(ep_num))
    device:send(OnOff.server.commands.Off(device):to_endpoint(ep_num+1))
    device:send(OnOff.server.commands.Off(device):to_endpoint(ep_num+2))
    device:send(OnOff.server.commands.Off(device):to_endpoint(ep_num+3))
    device:emit_event(capabilities.switch.switch.off())
  end
end

local function switch_on_handler(driver, device, command)
  device:send_to_component(command.component, zcl_clusters.OnOff.server.commands.On(device))
  device:emit_event(capabilities.switch.switch.on())
  local str = tostring(device)
  local value_in_brackets = str:match("%[([%d%w]+)%]")
  if value_in_brackets == "05" then
    switch_All_On_Off_handler(driver, device, "All On")
  end
end

local function switch_off_handler(driver, device, command)
  device:send_to_component(command.component, zcl_clusters.OnOff.server.commands.Off(device))
  device:emit_event(capabilities.switch.switch.off())
  local str = tostring(device)
  local value_in_brackets = str:match("%[([%d%w]+)%]")
  if value_in_brackets == "05" then
    switch_All_On_Off_handler(driver, device, "All Off")
  end
end

local function device_added(driver, device)
  if device.network_type ~= stDevice.NETWORK_TYPE_CHILD then
    create_child_devices(driver, device)
  end
end

local function device_init(driver, device, event)
  device:set_find_child(find_child)
end

local Confio4rSwitch = {
  NAME = "Zigbee Confio4r Switch",
  lifecycle_handlers = {
    added = device_added,
    init = device_init
  },
  capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = switch_on_handler,
      [capabilities.switch.commands.off.NAME] = switch_off_handler
    }
  },
  can_handle = can_handle_confio4r_switch
}

return Confio4rSwitch
