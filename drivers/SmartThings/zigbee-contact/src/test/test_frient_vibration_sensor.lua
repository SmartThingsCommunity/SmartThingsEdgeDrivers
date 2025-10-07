
-- Copyright 2025 SmartThings
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
local IasEnrollResponseCode = require "st.zigbee.generated.zcl_clusters.IASZone.types.EnrollResponseCode"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"

local IASZone = clusters.IASZone
local PowerConfiguration = clusters.PowerConfiguration
local TemperatureMeasurement = clusters.TemperatureMeasurement
local POWER_CONFIGURATION_AND_ACCELERATION_ENDPOINT = 0x2D
local TEMPERATURE_ENDPOINT = 0x26

local base64 = require "base64"
local mock_device = test.mock_device.build_test_zigbee_device(
        { profile = t_utils.get_profile_definition("acceleration-motion-temperature-battery.yml"),
          zigbee_endpoints = {
              [0x01] = {
                  id = 0x01,
                  manufacturer = "frient A/S",
                  model = "WISZB-137",
                  server_clusters = { 0x0003, 0x0005, 0x0006 }
              },
              [0x2D] = {
                  id = 0x2D,
                  server_clusters = { 0x0000, 0x0001, 0x0003, 0x0020, 0x0500, 0xFC04 }
              },
              [0x26] = {
                  id = 0x26,
                  server_clusters = { 0x0402 }
              }
          }
        }
)

local mock_device_contact = test.mock_device.build_test_zigbee_device(
        { profile = t_utils.get_profile_definition("acceleration-motion-temperature-contact-battery.yml"),
          zigbee_endpoints = {
              [0x01] = {
                  id = 0x01,
                  manufacturer = "frient A/S",
                  model = "WISZB-137",
                  server_clusters = { 0x0003, 0x0005, 0x0006 }
              },
              [0x2D] = {
                  id = 0x2D,
                  server_clusters = { 0x0000, 0x0001, 0x0003, 0x0020, 0x0500, 0xFC04 }
              },
              [0x26] = {
                  id = 0x26,
                  server_clusters = { 0x0402 }
              }
          }
        }
)

local Frient_AccelerationMeasurementCluster = {
  ID = 0xFC04,
  ManufacturerSpecificCode = 0x1015,
  attributes = {
    MeasuredValueX = { ID = 0x0000, data_type = data_types.name_to_id_map["Int16"] },
    MeasuredValueY = { ID = 0x0001, data_type = data_types.name_to_id_map["Int16"] },
    MeasuredValueZ = { ID = 0x0002, data_type = data_types.name_to_id_map["Int16"] }
  },
}

zigbee_test_utils.prepare_zigbee_env_info()

local function test_init()
    test.mock_device.add_test_device(mock_device)
    test.mock_device.add_test_device(mock_device_contact)
end

test.set_test_init_function(test_init)

local function custom_configure_reporting(device, cluster, attribute, data_type, min_interval, max_interval, reportable_change, mfg_code)
    local message = cluster_base.configure_reporting(device,
        data_types.ClusterId(cluster),
        data_types.AttributeId(attribute),
        data_type,
        min_interval,
        max_interval,
        reportable_change)

    -- Set the manufacturer-specific bit and add the manufacturer code
    message.body.zcl_header.frame_ctrl:set_mfg_specific()
    message.body.zcl_header.mfg_code = data_types.validate_or_build_type(mfg_code, data_types.Uint16, "mfg_code")

    return message
end

