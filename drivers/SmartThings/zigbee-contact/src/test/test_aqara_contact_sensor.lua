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

local clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local capabilities = require "st.capabilities"

local OnOff = clusters.OnOff
local PowerConfiguration = clusters.PowerConfiguration

local MFG_CODE = 0x115F
local PRIVATE_CLUSTER_ID = 0xFCC0
local PRIVATE_ATTRIBUTE_ID = 0x0009
local PRIVATE_HEART_BATTERY_ENERGY_ID = 0x00F7

local mock_device = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("contact-batteryLevel.yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "LUMI",
        model = "lumi.magnet.agl02",
        server_clusters = { PRIVATE_CLUSTER_ID, PowerConfiguration.ID, OnOff.ID }
      }
    }
  }
)

zigbee_test_utils.prepare_zigbee_env_info()

local function test_init()
  test.mock_device.add_test_device(mock_device)
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "doConfigure lifecycle handler",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
    test.socket.zigbee:__expect_send({ mock_device.id, zigbee_test_utils.build_bind_request(mock_device,
    zigbee_test_utils.mock_hub_eui, PowerConfiguration.ID) })
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        PowerConfiguration.attributes.BatteryVoltage:configure_reporting(mock_device, 30, 3600, 1)
      }
    )
    test.socket.zigbee:__expect_send({ mock_device.id, zigbee_test_utils.build_bind_request(mock_device,
    zigbee_test_utils.mock_hub_eui, OnOff.ID) })
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        OnOff.attributes.OnOff:configure_reporting(mock_device, 30, 3600, 1)
      }
    )
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, PRIVATE_ATTRIBUTE_ID, MFG_CODE
      , data_types.Uint8, 1) })
    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)

test.register_coroutine_test(
  "added lifecycle handler",
  function()
    -- The initial contactSensor event should be send during the device's first time onboarding
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.batteryLevel.type("CR1632")))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.batteryLevel.quantity(1)))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.batteryLevel.battery("normal")))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.contactSensor.contact.open()))
    test.wait_for_events()
    -- Avoid sending the initial contactSensor event after driver switch-over, as the switch-over event itself re-triggers the added lifecycle.
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.batteryLevel.type("CR1632")))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.batteryLevel.quantity(1)))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.batteryLevel.battery("normal")))
  end
)

test.register_coroutine_test(
  "heartbeat battery events - normal status",
  function()
    local attr_report_data = {
      { PRIVATE_HEART_BATTERY_ENERGY_ID, data_types.OctetString.ID, "\x01\x21\x44\x0C\x03\x28\x19\x04\x21\xA8\x13\x05\x21\x8E\x00\x06\x24\x04\x00\x00\x00\x00\x08\x21\x1E\x01\x0A\x21\x00\x00\x0C\x20\x01\x64\x10\x01\x66\x20\x03\x67\x20\x01\x68\x21\xA8\x00"}
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
    capabilities.batteryLevel.battery("normal")))
  end
)

test.register_coroutine_test(
  "heartbeat battery events - critical status",
  function()
    local attr_report_data = {
      { PRIVATE_HEART_BATTERY_ENERGY_ID, data_types.OctetString.ID, "\x01\x21\x00\x00\x03\x28\x19\x04\x21\xA8\x13\x05\x21\x8E\x00\x06\x24\x04\x00\x00\x00\x00\x08\x21\x1E\x01\x0A\x21\x00\x00\x0C\x20\x01\x64\x10\x01\x66\x20\x03\x67\x20\x01\x68\x21\xA8\x00"}
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
    capabilities.batteryLevel.battery("critical")))
  end
)

test.register_coroutine_test(
  "battery status events - normal status",
  function()
    local attr_report_data = {
      {PowerConfiguration.attributes.BatteryVoltage.ID, data_types.Uint8.ID, 0x1C }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PowerConfiguration.ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
    capabilities.batteryLevel.battery("normal")))
  end
)

test.register_coroutine_test(
  "battery status events - warning status",
  function()
    local attr_report_data = {
      {PowerConfiguration.attributes.BatteryVoltage.ID, data_types.Uint8.ID, 0x1A }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PowerConfiguration.ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
    capabilities.batteryLevel.battery("warning")))
  end
)

test.register_coroutine_test(
  "battery status events - critical status",
  function()
    local attr_report_data = {
      {PowerConfiguration.attributes.BatteryVoltage.ID, data_types.Uint8.ID, 0x9 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PowerConfiguration.ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
    capabilities.batteryLevel.battery("critical")))
  end
)

test.register_coroutine_test(
  "closed contact events - OnOff",
  function()
    local attr_report_data = {
      { OnOff.attributes.OnOff.ID, data_types.Boolean.ID, false }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, OnOff.ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.contactSensor.contact.closed()))
  end
)

test.register_coroutine_test(
  "open contact events - OnOff",
  function()
    local attr_report_data = {
      { OnOff.attributes.OnOff.ID, data_types.Boolean.ID, true }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, OnOff.ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.contactSensor.contact.open()))
  end
)

test.run_registered_tests()
