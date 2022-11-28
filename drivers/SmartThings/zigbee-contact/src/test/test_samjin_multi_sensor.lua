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
local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"

local write_attribute = require "st.zigbee.zcl.global_commands.write_attribute"
local data_types = require "st.zigbee.data_types"
local zcl_messages = require "st.zigbee.zcl"
local messages = require "st.zigbee.messages"
local zb_const = require "st.zigbee.constants"

local IASZone = clusters.IASZone
local PowerConfiguration = clusters.PowerConfiguration
local TemperatureMeasurement = clusters.TemperatureMeasurement

local IASCIEAddress = IASZone.attributes.IASCIEAddress
local EnrollResponseCode = IASZone.types.EnrollResponseCode

local mock_device = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("multi-sensor.yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "Samjin",
        model = "multi",
        server_clusters = { 0x0001, 0x0402, 0x0500, 0xFC02 }
      }
    }
  }
)

zigbee_test_utils.prepare_zigbee_env_info()

local function test_init()
  test.mock_device.add_test_device(mock_device)
end

test.set_test_init_function(test_init)

local function build_write_attr_msg(cluster, attr, data_type, value, mfg_code)
  local data = data_types.validate_or_build_type(value, data_type)
  local write_body = write_attribute.WriteAttribute({
    write_attribute.WriteAttribute.AttributeRecord(attr, data_type.ID, data)
  })
  local zclh = zcl_messages.ZclHeader({
    cmd = data_types.ZCLCommandId(write_attribute.WriteAttribute.ID)
  })
  if mfg_code ~= nil then
    zclh.frame_ctrl:set_mfg_specific()
    zclh.mfg_code = data_types.validate_or_build_type(mfg_code, data_types.Uint16, "mfg_code")
  end
  local addrh = messages.AddressHeader(
      zb_const.HUB.ADDR,
      zb_const.HUB.ENDPOINT,
      mock_device:get_short_address(),
      mock_device:get_endpoint(cluster),
      zb_const.HA_PROFILE_ID,
      cluster
  )
  local message_body = zcl_messages.ZclMessageBody({
    zcl_header = zclh,
    zcl_body = write_body
  })
  return messages.ZigbeeMessageTx({
    address_header = addrh,
    body = message_body
  })
end

test.register_coroutine_test(
  "Refresh necessary attributes",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.capability:__queue_receive({ mock_device.id, { capability = "refresh", component = "main", command = "refresh", args = {} } })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      IASZone.attributes.ZoneStatus:read(mock_device)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      TemperatureMeasurement.attributes.MeasuredValue:read(mock_device)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_attribute_read(mock_device, 0xFC02, {0x0010}, 0x1241)
    })
  end
)

test.register_coroutine_test(
  "Added should send all necessary events and messages",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
    -- test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.accelerationSensor.acceleration.inactive()))
    test.socket.zigbee:__expect_send({
      mock_device.id,
      PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      IASZone.attributes.ZoneStatus:read(mock_device)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      TemperatureMeasurement.attributes.MeasuredValue:read(mock_device)
    })
  end
)

test.register_coroutine_test(
  "Configure should configure all necessary attributes",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, PowerConfiguration.ID)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      PowerConfiguration.attributes.BatteryPercentageRemaining:configure_reporting(mock_device, 30, 21600, 1)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, TemperatureMeasurement.ID)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      TemperatureMeasurement.attributes.MeasuredValue:configure_reporting(mock_device, 30, 300, 16)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, IASZone.ID)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      IASZone.attributes.ZoneStatus:configure_reporting(mock_device, 30, 300, 1)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      IASCIEAddress:write(mock_device, zigbee_test_utils.mock_hub_eui)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      IASZone.server.commands.ZoneEnrollResponse(mock_device, EnrollResponseCode.SUCCESS, 0x00)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      build_write_attr_msg(0xFC02, 0x0000, data_types.Uint8, 0x14, 0x1241)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, 0xFC02)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_attr_config(mock_device, 0xFC02, 0x0010, 0, 3600, data_types.Bitmap8, 1, 0x1241)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_attr_config(mock_device, 0xFC02, 0x0012, 0, 3600, data_types.Int16, 1, 0x1241)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_attr_config(mock_device, 0xFC02, 0x0013, 0, 3600, data_types.Int16, 1, 0x1241)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_attr_config(mock_device, 0xFC02, 0x0014, 0, 3600, data_types.Int16, 1, 0x1241)
    })

    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)

test.register_coroutine_test(
  "Battery Percentage Remaining test cases when polling from hub",
  function()
    local battery_test_map = {
      ["Samjin"] = {
        [200] = 100,
        [150] = 75,
        [120] = 60,
        [97] = 49,
        [51] = 26,
        [1] = 1,
        [0] = 0
      }
    }
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added"})
    -- test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.accelerationSensor.acceleration.inactive()))
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.zigbee:__expect_send({
      mock_device.id,
      PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      IASZone.attributes.ZoneStatus:read(mock_device)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      TemperatureMeasurement.attributes.MeasuredValue:read(mock_device)
    })
    test.wait_for_events()
    test.socket.zigbee:__set_channel_ordering("strict")
    for voltage, batt_perc in pairs(battery_test_map[mock_device:get_manufacturer()]) do
      test.socket.zigbee:__queue_receive({ mock_device.id, PowerConfiguration.attributes.BatteryPercentageRemaining:build_test_attr_report(mock_device, voltage) })
      test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.battery.battery(batt_perc)) )
      test.wait_for_events()
    end
  end
)

test.run_registered_tests()
