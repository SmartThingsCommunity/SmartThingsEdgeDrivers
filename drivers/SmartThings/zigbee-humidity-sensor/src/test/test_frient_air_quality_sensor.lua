-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local t_utils = require "integration_test.utils"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local data_types = require "st.zigbee.data_types"
local cluster_base = require "st.zigbee.cluster_base"

local PowerConfiguration = clusters.PowerConfiguration
local TemperatureMeasurement = clusters.TemperatureMeasurement
local HumidityMeasurement = clusters.RelativeHumidity

local Frient_VOCMeasurement = {
  ID = 0xFC03,
  ManufacturerSpecificCode = 0x1015,
  attributes = {
    MeasuredValue = { ID = 0x0000, base_type = data_types.Uint16 },
    MinMeasuredValue = { ID = 0x0001, base_type = data_types.Uint16 },
    MaxMeasuredValue = { ID = 0x0002, base_type = data_types.Uint16 },
    Resolution = { ID = 0x0003, base_type = data_types.Uint16 },
  },
}

Frient_VOCMeasurement.attributes.MeasuredValue._cluster = Frient_VOCMeasurement
Frient_VOCMeasurement.attributes.MinMeasuredValue._cluster = Frient_VOCMeasurement
Frient_VOCMeasurement.attributes.MaxMeasuredValue._cluster = Frient_VOCMeasurement
Frient_VOCMeasurement.attributes.Resolution._cluster = Frient_VOCMeasurement

local mock_device = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("frient-airquality-humidity-temperature-battery.yml"),
    zigbee_endpoints = {
      [0x26] = {
        id = 0x26,
        manufacturer = "frient A/S",
        model = "AQSZB-110",
        server_clusters = {0x0001, 0x0402, 0x0405, 0xFC03}
      }
    }
  }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device)
end

test.set_test_init_function(test_init)

test.register_message_test(
  "Refresh should read all necessary attributes",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {mock_device.id, { capability = "refresh", component = "main", command = "refresh", args = {} } }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = {
        mock_device.id,
        PowerConfiguration.attributes.BatteryVoltage:read(mock_device)
      }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = {
        mock_device.id,
        HumidityMeasurement.attributes.MeasuredValue:read(mock_device)
      }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = {
        mock_device.id,
        TemperatureMeasurement.attributes.MeasuredValue:read(mock_device)
      }
    },
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.register_message_test(
        "Min battery voltage report should be handled",
        {
            {
                channel = "zigbee",
                direction = "receive",
                message = { mock_device.id, PowerConfiguration.attributes.BatteryVoltage:build_test_attr_report(mock_device, 23) }
            },
            {
                channel = "capability",
                direction = "send",
                message = mock_device:generate_test_message("main", capabilities.battery.battery(0))
            }
        }
)

test.register_message_test(
        "Max battery voltage report should be handled",
        {
            {
                channel = "zigbee",
                direction = "receive",
                message = { mock_device.id, PowerConfiguration.attributes.BatteryVoltage:build_test_attr_report(mock_device, 30) }
            },
            {
                channel = "capability",
                direction = "send",
                message = mock_device:generate_test_message("main", capabilities.battery.battery(100))
            }
        }
)

