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
local test = require "integration_test"
local clusters = require "st.zigbee.zcl.clusters"
local Basic = clusters.Basic
local IdentifyCluster = clusters.Identify
local PowerConfiguration = clusters.PowerConfiguration
local zcl_global_commands  = require "st.zigbee.zcl.global_commands"
local capabilities = require "st.capabilities"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils = require "integration_test.utils"

-- Needed for building ConfigureReportingResponse msg
local messages = require "st.zigbee.messages"
local zb_const = require "st.zigbee.constants"
local config_reporting_response = require "st.zigbee.zcl.global_commands.configure_reporting_response"
local data_types = require "st.zigbee.data_types"
local zcl_messages = require "st.zigbee.zcl"

local mock_simple_device = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("smartthings-arrival-sensor.yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "SmartThings",
        model = "tagv4",
        server_clusters = {0x0000, 0x0001, 0x0003}
      }
    }
  }
)

zigbee_test_utils.prepare_zigbee_env_info()

local function test_init()
  test.mock_device.add_test_device(mock_simple_device)
  zigbee_test_utils.init_noop_health_check_timer()
end

local function build_config_response_msg(cluster, status)
  local addr_header = messages.AddressHeader(
    mock_simple_device:get_short_address(),
    mock_simple_device.fingerprinted_endpoint_id,
    zb_const.HUB.ADDR,
    zb_const.HUB.ENDPOINT,
    zb_const.HA_PROFILE_ID, 
    cluster
  )
  local config_response_body = config_reporting_response.ConfigureReportingResponse({}, status)
  local zcl_header = zcl_messages.ZclHeader({
    cmd = data_types.ZCLCommandId(config_response_body.ID)
  })
  local message_body = zcl_messages.ZclMessageBody({
    zcl_header = zcl_header,
    zcl_body = config_response_body
  })
  return messages.ZigbeeMessageRx({
    address_header = addr_header,
    body = message_body
  })
end

test.set_test_init_function(test_init)

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
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_simple_device:generate_test_message("main",  capabilities.signalStrength.lqi({value = 0}))
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_simple_device:generate_test_message("main",  capabilities.signalStrength.rssi({value = 0, unit = 'dBm'}))
      }
    }
)

test.register_message_test(
    "Tone capability command beep should be handled",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_simple_device.id, { capability = "tone", component = "main", command = "beep", args = { } } }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_simple_device.id, IdentifyCluster.server.commands.Identify(mock_simple_device, 0x05) }
      }
    }
)

test.register_coroutine_test(
  "Battery Voltage test cases when polling from hub",
  function()
    local battery_test_map = {
      ["SmartThings"] = {
        [27] = 100,
        [26] = 100,
        [25] = 90,
        [23] = 70,
        [21] = 50,
        [19] = 30,
        [17] = 15,
        [16] = 1,
        [15] = 0
      }
    }
    test.socket.device_lifecycle:__queue_receive({ mock_simple_device.id, "added"})
    test.socket.capability:__expect_send( mock_simple_device:generate_test_message("main", capabilities.presenceSensor.presence("present")) )
    test.socket.zigbee:__expect_send({
      mock_simple_device.id,
      PowerConfiguration.attributes.BatteryVoltage:read(mock_simple_device)
    })
    test.wait_for_events()
    for voltage, batt_perc in pairs(battery_test_map[mock_simple_device:get_manufacturer()]) do
      test.socket.zigbee:__queue_receive({ mock_simple_device.id, PowerConfiguration.attributes.BatteryVoltage:build_test_attr_report(mock_simple_device, voltage) })
      test.socket.capability:__expect_send( mock_simple_device:generate_test_message("main", capabilities.battery.battery(batt_perc)) )
      test.wait_for_events()
    end
  end
)

test.register_coroutine_test(
  "Battery Voltage test cases when presence based on battery reports",
  function()
    local battery_test_map = {
      ["SmartThings"] = {
        [27] = 100,
        [26] = 100,
        [25] = 90,
        [23] = 70,
        [21] = 50,
        [19] = 30,
        [17] = 15,
        [16] = 1,
        [15] = 0
      }
    }
    test.socket.device_lifecycle:__queue_receive({ mock_simple_device.id, "added" })
    test.socket.capability:__expect_send( mock_simple_device:generate_test_message("main", capabilities.presenceSensor.presence("present")) )
    test.socket.zigbee:__expect_send({
      mock_simple_device.id,
      PowerConfiguration.attributes.BatteryVoltage:read(mock_simple_device)
    })
    test.wait_for_events()
    test.socket.zigbee:__queue_receive({ 
      mock_simple_device.id,
      build_config_response_msg(PowerConfiguration.ID, 0x00)
    })
    for voltage, batt_perc in pairs(battery_test_map[mock_simple_device:get_manufacturer()]) do
      test.socket.zigbee:__queue_receive({ mock_simple_device.id, PowerConfiguration.attributes.BatteryVoltage:build_test_attr_report(mock_simple_device, voltage) })
      test.socket.capability:__expect_send( mock_simple_device:generate_test_message("main", capabilities.presenceSensor.presence("present")) )
      test.socket.capability:__expect_send( mock_simple_device:generate_test_message("main", capabilities.signalStrength.lqi({value = 0})) )
      test.socket.capability:__expect_send( mock_simple_device:generate_test_message("main", capabilities.signalStrength.rssi({value = 0, unit = 'dBm'})) )
      test.socket.capability:__expect_send( mock_simple_device:generate_test_message("main", capabilities.battery.battery(batt_perc)) )
      test.wait_for_events()
    end
    
  end
)

test.register_coroutine_test(
  "Added lifecycle should be handlded",
  function ()
    test.socket.device_lifecycle:__queue_receive({ mock_simple_device.id, "added"})
    test.socket.capability:__expect_send(mock_simple_device:generate_test_message("main",
      capabilities.presenceSensor.presence("present")
    ))
    test.socket.zigbee:__expect_send({
      mock_simple_device.id,
      PowerConfiguration.attributes.BatteryVoltage:read(mock_simple_device)
    })
  end
)

test.run_registered_tests()
