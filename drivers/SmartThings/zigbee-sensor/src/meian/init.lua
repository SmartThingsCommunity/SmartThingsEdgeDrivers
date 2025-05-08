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

local IASZone = clusters.IASZone
local IASACE = clusters.IASACE

local TUYA_MFR_HEADER = "_TZ"

local is_meian_sos_button = function(opts, driver, device)
  if device:supports_capability(capabilities.button) and string.sub(device:get_manufacturer(),1,3) == TUYA_MFR_HEADER then
    return true
  end
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

local function info_changed(driver, device, event, args)
  if device.profile.id ~= args.old_st_store.profile.id then
    local magic_spell = {0x0004, 0x0000, 0x0001, 0x0005, 0x0007, 0xfffe}
    device:send(IASZone.attributes.ZoneStatus:read(device))
    device:send(read_attribute_function(device, clusters.Basic.ID, magic_spell))
  end
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
    infoChanged = info_changed
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