test.register_coroutine_test(
  "Configure should configure all necessary attributes",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(5, "oneshot")
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
    test.socket.zigbee:__set_channel_ordering("relaxed")

    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(
              mock_device,
              zigbee_test_utils.mock_hub_eui,
              PowerConfiguration.ID
      )
    })

    test.socket.zigbee:__expect_send({
      mock_device.id,
      PowerConfiguration.attributes.BatteryVoltage:configure_reporting(mock_device, 30, 21600, 1)
    })

    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(
              mock_device,
              zigbee_test_utils.mock_hub_eui,
              TemperatureMeasurement.ID
      )
    })

    test.socket.zigbee:__expect_send({
      mock_device.id,
      TemperatureMeasurement.attributes.MeasuredValue:configure_reporting(mock_device, 0x001E, 0x0E10, 100)
    })

    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(
              mock_device,
              zigbee_test_utils.mock_hub_eui,
              HumidityMeasurement.ID
      )
    })

    test.socket.zigbee:__expect_send({
      mock_device.id,
      HumidityMeasurement.attributes.MeasuredValue:configure_reporting(mock_device, 60, 3600, 300)
    })

    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(
          mock_device,
          zigbee_test_utils.mock_hub_eui,
          Frient_VOCMeasurement.ID,
              38
      ):to_endpoint(0x26)
    })

    test.socket.zigbee:__expect_send({
      mock_device.id,
      cluster_base.configure_reporting(
          mock_device,
          data_types.ClusterId(Frient_VOCMeasurement.ID),
          Frient_VOCMeasurement.attributes.MeasuredValue.ID,
          Frient_VOCMeasurement.attributes.MeasuredValue.base_type.ID,
          60, 600, 10
      ):to_endpoint(0x26)
    })


    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    test.wait_for_events()

    --refresh happens after configure
    test.mock_time.advance_time(5)
    test.socket.zigbee:__expect_send({
      mock_device.id,
      cluster_base.read_manufacturer_specific_attribute(mock_device, Frient_VOCMeasurement.ID, Frient_VOCMeasurement.attributes.MeasuredValue.ID, Frient_VOCMeasurement.ManufacturerSpecificCode):to_endpoint(0x26)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      TemperatureMeasurement.attributes.MeasuredValue:read(mock_device):to_endpoint(0x26)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      HumidityMeasurement.attributes.MeasuredValue:read(mock_device):to_endpoint(0x26)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      PowerConfiguration.attributes.BatteryVoltage:read(mock_device)
    })
  end
)

test.register_message_test(
  "Humidity report should be handled",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = {
        mock_device.id,
        HumidityMeasurement.attributes.MeasuredValue:build_test_attr_report(mock_device, 0x1950)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.relativeHumidityMeasurement.humidity({ value = 65 }))
    }
  }
)

test.register_message_test(
  "Temperature report should be handled (C) for the temperature cluster",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, TemperatureMeasurement.attributes.MeasuredValue:build_test_attr_report(mock_device, 2500) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.temperatureMeasurement.temperature({ value = 25.0, unit = "C" }))
    }
  }
)

test.register_coroutine_test(
    "info_changed to check for necessary preferences settings: Temperature Sensitivity",
    function()
        local updates = {
            preferences = {
                temperatureSensitivity = 0.9,
                humiditySensitivity = 10
            }
        }
        test.socket.zigbee:__set_channel_ordering("relaxed")
        test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed(updates))
        local temperatureSensitivity = math.floor(0.9 * 100 + 0.5)
        test.socket.zigbee:__expect_send({ mock_device.id,
                                           TemperatureMeasurement.attributes.MeasuredValue:configure_reporting(
                                                   mock_device,
                                                   30,
                                                   3600,
                                                   temperatureSensitivity
                                           )
        })
        local humiditySensitivity = math.floor(10 * 100 + 0.5)
        test.socket.zigbee:__expect_send({ mock_device.id,
                                           HumidityMeasurement.attributes.MeasuredValue:configure_reporting(
                                                   mock_device,
                                                   60,
                                                   3600,
                                                   humiditySensitivity
                                           )
        })
        test.wait_for_events()
    end
)

test.register_message_test(
  "VOC measurement report should be handled",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, cluster_base.build_test_attr_report(Frient_VOCMeasurement.attributes.MeasuredValue, mock_device, 300) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.airQualitySensor.airQuality({ value = 5 }))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.tvocHealthConcern.tvocHealthConcern({ value = "slightlyUnhealthy" }))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.tvocMeasurement.tvocLevel({ value = 300, unit = "ppb" }))
    }
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.register_coroutine_test(
  "Added handler should initialize VOC and air quality state",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.airQualitySensor.airQuality({ value = 0 })))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.tvocHealthConcern.tvocHealthConcern({ value = "good" })))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.tvocMeasurement.tvocLevel({ value = 0, unit = "ppb" })))
    test.wait_for_events()
  end
)

test.run_registered_tests()
