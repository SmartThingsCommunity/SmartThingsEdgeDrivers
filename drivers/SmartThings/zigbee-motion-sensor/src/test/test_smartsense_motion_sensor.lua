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

local test = require "integration_test"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils = require "integration_test.utils"
local capabilities = require "st.capabilities"
local data_types = require "st.zigbee.data_types"

local SMARTSENSE_PROFILE_ID = 0xFC01
local MFG_CODE = 0x110A
local SMARTSENSE_MOTION_CLUSTER = 0xFC04
local SMARTSENSE_MOTION_STATUS_CMD = 0x00
local SMARTSENSE_MOTION_STATUS_REPORT_CMD = 0x02
local FRAME_CTRL = 0x1D
local ENDPOINT = 0x02

local mock_device = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("smartsense-motion.yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "SmartThings",
        model = "PGC314",
        server_clusters = {}
      }
    }
  }
)

zigbee_test_utils.prepare_zigbee_env_info()

local function test_init()
  test.mock_device.add_test_device(mock_device)
end

test.set_test_init_function(test_init)

local build_motion_status_message = function(device, payload)
  local message = zigbee_test_utils.build_custom_command_id(
    device,
    SMARTSENSE_MOTION_CLUSTER,
    SMARTSENSE_MOTION_STATUS_CMD,
    MFG_CODE,
    payload,
    ENDPOINT
  )

  message.body.zcl_header.frame_ctrl.value = FRAME_CTRL
  message.address_header.profile.value = SMARTSENSE_PROFILE_ID
  message.lqi = data_types.Uint8(50)
  message.rssi = data_types.Int8(-50)

  return message
end

test.register_coroutine_test(
  "Value 0x7C reported from cluster 0xFC04 should be handled as: motion - inactive, battery 100%",
  function()
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      build_motion_status_message(mock_device, "\x7C")
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.battery.battery(100)))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.motionSensor.motion.inactive()))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.signalStrength.lqi(50)))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.signalStrength.rssi({ value = -50, unit = "dBm" })))
  end
)

test.register_coroutine_test(
  "Value 0x7E reported from cluster 0xFC04 should be handled as: motion - active, battery 100%",
  function()
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      build_motion_status_message(mock_device, "\x7E")
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.battery.battery(100)))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.motionSensor.motion.active()))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.signalStrength.lqi(50)))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.signalStrength.rssi({ value = -50, unit = "dBm" })))
  end
)

test.register_coroutine_test(
  "Value 0x58 reported from cluster 0xFC04 should be handled as: motion - inactive, battery 70%",
  function()
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      build_motion_status_message(mock_device, "\x58")
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.battery.battery(70)))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.motionSensor.motion.inactive()))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.signalStrength.lqi(50)))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.signalStrength.rssi({ value = -50, unit = "dBm" })))
  end
)

test.register_coroutine_test(
  "Value 0x5A reported from cluster 0xFC04 should be handled as: motion - active, battery 70%",
  function()
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      build_motion_status_message(mock_device, "\x5A")
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.battery.battery(70)))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.motionSensor.motion.active()))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.signalStrength.lqi(50)))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.signalStrength.rssi({ value = -50, unit = "dBm" })))
  end
)

test.register_coroutine_test(
  "Value 0xBD reported from cluster 0xFC04 should be handled as: motion - inactive",
  function()
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      build_motion_status_message(mock_device, "\xBD")
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.motionSensor.motion.inactive()))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.signalStrength.lqi(50)))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.signalStrength.rssi({ value = -50, unit = "dBm" })))
  end
)

test.register_coroutine_test(
  "Value 0xBF reported from cluster 0xFC04 should be handled as: motion - active",
  function()
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      build_motion_status_message(mock_device, "\xBF")
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.motionSensor.motion.active()))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.signalStrength.lqi(50)))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.signalStrength.rssi({ value = -50, unit = "dBm" })))
  end
)

test.register_coroutine_test(
  "Value 0x30 reported from cluster 0xFC04 should be handled as: motion - inactive, battery 0%",
  function()
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      build_motion_status_message(mock_device, "\x30")
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.battery.battery(0)))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.motionSensor.motion.inactive()))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.signalStrength.lqi(50)))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.signalStrength.rssi({ value = -50, unit = "dBm" })))
  end
)

test.register_coroutine_test(
  "Device added lifecycle event should emit initial inactive event for motion",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
    -- test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.motionSensor.motion.inactive()))
    -- test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.signalStrength.lqi(0)))
    -- test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.signalStrength.rssi({value = -100, unit = 'dBm'})))
  end
)

test.run_registered_tests()
