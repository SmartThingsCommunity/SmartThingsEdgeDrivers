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
      }
    },
    {
      inner_block_ordering = "relaxed"
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

local add_device = function()
  test.socket.device_lifecycle:__queue_receive({ mock_simple_device.id, "added"})
  -- test.socket.capability:__expect_send(mock_simple_device:generate_test_message("main",
  --   capabilities.presenceSensor.presence("present")
  -- ))
  test.socket.zigbee:__expect_send({
    mock_simple_device.id,
    PowerConfiguration.attributes.BatteryVoltage:read(mock_simple_device)
  })
  test.wait_for_events()
end

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
    test.socket.capability:__set_channel_ordering("relaxed")
    add_device()
    for voltage, batt_perc in pairs(battery_test_map[mock_simple_device:get_manufacturer()]) do
      local powerConfigurationMessage = PowerConfiguration.attributes.BatteryVoltage:build_test_attr_report(mock_simple_device, voltage)
      test.socket.zigbee:__queue_receive({ mock_simple_device.id, powerConfigurationMessage })
      test.socket.capability:__expect_send( mock_simple_device:generate_test_message("main", capabilities.battery.battery(batt_perc)) )
      test.socket.capability:__expect_send( mock_simple_device:generate_test_message("main", capabilities.presenceSensor.presence.present()))
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
    test.socket.capability:__set_channel_ordering("relaxed")
    add_device()
    test.socket.zigbee:__queue_receive({
      mock_simple_device.id,
      build_config_response_msg(PowerConfiguration.ID, 0x00)
    })
    test.socket.capability:__expect_send( mock_simple_device:generate_test_message("main", capabilities.presenceSensor.presence("present")))
    for voltage, batt_perc in pairs(battery_test_map[mock_simple_device:get_manufacturer()]) do
      local powerConfigurationMessage = PowerConfiguration.attributes.BatteryVoltage:build_test_attr_report(mock_simple_device, voltage)
      test.socket.zigbee:__queue_receive({ mock_simple_device.id, powerConfigurationMessage })
      test.socket.capability:__expect_send( mock_simple_device:generate_test_message("main", capabilities.presenceSensor.presence("present")))
      test.socket.capability:__expect_send( mock_simple_device:generate_test_message("main", capabilities.battery.battery(batt_perc)) )
      test.wait_for_events()
    end
  end
)

test.register_coroutine_test(
    "Added lifecycle should be handlded",
    function ()
      add_device()
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


test.register_coroutine_test(
  "Device should be marked not present when default check interval elapses without a battery report",
  function()
    test.socket.capability:__set_channel_ordering("relaxed")
    add_device()
    -- Have a timer for the no-communication timeout
    test.timer.__create_and_queue_never_fire_timer("oneshot")
    test.socket.zigbee:__queue_receive({
      mock_simple_device.id,
      build_config_response_msg(PowerConfiguration.ID, 0x00)
    })
    test.socket.capability:__expect_send( mock_simple_device:generate_test_message("main", capabilities.presenceSensor.presence.present()))
    test.wait_for_events()
    test.timer.__create_and_queue_test_time_advance_timer(120, "oneshot")
    --test.timer.__create_and_queue_never_fire_timer("oneshot")
    local powerConfigurationMessage = PowerConfiguration.attributes.BatteryVoltage:build_test_attr_report(mock_simple_device, 27)
    powerConfigurationMessage.lqi = data_types.Uint8(50)
    powerConfigurationMessage.rssi = data_types.Int8(-50)
    test.socket.zigbee:__queue_receive({ mock_simple_device.id, powerConfigurationMessage })
    test.socket.capability:__expect_send( mock_simple_device:generate_test_message("main", capabilities.presenceSensor.presence.present()) )
    test.socket.capability:__expect_send( mock_simple_device:generate_test_message("main", capabilities.battery.battery(100)) )
    test.wait_for_events()
    test.mock_time.advance_time(121)
    test.socket.capability:__expect_send( mock_simple_device:generate_test_message("main", capabilities.presenceSensor.presence("not present")) )
  end
)

test.register_coroutine_test(
  "Device should be marked not present when non-default check interval elapses without a battery report",
  function()
    test.timer.__create_and_queue_never_fire_timer("interval", "polling_schedule")
    test.socket.capability:__set_channel_ordering("relaxed")
    add_device()
    test.socket.device_lifecycle():__queue_receive(mock_simple_device:generate_info_changed({preferences = {checkInterval = 300}}))
    test.wait_for_events()
    test.socket.zigbee:__queue_receive({
      mock_simple_device.id,
      build_config_response_msg(PowerConfiguration.ID, 0x00)
    })
    test.socket.capability:__expect_send( mock_simple_device:generate_test_message("main", capabilities.presenceSensor.presence("present")) )
    test.wait_for_events()
    test.timer.__create_and_queue_test_time_advance_timer(300, "oneshot")
    local powerConfigurationMessage = PowerConfiguration.attributes.BatteryVoltage:build_test_attr_report(mock_simple_device, 27)
    test.socket.zigbee:__queue_receive({ mock_simple_device.id, powerConfigurationMessage })
    test.socket.capability:__expect_send( mock_simple_device:generate_test_message("main", capabilities.presenceSensor.presence("present")) )
    test.socket.capability:__expect_send( mock_simple_device:generate_test_message("main", capabilities.battery.battery(100)) )
    test.wait_for_events()
    test.mock_time.advance_time(200)
    test.timer.__create_and_queue_test_time_advance_timer(300, "oneshot")
    test.socket.zigbee:__queue_receive({ mock_simple_device.id, powerConfigurationMessage })
    test.socket.capability:__expect_send( mock_simple_device:generate_test_message("main", capabilities.presenceSensor.presence("present")) )
    test.socket.capability:__expect_send( mock_simple_device:generate_test_message("main", capabilities.battery.battery(100)) )
    test.wait_for_events()
    test.mock_time.advance_time(305)
    test.socket.capability:__expect_send( mock_simple_device:generate_test_message("main", capabilities.presenceSensor.presence("not present")) )
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "Device should configure necessary attributes",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_simple_device.id, "doConfigure" })
    test.socket.zigbee:__set_channel_ordering("relaxed")
    mock_simple_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    test.socket.zigbee:__expect_send({
      mock_simple_device.id,
      PowerConfiguration.attributes.BatteryVoltage:read(mock_simple_device)
    })
    test.socket.zigbee:__expect_send({
      mock_simple_device.id,
      PowerConfiguration.attributes.BatteryVoltage:configure_reporting(
        mock_simple_device,
        1,
        21,
        1
      )
    })
    test.socket.zigbee:__expect_send({
      mock_simple_device.id,
      zigbee_test_utils.build_bind_request(
        mock_simple_device,
        zigbee_test_utils.mock_hub_eui,
        PowerConfiguration.ID
      )
    })
  end
)

test.run_registered_tests()
