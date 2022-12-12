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
local t_utils = require "integration_test.utils"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local PowerConfiguration = clusters.PowerConfiguration
local OnOff = clusters.OnOff
local Basic = clusters.Basic

local mock_device = test.mock_device.build_test_zigbee_device(
  { profile = t_utils.get_profile_definition("valve-battery-powerSource.yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "Sinope Technologies",
        model = "VA4220ZB",
        server_clusters = {0x0000, 0x0001, 0x0006}
      }
    }
  }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device)
  zigbee_test_utils.init_noop_health_check_timer()
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Added event should generate expected messages",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      PowerConfiguration.attributes.BatteryVoltage:read(mock_device)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      OnOff.attributes.OnOff:read(mock_device)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      Basic.attributes.PowerSource:read(mock_device)
    })
  end
)

test.register_coroutine_test(
  "Configure event should generate expected messages",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      PowerConfiguration.attributes.BatteryVoltage:read(mock_device)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      OnOff.attributes.OnOff:read(mock_device)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      Basic.attributes.PowerSource:read(mock_device)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      PowerConfiguration.attributes.BatteryVoltage:configure_reporting(mock_device, 30, 21600, 1)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, PowerConfiguration.ID)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      OnOff.attributes.OnOff:configure_reporting(mock_device, 0, 600, 1)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, OnOff.ID)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      Basic.attributes.PowerSource:configure_reporting(mock_device, 5, 600, 1)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, Basic.ID)
    })
    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)

test.register_coroutine_test(
  "Refresh should generate expected messages",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.capability:__queue_receive({ mock_device.id, { capability = "refresh", component = "main", command = "refresh", args = {} } })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      PowerConfiguration.attributes.BatteryVoltage:read(mock_device)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      OnOff.attributes.OnOff:read(mock_device)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      Basic.attributes.PowerSource:read(mock_device)
    })
  end
)

test.register_coroutine_test(
  "Battery voltage events should generate expected messages",
  function()
    test.socket.zigbee:__queue_receive({ mock_device.id, PowerConfiguration.attributes.BatteryVoltage:build_test_attr_report(mock_device, 55) })
    test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.battery.battery(20)) )
  end
)

test.register_coroutine_test(
  "Battery voltage events should handle 0 percent",
  function()
    test.socket.zigbee:__queue_receive({ mock_device.id, PowerConfiguration.attributes.BatteryVoltage:build_test_attr_report(mock_device, 0) })
    test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.battery.battery(0)) )
  end
)

test.run_registered_tests()
