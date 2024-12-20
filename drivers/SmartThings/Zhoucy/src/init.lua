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

local capabilities = require "st.capabilities"
local log = require "log"
local stDevice = require "st.device"
local zcl_clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"

local defaults = require "st.zigbee.defaults"
local ZigbeeDriver = require "st.zigbee"

--local Scenes = zcl_clusters.Scenes

local OnOff = zcl_clusters.OnOff

local PRIVATE_CLUSTER_ID = 0x0006
local PRIVATE_ATTRIBUTE_ID = 0x6000
local MFG_CODE = 0x1235



local FINGERPRINTS = {
  { mfr = "REXENSE", model = "HY0002", switches = 2},
}

-- local function can_handle_wallhero_switch(opts, driver, device, ...)
--  for _, fingerprint in ipairs(FINGERPRINTS) do
--    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
--     --  local subdriver = require("src")
--      return true
--    end
--  end
--  return false
-- end
----------------------------add 2024.11.28-------------------
local function switch_on_handler(driver,device,command)
log.error("#####run switch_on_handler#####");
  device:send_to_component(command.component, OnOff.server.commands.On(device))
--  device:send(OnOff.server.commands.On(device))
--  device:send(OnOff.client.commands.On(device))

end

local function switch_off_handler(driver,device,command)
log.error("#####run on_off_attr_handler#####");
  device:send_to_component(command.component, OnOff.server.commands.Off(device))
--  device:send(OnOff.server.commands.Off(device))
--  device:send(OnOff.client.commands.off(device))
end
----------------------------end 2024.11.28-------------------

----------------------------add 2024.11.29----------

local function component_to_endpoint(device, component_id)
    local ep_num = component_id:match("switch(%d)")
    return ep_num and tonumber(ep_num) or device.fingerprinted_endpoint_id
  end
   
  local function endpoint_to_component(device, ep)
    local switch_comp = string.format("switch%d", ep)
    if device.profile.components[switch_comp] ~= nil then
      return switch_comp
    else
      return "main"
   end
 end
--------------------------------end 2024.12.03----------

local function get_children_info(device)
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_model() == fingerprint.model then
      return fingerprint.switches
    end
  end
end 

local function find_child(parent, ep_id)
  log.error("######run find child#######");
  return parent:get_child_by_parent_assigned_key(string.format("%02X", ep_id))
end

local function create_child_devices(driver, device)
 log.error("#####run create_chilid_device#####");
  local switch_amount = get_children_info(device)
  local base_name = string.sub(device.label, 0, -2)
  -- Create Switch 2-4
  for i = 2, switch_amount, 1 do
    if find_child(device, i) == nil then
      local metadata = {
        type = "EDGE_CHILD",
        parent_assigned_child_key = string.format("%02X", i),
        label = base_name .. i,
        profile = "basic-switch",
        parent_device_id = device.id,
        vendor_provided_label = base_name .. i,
      }
      driver:try_create_device(metadata)
      log.error("#####run try_create_device#####");
    end
   end
  device:refresh()
end

local function device_added(driver, device)
 log.error("###### run devices_added #########");
  if device.network_type ~= stDevice.NETWORK_TYPE_CHILD then
    create_child_devices(driver, device)
  end

------------------------------add 2024.11.28----------------------
-- Set Button Capabilities for scene switches
if device:supports_capability_by_id(capabilities.switch.ID) then
  device:emit_event(capabilities.switch.switch.on())
  end
-------------------------------end 2024.11.28---------------------

end

local function device_info_changed(driver, device, event, args)
  log.error("########## run devices_info_changed##########");
  local preferences = device.preferences
  local old_preferences = args.old_st_store.preferences
  local value_map = { [true] = 0x00,[false] = 0x01 }
  if preferences ~= nil then
    local id = "stse.turnOffIndicatorLight"
    local old_value = old_preferences[id]
    local value = preferences[id]
    if value ~= nil and value ~= old_value  then
      value = value_map[value]
      local message = cluster_base.write_manufacturer_specific_attribute(device, PRIVATE_CLUSTER_ID, PRIVATE_ATTRIBUTE_ID, MFG_CODE, data_types.Uint8, value)
      device:send(message)
    end
  end
end

local function device_init(driver, device, event)
log.error("############## run devices_init ########### ");
 device:set_component_to_endpoint_fn(component_to_endpoint)
 device:set_endpoint_to_component_fn(endpoint_to_component)
  device:set_find_child(find_child)
end



local function On_Off_cluster_handler(driver, device,value, zb_rx)
  log.error("################On_Off__cluster_handler############");
  local attr = capabilities.switch.switch
  device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value, value.value == false and attr.off() or attr.on())
--  device:emit_event(capabilities.switch.switch.on())
end

local zigbeeswitch = {
  NAME = "Zigbee HEXENSE Switch",
  lifecycle_handlers = {
    added = device_added,
    init = device_init,
    infoChanged = device_info_changed
  },
----------------------add 2024.11.28------------------------------------------
  capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = switch_on_handler,
      [capabilities.switch.commands.off.NAME] = switch_off_handler
    }
  },

   zigbee_handlers = {
     attr = {
      [OnOff.ID] = {
        [OnOff.attributes.OnOff.ID] = On_Off_cluster_handler,
      }
    }
  }
  ----------------------end 2024.11.28----------------------------------------
  -- can_handle = can_handle_wallhero_switch
}
defaults.register_for_default_handlers(zigbeeswitch, {native_capability_cmds_enabled = true})
local zigbee_switch = ZigbeeDriver("zigbee_switch", zigbeeswitch)
zigbee_switch:run()
