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

-- Mock out globals
local data_types = require "st.zigbee.data_types"
local test = require "integration_test"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils = require "integration_test.utils"
local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local Basic = clusters.Basic

-- Constants
local PROFILE_ID = 0xFC01
local PRESENCE_LEGACY_CLUSTER = 0xFC05
local LEGACY_DEVICE_BATTERY_COMMAND = 0x00
local LEGACY_DEVICE_PRESENCE_COMMAND = 0x01
local BEEP_CMD_ID = 0x00
local MFG_CODE = 0x110A
local BEEP_SOURCE_ENDPOINT = 0x02
local BEEP_PAYLOAD = ""
local FRAME_CTRL = 0x15
local NUMBER_OF_BEEPS = 5
local BATTERY_ENDPOINT = 0x02
local PRESENCE_ENDPOINT = 0x02

local mock_simple_device = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("smartthings-arrival-sensor-v1.yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "SmartThings",
        model = "PGC410",
        server_clusters = {0x0000, 0x0001, 0x0003}
      }
    }
  }
)


local build_status_message = function(device, command, payload ,endpoint)
  local message = zigbee_test_utils.build_custom_command_id(
      device,
      PRESENCE_LEGACY_CLUSTER,
      command,
      MFG_CODE,
      payload,
      endpoint
  )

  message.body.zcl_header.frame_ctrl.value = FRAME_CTRL
  message.address_header.profile.value = PROFILE_ID

  return message
end

zigbee_test_utils.prepare_zigbee_env_info()

local add_device = function()
  test.socket.device_lifecycle:__queue_receive({ mock_simple_device.id, "added"})
  -- test.socket.capability:__expect_send(mock_simple_device:generate_test_message("main",
  --   capabilities.presenceSensor.presence("present")
  -- ))
  test.wait_for_events()
end

local function test_init()
  test.mock_device.add_test_device(mock_simple_device)
  zigbee_test_utils.init_noop_health_check_timer()
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
    "Tone capability command beep should be handled",
    function ()
      local beep_message = zigbee_test_utils.build_tx_custom_command_id(mock_simple_device, PRESENCE_LEGACY_CLUSTER, BEEP_CMD_ID, MFG_CODE, BEEP_PAYLOAD):to_endpoint(0x02)
      beep_message.body.zcl_header.frame_ctrl.value = FRAME_CTRL
      beep_message.address_header.src_endpoint.value = BEEP_SOURCE_ENDPOINT
      beep_message.address_header.profile.value = PROFILE_ID
      test.socket.capability:__queue_receive({ mock_simple_device.id, { capability = "tone", component = "main", command = "beep", args = {} } })

      for i=1,NUMBER_OF_BEEPS,1 do
        test.timer.__create_and_queue_test_time_advance_timer(i*8, "oneshot")
      end
      for i=1,NUMBER_OF_BEEPS,1 do
        test.socket.zigbee:__expect_send({
          mock_simple_device.id,
          beep_message
        })
        test.wait_for_events()
        test.mock_time.advance_time(7)
      end
    end
)

test.register_message_test(
  "Response to sensor poll should be correctly handled",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_simple_device.id, Basic.attributes.ZCLVersion:build_test_attr_report(mock_simple_device, 0x00) } -- Actual version isn't important
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_simple_device:generate_test_message("main",  capabilities.presenceSensor.presence("present"))
    }
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.register_coroutine_test(
    "Added lifecycle should be handlded",
    function ()
      add_device()
    end
)

test.register_coroutine_test(
  "Value 0x00 reported from cluster 0xFC05 should be handled as: Present",
  function()
    test.socket.zigbee:__queue_receive({
      mock_simple_device.id,
      build_status_message(mock_simple_device, LEGACY_DEVICE_PRESENCE_COMMAND, "0x1C", PRESENCE_ENDPOINT)
    })
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.capability:__expect_send(mock_simple_device:generate_test_message("main", capabilities.presenceSensor.presence("present")))
  end
)

test.register_coroutine_test(
  "Value 0x1E reported from cluster 0xFC05 should be handled as: Present, battery 100%",
  function()
    test.socket.zigbee:__queue_receive({
      mock_simple_device.id,
      build_status_message(mock_simple_device, LEGACY_DEVICE_BATTERY_COMMAND, "", BATTERY_ENDPOINT)
    })
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.capability:__expect_send(mock_simple_device:generate_test_message("main", capabilities.battery.battery(100)))
    test.socket.capability:__expect_send(mock_simple_device:generate_test_message("main", capabilities.presenceSensor.presence("present")))
  end
)

test.register_coroutine_test(
  "Value 0x1C reported from cluster 0xFC05 should be handled as: Present, battery 75%",
  function()
    test.socket.zigbee:__queue_receive({
      mock_simple_device.id,
      build_status_message(mock_simple_device, LEGACY_DEVICE_BATTERY_COMMAND, "", BATTERY_ENDPOINT)
    })
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.capability:__expect_send(mock_simple_device:generate_test_message("main", capabilities.battery.battery(75)))
    test.socket.capability:__expect_send(mock_simple_device:generate_test_message("main", capabilities.presenceSensor.presence("present")))
  end
)

test.register_coroutine_test(
  "Value 0x15 reported from cluster 0xFC05 should be handled as: Present, battery 0%",
  function()
    test.socket.zigbee:__queue_receive({
      mock_simple_device.id,
      build_status_message(mock_simple_device, LEGACY_DEVICE_BATTERY_COMMAND, "", BATTERY_ENDPOINT)
    })
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.capability:__expect_send(mock_simple_device:generate_test_message("main", capabilities.battery.battery(0)))
    test.socket.capability:__expect_send(mock_simple_device:generate_test_message("main", capabilities.presenceSensor.presence("present")))
  end
)

test.register_coroutine_test(
    "init followed by no action should result in timeout",
    function ()
      test.mock_device.add_test_device(mock_simple_device)
      test.timer.__create_and_queue_test_time_advance_timer(120, "oneshot")
      test.socket.device_lifecycle:__queue_receive({ mock_simple_device.id, "init"})
      test.wait_for_events()
      test.mock_time.advance_time(121)
      test.socket.capability:__expect_send( mock_simple_device:generate_test_message("main", capabilities.presenceSensor.presence("not present")) )
    end,
    {
      test_init = function()
        zigbee_test_utils.init_noop_health_check_timer()
      end
    }
)

test.run_registered_tests()
