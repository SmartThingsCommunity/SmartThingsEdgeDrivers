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
local ZigbeeDriver = require "st.zigbee"
local defaults = require "st.zigbee.defaults"
local clusters = require "st.zigbee.zcl.clusters"
local stDevice = require "st.device"

local log = require "log"
local zcl_clusters = require "st.zigbee.zcl.clusters"
local OnOff = zcl_clusters.OnOff

local ZIBEE_DIMMING_SWITCH_FINGERPRINTS = {
  { mfr = "REXENSE", model = "HY0002", switches = 2 },
}

--local function info_changed(self, device, event, args)
--  preferences.update_preferences(self, device, args)
--end

local do_configure = function(self, device)
  device:refresh()
  device:configure()
end

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

local function find_child(parent, ep_id)
  log.error("#####run find child#####")
  return parent:get_child_by_parent_assigned_key(string.format("%02X", ep_id))
end

local function device_init(driver, device, event)
  log.error("#####run device init#####")
  device:set_find_child(find_child)
end

--local device_init = function(self, device)
--  device:set_component_to_endpoint_fn(component_to_endpoint)
--  device:set_endpoint_to_component_fn(endpoint_to_component)
--end

local function get_children_info(device)
  for _, fingerprint in ipairs(ZIBEE_DIMMING_SWITCH_FINGERPRINTS) do
    if device:get_model() == fingerprint.model then
      return fingerprint.switches
    end
  end
end

local function create_child_devices(driver, device)
  log.error("#####run create_child_device#####")
  local switch_amount = get_children_info(device)
  local base_name = string.sub(device.label, 0, -2)
  -- Create Switch 2-4
  for i = 2, switch_amount, 1 do
    if find_child(device, i) == nil then
      local metadata = {
        type = "EDGE_CHILD",
        parent_assigned_child_key = string.format("%02X", i),
        label = base_name .. i,
        profile = "duan-switch-test1",
        parent_device_id = device.id,
        vendor_provided_label = base_name .. i,
      }
      driver:try_create_device(metadata)
      log.error("#####run try_create_device#####")
    end
  end
end

local function device_added(driver, device, event)
  log.error("#####run device_added#####")
  if device.network_type ~= stDevice.NETWORK_TYPE_CHILD then
    create_child_devices(driver, device)
  end
  if device:supports_capability_by_id(capabilities.switch.ID) then
    device:emit_event(capabilities.switch.switch({ "on" }))
    -- device:refresh()
  end
end

-------------pc driver start 20241126------------------------------
local function switch_on_handler(driver, device, command)
  log.error("#####run switch_on_handler#####")
  device:send_to_component(command.component, OnOff.server.commands.On(device))



end

local function switch_off_handler(driver, device, command)
  log.error("#####run switch_off_handler#####")
  device:send_to_component(command.component, OnOff.server.commands.Off(device))
end

local function on_off_attr_handler(driver, device, value, zb_rx)
  log.error("#####run on_off_attr_handler#####")
  local attr = capabilities.switch.switch
  device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value, value.value == false and attr.off() or attr.on())

  -- local attr = capabilities.switch.switch
  -- local event = attr.on()
  -- if value.value == false or value.value == 0 then
  --   event = attr.off()
  -- end
  -- device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value, event)

end
-------------pc driver end   20241126------------------------------

local zigbee_switch_driver_template = {
  NAME = "Zigbee REXENSE Switch",
  --  supported_capabilities = {
  --    capabilities.switch
  --  },
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
    -- infoChanged = info_changed,
    doConfigure = do_configure
  },

  -------------pc driver start 20241126------------------------------
  capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = switch_on_handler,
      [capabilities.switch.commands.off.NAME] = switch_off_handler
    }
  },
  zigbee_handlers = {
    attr = {
      [zcl_clusters.OnOff.ID] = {
        [zcl_clusters.OnOff.attributes.OnOff.ID] = on_off_attr_handler
      }
    }
  },

  -------------pc driver end   20241126------------------------------
}

defaults.register_for_default_handlers(zigbee_switch_driver_template, { native_capability_cmds_enabled = true })
local zigbee_switch = ZigbeeDriver("zigbee_switch", zigbee_switch_driver_template)
zigbee_switch:run()

