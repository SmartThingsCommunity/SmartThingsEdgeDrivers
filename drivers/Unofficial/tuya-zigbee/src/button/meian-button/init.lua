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

local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local read_attribute = require "st.zigbee.zcl.global_commands.read_attribute"
local constants = require "st.zigbee.constants"
local zcl_messages = require "st.zigbee.zcl"
local data_types = require "st.zigbee.data_types"
local messages = require "st.zigbee.messages"
local defaults = require "st.zigbee.defaults"
local PowerConfiguration = clusters.PowerConfiguration

local IASACE = clusters.IASACE

local FINGERPRINTS = {
  { mfr = "_TZ3000_pkfazisv", model = "TS0215A"}
}

local function is_meian_sos_button(opts, driver, device)
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local function read_attribute_function(device, cluster_id, attr_id)
  local read_body = read_attribute.ReadAttribute( attr_id )
  local zclh = zcl_messages.ZclHeader({
    cmd = data_types.ZCLCommandId(read_attribute.ReadAttribute.ID)
  })
  local addrh = messages.AddressHeader(
    constants.HUB.ADDR,
    constants.HUB.ENDPOINT,
    device:get_short_address(),
    device:get_endpoint(cluster_id),
    constants.HA_PROFILE_ID,
    cluster_id
  )
  local message_body = zcl_messages.ZclMessageBody({
    zcl_header = zclh,
    zcl_body = read_body
  })
  return messages.ZigbeeMessageTx({
    address_header = addrh,
    body = message_body
  })
end

local function added_handler(driver, device, event, args)
  device:emit_event(capabilities.button.supportedButtonValues({"pushed"}, {visibility = { displayed = false }}))
  device:emit_event(capabilities.button.numberOfButtons({value = 1}, {visibility = { displayed = false }}))
  device:emit_event(capabilities.button.button.pushed({state_change = false}))

  local magic_spell = {0x0004, 0x0000, 0x0001, 0x0005, 0x0007, 0xfffe}
  device:send(read_attribute_function(device, clusters.Basic.ID, magic_spell))
  device:send(PowerConfiguration.attributes.BatteryPercentageRemaining:read(device))
end

local ias_ace_emergency_handler = function(driver, device)
  device:emit_event(capabilities.button.button.pushed({ state_change = true }))
end

local meian_sos_button_handler = {
  NAME = "Meian Sos Button",
  supported_capabilities = {
    capabilities.battery,
    capabilities.button,
    capabilities.refresh
  },
  lifecycle_handlers = {
    added = added_handler
  },
  zigbee_handlers = {
    cluster = {
      [IASACE.ID] = {
        [IASACE.server.commands.Emergency.ID] = ias_ace_emergency_handler
      }
    }
  },
  can_handle = is_meian_sos_button
}
defaults.register_for_default_handlers(meian_sos_button_handler, meian_sos_button_handler.supported_capabilities)
return meian_sos_button_handler