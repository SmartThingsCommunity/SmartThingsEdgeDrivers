-- Copyright © 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local t_utils = require "integration_test.utils"
local test = require "integration_test"

local mock_device = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("humidity.yml"),
  manufacturer_info = { vendor_id = 0x0000, product_id = 0x0000 },
  endpoints = {
    {
      endpoint_id = 0,
      clusters = {
        { cluster_id = clusters.Basic.ID, cluster_type = "SERVER" },
      },
      device_types = {
        { device_type_id = 0x0016, device_type_revision = 1 } -- RootNode
      }
    },
    {
      endpoint_id = 1,
      clusters = {
        { cluster_id = clusters.SoilMeasurement.ID, cluster_type = "SERVER" },
        { cluster_id = clusters.TemperatureMeasurement.ID, cluster_type = "SERVER" },
      },
      device_types = {
        { device_type_id = 0x0045, device_type_revision = 1 } -- Soil Sensor
      }
    },
  }
})

local subscribe_request

local cluster_subscribe_list = {
  clusters.SoilMeasurement.attributes.SoilMoistureMeasuredValue,
}

local additional_subscribed_attributes = {
  clusters.TemperatureMeasurement.attributes.MeasuredValue,
  clusters.TemperatureMeasurement.attributes.MinMeasuredValue,
  clusters.TemperatureMeasurement.attributes.MaxMeasuredValue
}

local function test_init()
  subscribe_request = cluster_subscribe_list[1]:subscribe(mock_device)
  for i, cluster in ipairs(cluster_subscribe_list) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(mock_device))
    end
  end

  test.disable_startup_messages()
  test.mock_device.add_test_device(mock_device)
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "init" })
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})
end
test.set_test_init_function(test_init)

local function update_device_profile()
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
  mock_device:expect_metadata_update({ profile = "temperature-humidity" })
  mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })

  test.wait_for_events()

  local updated_device_profile = t_utils.get_profile_definition("temperature-humidity.yml")
  test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({ profile = updated_device_profile }))
  for _, attr in ipairs(additional_subscribed_attributes) do
    subscribe_request:merge(attr:subscribe(mock_device))
  end
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})
end

test.register_coroutine_test(
  "Relative humidity reports should generate correct messages",
  function()
    update_device_profile()
    test.wait_for_events()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        clusters.RelativeHumidityMeasurement.server.attributes.MeasuredValue:build_test_report_data(mock_device, 1, 4049)
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.relativeHumidityMeasurement.humidity({ value = 40 }))
    )

    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        clusters.RelativeHumidityMeasurement.server.attributes.MeasuredValue:build_test_report_data(mock_device, 1, 4050)
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.relativeHumidityMeasurement.humidity({ value = 41 }))
    )
  end
)

test.register_coroutine_test(
  "Temperature reports should generate correct messages",
  function()
    update_device_profile()
    test.wait_for_events()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        clusters.TemperatureMeasurement.server.attributes.MeasuredValue:build_test_report_data(mock_device, 1, 40*100)
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.temperatureMeasurement.temperature({ value = 40.0, unit = "C" }))
    )
  end
)

test.register_coroutine_test(
  "Min and max temperature attributes set capability constraint",
  function()
    update_device_profile()
    test.wait_for_events()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        clusters.TemperatureMeasurement.attributes.MinMeasuredValue:build_test_report_data(mock_device, 1, 500)
      }
    )
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        clusters.TemperatureMeasurement.attributes.MaxMeasuredValue:build_test_report_data(mock_device, 1, 4000)
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.temperatureMeasurement.temperatureRange({ value = { minimum = 5.00, maximum = 40.00 }, unit = "C" })
      )
    )
  end
)

test.run_registered_tests()
