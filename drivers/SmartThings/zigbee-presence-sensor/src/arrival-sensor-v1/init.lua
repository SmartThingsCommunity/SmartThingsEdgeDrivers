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

-- Zigbee Spec Utils
local zcl_messages     = require "st.zigbee.zcl"
local messages         = require "st.zigbee.messages"
local generic_body     = require "st.zigbee.generic_body"
local zb_const         = require "st.zigbee.constants"
local data_types       = require "st.zigbee.data_types"
local utils            = require "st.utils"

-- Capabilities
local capabilities     = require "st.capabilities"
local Tone             = capabilities.tone
local PresenceSensor   = capabilities.presenceSensor
local SignalStrength   = capabilities.signalStrength
local Battery          = capabilities.battery

-- Constants
local PROFILE_ID = 0xFC01
local PRESENCE_LEGACY_CLUSTER = 0xFC05
local BEEP_CMD_ID = 0x00
local CHECKIN_CMD_ID = 0x01
local DATA_TYPE = 0x00
local MFG_CODE = 0x110A
local BEEP_DESTINATION_ENDPOINT = 0x02
local BEEP_SOURCE_ENDPOINT = 0x02
local BEEP_PAYLOAD = ""
local FRAME_CTRL = 0x15

local NUMBER_OF_BEEPS = 5
local LEGACY_DEVICE_BATTERY_COMMAND = 0x00
local LEGACY_DEVICE_PRESENCE_COMMAND = 0x01
local LEGACY_DEVICE_PRESENCE_REPORT_EXT = 0x02
local presence_utils = require "presence_utils"

local CHECKIN_INTERVAL = 20 -- seconds

local function arrival_sensor_v1_can_handle(opts, driver, device, ...)
  return device:get_model() ~= "tagv4"
end

local function legacy_battery_handler(self, device, zb_rx)
  local battery_value = string.byte(zb_rx.body.zcl_body.body_bytes)
  local divisor = 10
  local battery_intermediate = ((battery_value / divisor) - 2.2) * 125
  local battery_percentage = utils.round(utils.clamp_value(battery_intermediate, 0, 100))
  device:emit_event(Battery.battery(battery_percentage))
end

local function create_beep_message(device)
  local header_args = {
    cmd =  data_types.ZCLCommandId(BEEP_CMD_ID)
  }
  header_args.mfg_code = data_types.validate_or_build_type(MFG_CODE, data_types.Uint16, "mfg_code")
  local zclh = zcl_messages.ZclHeader(header_args)
  zclh.frame_ctrl:set_cluster_specific()
  zclh.frame_ctrl:set_mfg_specific()
  zclh.frame_ctrl:set_disable_default_response()

  local addrh = messages.AddressHeader(
    zb_const.HUB.ADDR,
    BEEP_SOURCE_ENDPOINT,
    device:get_short_address(),
    BEEP_DESTINATION_ENDPOINT,
    PROFILE_ID,
    PRESENCE_LEGACY_CLUSTER
  )

  local payload_body = generic_body.GenericBody(BEEP_PAYLOAD)

  local message_body = zcl_messages.ZclMessageBody({
    zcl_header = zclh,
    zcl_body = payload_body
  })

  local beep_message = messages.ZigbeeMessageTx({
    address_header = addrh,
    body = message_body
  })
  return beep_message
end

local function beep_handler(self, device, command)
  local beep_message = create_beep_message(device)
  device:send(beep_message)
  for i=1,(NUMBER_OF_BEEPS),1 do
    device.thread:call_with_delay(
      i*7,
      function()
        device:send(beep_message)
      end
    )
  end
end

local function added_handler(self, device)
  -- device:emit_event(PresenceSensor.presence("present"))
end

local function init_handler(self, device, event, args)
  device:set_field(
    presence_utils.PRESENCE_CALLBACK_CREATE_FN,
    function(device)
      return device.thread:call_with_delay(
              3 * CHECKIN_INTERVAL + 1,
              function()
                device:emit_event(PresenceSensor.presence("not present"))
                device:set_field(presence_utils.PRESENCE_CALLBACK_TIMER, nil)
              end
      )
    end
  )
  presence_utils.create_presence_timeout(device)
end

local arrival_sensor_v1 = {
  NAME = "Arrival Sensor v1",
  zigbee_handlers = {
    cluster = {
      [PRESENCE_LEGACY_CLUSTER] = {
        [LEGACY_DEVICE_BATTERY_COMMAND] = legacy_battery_handler
      }
    }
  },
  capability_handlers = {
    [Tone.ID] = {
      [Tone.commands.beep.NAME] = beep_handler
    }
  },
  lifecycle_handlers = {
    added = added_handler,
    init = init_handler
  },
  can_handle = arrival_sensor_v1_can_handle
}

return arrival_sensor_v1
