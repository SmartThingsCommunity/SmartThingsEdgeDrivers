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
local mgmt_bind_req = require "st.zigbee.zdo.mgmt_bind_request"
local log = require "log"
local zdo_messages = require "st.zigbee.zdo"

local PowerConfiguration = clusters.PowerConfiguration
local WindowCovering = clusters.WindowCovering

-- Src_ep, buttonName
local UP_MAPPING = {
  [1] = "button1",
  [2] = "button4",
  [3] = "button7",
  [4] = "button10"
}

local DOWN_MAPPING = {
  [1] = "button3",
  [2] = "button6",
  [3] = "button9",
  [4] = "button12"
}

local STOP_MAPPING = {
  [1] = "button2",
  [2] = "button5",
  [3] = "button8",
  [4] = "button11"
}

local function build_button_handler(MAPPING, pressed_type)
  return function(driver, device, zb_rx)
    local additional_fields = {
      state_change = true
    }
    local event = pressed_type(additional_fields)
    local button_name = MAPPING[zb_rx.address_header.src_endpoint.value]
    local comp = device.profile.components[button_name]
    if comp ~= nil then
      device:emit_component_event(comp, event)
    else
      log.warn("Attempted to emit button event for unknown button: " .. button_name)
    end
  end
end

local do_configure = function(self, device)
  device:send(PowerConfiguration.attributes.BatteryPercentageRemaining:read(device):to_endpoint(0xE8))
  device:send(PowerConfiguration.attributes.BatteryPercentageRemaining:configure_reporting(device, 30, 21600, 1):to_endpoint(0xE8))
  device:send(device_management.build_bind_request(device, WindowCovering.ID, self.environment_info.hub_zigbee_eui, 1))
  device:send(device_management.build_bind_request(device, WindowCovering.ID, self.environment_info.hub_zigbee_eui, 2))
  device:send(device_management.build_bind_request(device, WindowCovering.ID, self.environment_info.hub_zigbee_eui, 3))
  device:send(device_management.build_bind_request(device, WindowCovering.ID, self.environment_info.hub_zigbee_eui, 4))
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

local somfy_situo_4_handler = {
  NAME = "SOMFY Situo 4 Remote Control",
  lifecycle_handlers = {
    doConfigure = do_configure
  },
  zigbee_handlers = {
    cluster = {
      [WindowCovering.ID] = {
        [WindowCovering.server.commands.UpOrOpen.ID] = build_button_handler(UP_MAPPING, capabilities.button.button.pushed),
        [WindowCovering.server.commands.DownOrClose.ID] = build_button_handler(DOWN_MAPPING, capabilities.button.button.pushed),
        [WindowCovering.server.commands.Stop.ID] = build_button_handler(STOP_MAPPING, capabilities.button.button.pushed)
      }
    }
  },
  can_handle = function(opts, driver, device, ...)
    return device:get_model() == "Situo 4 Zigbee"
  end
}

return somfy_situo_4_handler