test.register_coroutine_test(
        "init and doConfigure lifecycles should be handled properly",
        function()
            test.socket.environment_update:__queue_receive({ "zigbee", { hub_zigbee_id = base64.encode(zigbee_test_utils.mock_hub_eui) } })
            test.socket.zigbee:__set_channel_ordering("relaxed")

            test.socket.device_lifecycle:__queue_receive({ mock_device.id, "init" })

            test.wait_for_events()

            --test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
            test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })

            test.socket.zigbee:__expect_send({
                mock_device.id,
                zigbee_test_utils.build_bind_request(
                    mock_device,
                    zigbee_test_utils.mock_hub_eui,
                    PowerConfiguration.ID,
                    POWER_CONFIGURATION_AND_ACCELERATION_ENDPOINT
                ):to_endpoint(POWER_CONFIGURATION_AND_ACCELERATION_ENDPOINT)
            })

            test.socket.zigbee:__expect_send({
                 mock_device.id,
                 PowerConfiguration.attributes.BatteryVoltage:configure_reporting(
                         mock_device,
                         30,
                         21600,
                         1
                 ):to_endpoint(POWER_CONFIGURATION_AND_ACCELERATION_ENDPOINT)
             })

             test.socket.zigbee:__expect_send({
                mock_device.id,
                zigbee_test_utils.build_bind_request(
                    mock_device,
                    zigbee_test_utils.mock_hub_eui,
                    IASZone.ID,
                    POWER_CONFIGURATION_AND_ACCELERATION_ENDPOINT
                ):to_endpoint(POWER_CONFIGURATION_AND_ACCELERATION_ENDPOINT)
            })

            test.socket.zigbee:__expect_send({
                mock_device.id,
                zigbee_test_utils.build_bind_request(
                    mock_device,
                    zigbee_test_utils.mock_hub_eui,
                    TemperatureMeasurement.ID,
                    TEMPERATURE_ENDPOINT
                ):to_endpoint(TEMPERATURE_ENDPOINT)
            })

            test.socket.zigbee:__expect_send({
                mock_device.id,
                IASZone.attributes.ZoneStatus:configure_reporting(
                        mock_device,
                        0x001E,
                        0x012C,
                        1
                ):to_endpoint(POWER_CONFIGURATION_AND_ACCELERATION_ENDPOINT)
            })

            test.socket.zigbee:__expect_send({
                mock_device.id,
                TemperatureMeasurement.attributes.MeasuredValue:configure_reporting(
                        mock_device,
                        30,
                        600,
                        100
                ):to_endpoint(TEMPERATURE_ENDPOINT)
            })

            test.socket.zigbee:__expect_send({
                mock_device.id,
                IASZone.attributes.IASCIEAddress:write(
                        mock_device,
                        zigbee_test_utils.mock_hub_eui
                ):to_endpoint(POWER_CONFIGURATION_AND_ACCELERATION_ENDPOINT)
            })

            test.socket.zigbee:__expect_send({
                mock_device.id,
                zigbee_test_utils.build_bind_request(
                    mock_device,
                    zigbee_test_utils.mock_hub_eui,
                    Frient_AccelerationMeasurementCluster.ID,
                    POWER_CONFIGURATION_AND_ACCELERATION_ENDPOINT
                ):to_endpoint(POWER_CONFIGURATION_AND_ACCELERATION_ENDPOINT)
            })

            test.socket.zigbee:__expect_send({
                mock_device.id,
                custom_configure_reporting(
                    mock_device,
                    Frient_AccelerationMeasurementCluster.ID,
                    Frient_AccelerationMeasurementCluster.attributes.MeasuredValueY.ID,
                    Frient_AccelerationMeasurementCluster.attributes.MeasuredValueY.data_type,
                    0x0000,
                    0x012C,
                    0x0001,
                    Frient_AccelerationMeasurementCluster.ManufacturerSpecificCode
                ):to_endpoint(POWER_CONFIGURATION_AND_ACCELERATION_ENDPOINT)
            })

            test.socket.zigbee:__expect_send({
                mock_device.id,
                custom_configure_reporting(
                    mock_device,
                    Frient_AccelerationMeasurementCluster.ID,
                    Frient_AccelerationMeasurementCluster.attributes.MeasuredValueX.ID,
                    Frient_AccelerationMeasurementCluster.attributes.MeasuredValueX.data_type,
                    0x0000,
                    0x012C,
                    0x0001,
                    Frient_AccelerationMeasurementCluster.ManufacturerSpecificCode
                ):to_endpoint(POWER_CONFIGURATION_AND_ACCELERATION_ENDPOINT)
            })

            test.socket.zigbee:__expect_send({
                mock_device.id,
                custom_configure_reporting(
                    mock_device,
                    Frient_AccelerationMeasurementCluster.ID,
                    Frient_AccelerationMeasurementCluster.attributes.MeasuredValueZ.ID,
                    Frient_AccelerationMeasurementCluster.attributes.MeasuredValueZ.data_type,
                    0x0000,
                    0x012C,
                    0x0001,
                    Frient_AccelerationMeasurementCluster.ManufacturerSpecificCode
                ):to_endpoint(POWER_CONFIGURATION_AND_ACCELERATION_ENDPOINT)
            })

            test.socket.zigbee:__expect_send({
                mock_device.id,
                IASZone.server.commands.ZoneEnrollResponse(
                    mock_device,
                    IasEnrollResponseCode.SUCCESS,
                    0x00
                )
            })

            test.socket.zigbee:__expect_send({
                mock_device.id,
                zigbee_test_utils.build_bind_request(
                    mock_device,
                    zigbee_test_utils.mock_hub_eui,
                    IASZone.ID,
                    POWER_CONFIGURATION_AND_ACCELERATION_ENDPOINT
                )
            })


            test.socket.zigbee:__expect_send({
                mock_device.id,
                IASZone.attributes.CurrentZoneSensitivityLevel:write(
                        mock_device,
                        0x000A
                ):to_endpoint(POWER_CONFIGURATION_AND_ACCELERATION_ENDPOINT)
            })

            test.socket.zigbee:__expect_send({
                mock_device.id,
                TemperatureMeasurement.attributes.MeasuredValue:configure_reporting(
                        mock_device,
                        0x001E,
                        0x0E10,
                        100
                ):to_endpoint(TEMPERATURE_ENDPOINT)
            })

            test.socket.zigbee:__expect_send({
              mock_device.id,
              IASZone.attributes.ZoneStatus:configure_reporting(
                      mock_device,
                      0,
                      3600,
                      0
              )
            })

            test.socket.zigbee:__expect_send({
              mock_device.id,
              zigbee_test_utils.build_bind_request(
                  mock_device,
                  zigbee_test_utils.mock_hub_eui,
                  Frient_AccelerationMeasurementCluster.ID,
                  POWER_CONFIGURATION_AND_ACCELERATION_ENDPOINT
              )
            })

            mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
        end
)

