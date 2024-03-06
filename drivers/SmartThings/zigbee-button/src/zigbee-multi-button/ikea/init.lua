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
local constants = require "st.zigbee.constants"
local clusters = require "st.zigbee.zcl.clusters"
local device_management = require "st.zigbee.device_management"
local messages = require "st.zigbee.messages"
local mgmt_bind_resp = require "st.zigbee.zdo.mgmt_bind_response"
local mgmt_bind_req = require "st.zigbee.zdo.mgmt_bind_request"
local utils = require 'st.utils'
local zdo_messages = require "st.zigbee.zdo"
local supported_values = require "zigbee-multi-button.supported_values"

local OnOff = clusters.OnOff
local PowerConfiguration = clusters.PowerConfiguration
local Groups = clusters.Groups

local ENTRIES_READ = "ENTRIES_READ"

local IKEA_MFG = {
  { mfr = "IKEA of Sweden" },
  { mfr = "KE" },
  { mfr = "\02KE" }
}

local can_handle_ikea = function(opts, driver, device)
  for _, fingerprint in ipairs(IKEA_MFG) do
    if device:get_manufacturer() == fingerprint.mfr then
      return true
    end
  end
  return false
end

local do_configure = function(self, device)
  device:send(device_management.build_bind_request(device, PowerConfiguration.ID, self.environment_info.hub_zigbee_eui))
  device:send(device_management.build_bind_request(device, OnOff.ID, self.environment_info.hub_zigbee_eui))
  device:send(PowerConfiguration.attributes.BatteryPercentageRemaining:configure_reporting(device, 30, 21600, 1))
  -- Read binding table
  local addr_header = messages.AddressHeader(
    constants.HUB.ADDR,
    constants.HUB.ENDPOINT,
    device:get_short_address(),
    device.fingerprinted_endpoint_id,
    constants.ZDO_PROFILE_ID,
    mgmt_bind_req.BINDING_TABLE_REQUEST_CLUSTER_ID
  )
  local binding_table_req = mgmt_bind_req.MgmtBindRequest(0) -- Single argument of the start index to query the table
  local message_body = zdo_messages.ZdoMessageBody({
                                                   zdo_body = binding_table_req
                                                 })
  local binding_table_cmd = messages.ZigbeeMessageTx({
                                                     address_header = addr_header,
                                                     body = message_body
                                                   })
  device:send(binding_table_cmd)
end

local function added_handler(self, device)
  local config = supported_values.get_device_parameters(device)
  for _, component in pairs(device.profile.components) do
    local number_of_buttons = component.id == "main" and config.NUMBER_OF_BUTTONS or 1
    if config ~= nil then
      device:emit_component_event(component, capabilities.button.supportedButtonValues(config.SUPPORTED_BUTTON_VALUES), {visibility = { displayed = false }})
    else
      device:emit_component_event(component, capabilities.button.supportedButtonValues({"pushed", "held"}, {visibility = { displayed = false }}))
    end
    device:emit_component_event(component, capabilities.button.numberOfButtons({value = number_of_buttons}))
  end
  device:send(PowerConfiguration.attributes.BatteryPercentageRemaining:read(device))
  device:emit_event(capabilities.button.button.pushed({state_change = false}))
end

local function zdo_binding_table_handler(driver, device, zb_rx)
  for _, binding_table in pairs(zb_rx.body.zdo_body.binding_table_entries) do
    if binding_table.dest_addr_mode.value == binding_table.DEST_ADDR_MODE_SHORT then
      -- send add hub to zigbee group command
      driver:add_hub_to_zigbee_group(binding_table.dest_addr.value)
      return
    end
  end

  local entries_read = device:get_field(ENTRIES_READ) or 0
  entries_read = entries_read + zb_rx.body.zdo_body.binding_table_list_count.value

  -- if the device still has binding table entries we haven't read, we need
  -- to go ask for them until we've read them all
  if entries_read < zb_rx.body.zdo_body.total_binding_table_entry_count.value then
    device:set_field(ENTRIES_READ, entries_read)

    -- Read binding table
    local addr_header = messages.AddressHeader(
      constants.HUB.ADDR,
      constants.HUB.ENDPOINT,
      device:get_short_address(),
      device.fingerprinted_endpoint_id,
      constants.ZDO_PROFILE_ID,
      mgmt_bind_req.BINDING_TABLE_REQUEST_CLUSTER_ID
    )
    local binding_table_req = mgmt_bind_req.MgmtBindRequest(entries_read) -- Single argument of the start index to query the table
    local message_body = zdo_messages.ZdoMessageBody({ zdo_body = binding_table_req })
    local binding_table_cmd = messages.ZigbeeMessageTx({ address_header = addr_header, body = message_body })
    device:send(binding_table_cmd)
  else
    driver:add_hub_to_zigbee_group(0x0000) -- fallback if no binding table entries found
    device:send(Groups.commands.AddGroup(device, 0x0000))
  end
end

local battery_perc_attr_handler = function(driver, device, value, zb_rx)
  device:emit_event(capabilities.battery.battery(utils.clamp_value(value.value, 0, 100)))
end

local ikea_of_sweden = {
  NAME = "IKEA Sweden",
  lifecycle_handlers = {
    doConfigure = do_configure,
    added = added_handler
  },
  zigbee_handlers = {
    zdo = {
      [mgmt_bind_resp.MGMT_BIND_RESPONSE] = zdo_binding_table_handler
    },
    attr = {
      [PowerConfiguration.ID] = {
        [PowerConfiguration.attributes.BatteryPercentageRemaining.ID] = battery_perc_attr_handler
      }
    }
  },
  sub_drivers = {
    require("zigbee-multi-button.ikea.TRADFRI_remote_control"),
    require("zigbee-multi-button.ikea.TRADFRI_on_off_switch"),
    require("zigbee-multi-button.ikea.TRADFRI_open_close_remote")
  },
  can_handle = can_handle_ikea
}

return ikea_of_sweden
