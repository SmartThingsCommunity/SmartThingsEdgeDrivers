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
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local Thermostat = clusters.Thermostat
local ThermostatUserInterfaceConfiguration = clusters.ThermostatUserInterfaceConfiguration
local capabilities = require "st.capabilities"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local base64 = require "st.base64"
local t_utils = require "integration_test.utils"

local mock_device = test.mock_device.build_test_zigbee_device(
    {
      profile = t_utils.get_profile_definition("thermostat-sinope-th1400.yml"),
      zigbee_endpoints = {
        [1] = {
          id = 1,
          manufacturer = "Sinope Technologies",
          model = "TH1400ZB",
          server_clusters = {0x0201, 0x0402}
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

test.register_message_test(
    "Temperature reports using the thermostat cluster should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, Thermostat.attributes.LocalTemperature:build_test_attr_report(mock_device, 2500) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.temperatureMeasurement.temperature({ value = 25.0, unit = "C" }))
      }
    }
)

test.register_message_test(
    "PIHeatingDemand reports using the thermostat cluster should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, Thermostat.attributes.PIHeatingDemand:build_test_attr_report(mock_device, 8) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.thermostatOperatingState.thermostatOperatingState("idle"))
      }
    }
)

test.register_coroutine_test(
    "Configure should configure all necessary attributes",
    function ()
      test.socket.zigbee:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle:__queue_receive({mock_device.id, "doConfigure"})
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         zigbee_test_utils.build_bind_request(
                                             mock_device,
                                             zigbee_test_utils.mock_hub_eui,
                                             Thermostat.ID
                                         )
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         Thermostat.attributes.LocalTemperature:configure_reporting(mock_device, 19, 300, 25)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         Thermostat.attributes.OccupiedHeatingSetpoint:configure_reporting(mock_device, 8, 302, 40)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         Thermostat.attributes.PIHeatingDemand:configure_reporting(mock_device, 11, 301, 10)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         Thermostat.attributes.SystemMode:configure_reporting(mock_device, 10, 305)
                                       })
      mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    end
)

test.register_coroutine_test(
    "Check all preferences via infoChanged",
    function()
      local updates = {
        preferences = {
          keypadLock = 1, --Lock
          backlightSetting = 0, --OnDemand
          timeFormat = 1, --12h
          airFloorMode = 2, --Floor
          floorSensorType = 1, --12k
          ambientLimit = 10,
          floorLowLimit = 20,
          floorHighLimit = 30,
          auxiliaryCycleLength = 1800 --30mins
        }
      }
      local SINOPE_CUSTOM_CLUSTER = 0xFF01
      local MFR_TIME_FORMAT_ATTRIBUTE = 0x0114
      local MFR_AIR_FLOOR_MODE_ATTRIBUTE = 0x0105
      local MFR_AMBIENT_LIMIT_ATTRIBUTE = 0x0108
      local MFR_FLOOR_LOW_LIMIT_ATTRIBUTE = 0x0109
      local MFR_FLOOR_SENSOR_TYPE_ATTRIBUTE = 0x010B
      local MFR_FLOOR_HIGH_LIMIT_ATTRIBUTE = 0x010A
      local MFR_BACKLIGHT_MODE_ATTRIBUTE = 0x0402
      local MFR_AUXILIARY_CYCLE_LENGTH_ATTRIBUTE = 0x0404
      test.socket.zigbee:__set_channel_ordering("relaxed")
      test.socket.environment_update:__queue_receive({ "zigbee", { hub_zigbee_id = base64.encode(zigbee_test_utils.mock_hub_eui) } })
      test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed(updates))
      test.socket.zigbee:__expect_send({
        mock_device.id,
        cluster_base.write_attribute(mock_device,
          data_types.ClusterId(ThermostatUserInterfaceConfiguration.ID),
          data_types.AttributeId(ThermostatUserInterfaceConfiguration.attributes.KeypadLockout.ID),
          data_types.validate_or_build_type(0x0001, data_types.Enum8, "payload")
        )
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        cluster_base.write_attribute(mock_device,
          data_types.ClusterId(Thermostat.ID),
          data_types.AttributeId(MFR_BACKLIGHT_MODE_ATTRIBUTE),
          data_types.validate_or_build_type(0x0000, data_types.Enum8, "payload")
        )
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        cluster_base.write_attribute(mock_device,
          data_types.ClusterId(SINOPE_CUSTOM_CLUSTER),
          data_types.AttributeId(MFR_TIME_FORMAT_ATTRIBUTE),
          data_types.validate_or_build_type(0x0001, data_types.Enum8, "payload")
        )
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        cluster_base.write_attribute(mock_device,
          data_types.ClusterId(SINOPE_CUSTOM_CLUSTER),
          data_types.AttributeId(MFR_AIR_FLOOR_MODE_ATTRIBUTE),
          data_types.validate_or_build_type(0x0002, data_types.Enum8, "payload")
        )
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        cluster_base.write_attribute(mock_device,
          data_types.ClusterId(SINOPE_CUSTOM_CLUSTER),
          data_types.AttributeId(MFR_FLOOR_SENSOR_TYPE_ATTRIBUTE),
          data_types.validate_or_build_type(0x0001, data_types.Enum8, "payload")
        )
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        cluster_base.write_attribute(mock_device,
          data_types.ClusterId(SINOPE_CUSTOM_CLUSTER),
          data_types.AttributeId(MFR_AMBIENT_LIMIT_ATTRIBUTE),
          data_types.validate_or_build_type(1000, data_types.Int16, "payload")
        )
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        cluster_base.write_attribute(mock_device,
          data_types.ClusterId(SINOPE_CUSTOM_CLUSTER),
          data_types.AttributeId(MFR_FLOOR_LOW_LIMIT_ATTRIBUTE),
          data_types.validate_or_build_type(2000, data_types.Int16, "payload")
        )
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        cluster_base.write_attribute(mock_device,
          data_types.ClusterId(SINOPE_CUSTOM_CLUSTER),
          data_types.AttributeId(MFR_FLOOR_HIGH_LIMIT_ATTRIBUTE),
          data_types.validate_or_build_type(3000, data_types.Int16, "payload")
        )
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        cluster_base.write_attribute(mock_device,
          data_types.ClusterId(Thermostat.ID),
          data_types.AttributeId(MFR_AUXILIARY_CYCLE_LENGTH_ATTRIBUTE),
          data_types.validate_or_build_type(0x0708, data_types.Uint16, "payload")
        )
      })
    end
)

test.run_registered_tests()