test.register_message_test(
  "Temperature report should be handled (C) for the temperature measurement cluster",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, TemperatureMeasurement.attributes.MeasuredValue:build_test_attr_report(mock_device, 2300)}
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.temperatureMeasurement.temperature({ value = 23.0, unit = "C"}))
    },
    {
      channel = "devices",
      direction = "send",
      message = { "register_native_capability_attr_handler",
        {
          device_uuid = mock_device.id, capability_id = "temperatureMeasurement", capability_attr_id = "temperature"
        }
      }
    }
  }
)

test.register_message_test(
  "Battery min voltage report should be handled",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = {mock_device.id, PowerConfiguration.attributes.BatteryVoltage:build_test_attr_report(mock_device, 23)}
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.battery.battery(0))
    }
  }
)

test.register_message_test(
  "Battery max voltage report should be handled",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = {mock_device.id, PowerConfiguration.attributes.BatteryVoltage:build_test_attr_report(mock_device, 30)}
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.battery.battery(100))
    }
  }
)

test.register_coroutine_test(
"Refresh necessary attributes",
function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.capability:__queue_receive({ mock_device.id, { capability = "refresh", component = "main", command = "refresh", args = {} } })
    test.socket.zigbee:__expect_send({ mock_device.id, IASZone.attributes.ZoneStatus:read(mock_device):to_endpoint(POWER_CONFIGURATION_AND_ACCELERATION_ENDPOINT) })
    test.socket.zigbee:__expect_send({ mock_device.id, PowerConfiguration.attributes.BatteryVoltage:read(mock_device):to_endpoint(POWER_CONFIGURATION_AND_ACCELERATION_ENDPOINT) })
    test.socket.zigbee:__expect_send({ mock_device.id, TemperatureMeasurement.attributes.MeasuredValue:read(mock_device):to_endpoint(TEMPERATURE_ENDPOINT) })
    test.socket.zigbee:__expect_send({
        mock_device.id,
        cluster_base.read_manufacturer_specific_attribute(
                mock_device,
                Frient_AccelerationMeasurementCluster.ID,
                Frient_AccelerationMeasurementCluster.attributes.MeasuredValueX.ID,
                Frient_AccelerationMeasurementCluster.ManufacturerSpecificCode
        ):to_endpoint(POWER_CONFIGURATION_AND_ACCELERATION_ENDPOINT)
    })
    test.socket.zigbee:__expect_send({
        mock_device.id,
        cluster_base.read_manufacturer_specific_attribute(
                mock_device,
                Frient_AccelerationMeasurementCluster.ID,
                Frient_AccelerationMeasurementCluster.attributes.MeasuredValueY.ID,
                Frient_AccelerationMeasurementCluster.ManufacturerSpecificCode
        ):to_endpoint(POWER_CONFIGURATION_AND_ACCELERATION_ENDPOINT)
    })
    test.socket.zigbee:__expect_send({
        mock_device.id,
        cluster_base.read_manufacturer_specific_attribute(
                mock_device,
                Frient_AccelerationMeasurementCluster.ID,
                Frient_AccelerationMeasurementCluster.attributes.MeasuredValueZ.ID,
                Frient_AccelerationMeasurementCluster.ManufacturerSpecificCode
        ):to_endpoint(POWER_CONFIGURATION_AND_ACCELERATION_ENDPOINT)
    })
end
)

