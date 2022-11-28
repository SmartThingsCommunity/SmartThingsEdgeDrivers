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

local constants = require "st.zigbee.constants"
local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local device_management = require "st.zigbee.device_management"
local messages = require "st.zigbee.messages"
local mgmt_bind_resp = require "st.zigbee.zdo.mgmt_bind_response"
local mgmt_bind_req = require "st.zigbee.zdo.mgmt_bind_request"
local zdo_messages = require "st.zigbee.zdo"
local battery_defaults = require "st.zigbee.defaults.battery_defaults"

local OnOff = clusters.OnOff
local PowerConfiguration = clusters.PowerConfiguration
local Groups = clusters.Groups

local IKEA_MOTION_SENSOR_FINGERPRINTS = {
    { mfr = "IKEA of Sweden", model = "TRADFRI motion sensor" }
}

local MOTION_RESET_TIMER = "motionResetTimer"

local function on_with_timed_off_command_handler(driver, device, zb_rx)
  local motion_reset_timer = device:get_field(MOTION_RESET_TIMER)
  local on_time_secs = zb_rx.body.zcl_body.on_time.value and zb_rx.body.zcl_body.on_time.value / 10 or 180
  device:emit_event(capabilities.motionSensor.motion.active())
  if motion_reset_timer then
    device.thread:cancel_timer(motion_reset_timer)
    device:set_field(MOTION_RESET_TIMER, nil)
  end
  local reset_motion_status = function()
    device:emit_event(capabilities.motionSensor.motion.inactive())
  end
  motion_reset_timer = device.thread:call_with_delay(on_time_secs, reset_motion_status)
  device:set_field(MOTION_RESET_TIMER, motion_reset_timer)
end

local is_ikea_motion = function(opts, driver, device)
    for _, fingerprint in ipairs(IKEA_MOTION_SENSOR_FINGERPRINTS) do
        if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
            return true
        end
    end
    return false
end

local function zdo_binding_table_handler(driver, device, zb_rx)
  for _, binding_table in pairs(zb_rx.body.zdo_body.binding_table_entries) do
    if binding_table.dest_addr_mode.value == binding_table.DEST_ADDR_MODE_SHORT then
      -- send add hub to zigbee group command
      driver:add_hub_to_zigbee_group(binding_table.dest_addr.value)
      return
    end
  end
  driver:add_hub_to_zigbee_group(0x0000) -- fallback if no binding table entries found
  device:send(Groups.commands.AddGroup(device, 0x0000))
end

local function device_added(self, device)
  device:refresh()
  -- Ikea Motion Sensor doesn't report current status during pairing process
  -- so fake event is needed for default status
  -- device:emit_event(capabilities.motionSensor.motion.inactive())
end

local do_configure = function(self, device)
  device:send(device_management.build_bind_request(device, PowerConfiguration.ID, self.environment_info.hub_zigbee_eui))
  device:send(device_management.build_bind_request(device, OnOff.ID, self.environment_info.hub_zigbee_eui))
  device:send(PowerConfiguration.attributes.BatteryVoltage:configure_reporting(device, 30, 21600, 1))
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

local ikea_motion_sensor = {
  NAME = "ikea motion sensor",
  zigbee_handlers = {
    cluster = {
      [OnOff.ID] = {
          [OnOff.server.commands.OnWithTimedOff.ID] = on_with_timed_off_command_handler
      }
    },
    zdo = {
      [mgmt_bind_resp.MGMT_BIND_RESPONSE] = zdo_binding_table_handler
    }
  },
  lifecycle_handlers = {
    init = battery_defaults.build_linear_voltage_init(2.1, 3.0),
    added = device_added,
    doConfigure = do_configure
  },
  can_handle = is_ikea_motion
}

return ikea_motion_sensor