test.register_message_test(
  "Reported ZoneStatus change should be handled: active motion and inactive acceleration",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = {mock_device.id, IASZone.attributes.ZoneStatus:build_test_attr_report(mock_device, 0x0001)}
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.motionSensor.motion.active(mock_device))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.accelerationSensor.acceleration.inactive(mock_device))
    }
  }
)

test.register_message_test(
  "Reported ZoneStatus change should be handled: inactive motion and active acceleration",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = {mock_device.id, IASZone.attributes.ZoneStatus:build_test_attr_report(mock_device, 0x0002)}
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.motionSensor.motion.inactive(mock_device))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.accelerationSensor.acceleration.active(mock_device))
    }
  }
)

test.register_coroutine_test(
  "Three Axis report should be correctly handled",
  function()
    local attr_report_data = {
      { 0x0000, data_types.Int16.ID, 300},
      { 0x0001, data_types.Int16.ID, 200},
      { 0x0002, data_types.Int16.ID, 100},
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, Frient_AccelerationMeasurementCluster.ID, attr_report_data, 0x1015)
    })

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.threeAxis.threeAxis({300, 200, 100}))
    )

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.threeAxis.threeAxis({300, 200, 100}))
    )

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.threeAxis.threeAxis({300, 200, 100}))
    )
  end
)

test.register_coroutine_test(
  "Contact sensor open events should be correctly handled when preference is set",
  function()
    local updates = {
        preferences = {
            garageSensor = "Yes"
        }
    }
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive(mock_device_contact:generate_info_changed(updates))
    local attr_report_data = {
      { 0x0000, data_types.Int16.ID, 300},
      { 0x0001, data_types.Int16.ID, 200},
      { 0x0002, data_types.Int16.ID, -902},
    }
    test.socket.zigbee:__queue_receive({
      mock_device_contact.id,
      zigbee_test_utils.build_attribute_report(mock_device_contact, Frient_AccelerationMeasurementCluster.ID, attr_report_data, 0x1015)
    })

    test.socket.capability:__expect_send(
      mock_device_contact:generate_test_message("main", capabilities.threeAxis.threeAxis({300, 200, -902}))
    )

    test.socket.capability:__expect_send(
      mock_device_contact:generate_test_message("main", capabilities.threeAxis.threeAxis({300, 200, -902}))
    )

    test.socket.capability:__expect_send(
      mock_device_contact:generate_test_message("main", capabilities.threeAxis.threeAxis({300, 200, -902}))
    )

    test.socket.capability:__expect_send(
      mock_device_contact:generate_test_message("main", capabilities.contactSensor.contact.open())
    )
  end
)

test.register_coroutine_test(
  "Contact sensor close events should be correctly handled when preference is set",
  function()
    local updates = {
        preferences = {
            garageSensor = "Yes"
        }
    }
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed(updates))
    local attr_report_data = {
      { 0x0000, data_types.Int16.ID, 300},
      { 0x0001, data_types.Int16.ID, 200},
      { 0x0002, data_types.Int16.ID, 100},
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, Frient_AccelerationMeasurementCluster.ID, attr_report_data, 0x1015)
    })

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.threeAxis.threeAxis({300, 200, 100}))
    )

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.threeAxis.threeAxis({300, 200, 100}))
    )

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.threeAxis.threeAxis({300, 200, 100}))
    )

    --if (mock_device.preferences.garageSensor == "Yes") then
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.contactSensor.contact.closed())
      )
    --end
  end
)

test.run_registered_tests()