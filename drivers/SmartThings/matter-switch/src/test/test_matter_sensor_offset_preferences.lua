-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"
local clusters = require "st.matter.clusters"

local mock_device = test.mock_device.build_test_matter_device({
    profile = t_utils.get_profile_definition("3-button-battery-temperature-humidity.yml"),
    matter_version = {hardware = 1, software = 1},
    manufacturer_info = {
        vendor_id = 0x0000,
        product_id = 0x0000,
    },
    endpoints = {
        {
            endpoint_id = 1,
            clusters = {
                {cluster_id = clusters.TemperatureMeasurement.ID, cluster_type = "SERVER"},
            },
            device_types = {
                {device_type_id = 0x0302, device_type_revision = 1},
            }
        },
        {
            endpoint_id = 2,
            clusters = {
                {cluster_id = clusters.RelativeHumidityMeasurement.ID, cluster_type = "BOTH"},
            },
            device_types = {
                {device_type_id = 0x0307, device_type_revision = 1},
            }
        },
    }
})

local function test_init()
    test.disable_startup_messages()
    test.mock_device.add_test_device(mock_device)
end

test.register_coroutine_test("Read appropriate attribute values after tempOffset preference change", function()
    local report = clusters.TemperatureMeasurement.attributes.MeasuredValue:build_test_report_data(mock_device,1, 2000)
    test.socket.device_lifecycle():__queue_receive(mock_device:generate_info_changed({ preferences = { tempOffset = "2" } }))

    test.socket.matter:__queue_receive({mock_device.id, report})
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",capabilities.temperatureMeasurement.temperature({
        value = 20.0,
        unit = "C"
    })))
    test.socket.device_lifecycle():__queue_receive(mock_device:generate_info_changed({preferences = {tempOffset = "5"}}))
    test.socket.matter:__expect_send({mock_device.id, clusters.TemperatureMeasurement.attributes.MeasuredValue:read(mock_device)})

    test.wait_for_events()

    test.socket.matter:__queue_receive({mock_device.id, report})
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",capabilities.temperatureMeasurement.temperature({
        value = 20.0,
        unit = "C"
    })))
end,
{
   min_api_version = 17
}
)

test.register_coroutine_test("Read appropriate attribute values after humidityOffset preference change", function()
    local report = clusters.RelativeHumidityMeasurement.attributes.MeasuredValue:build_test_report_data(mock_device,2, 2000)
    test.socket.device_lifecycle():__queue_receive(mock_device:generate_info_changed({ preferences = { humidityOffset = "0" } }))

    test.socket.matter:__queue_receive({mock_device.id, report})
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",capabilities.relativeHumidityMeasurement.humidity({
        value = 20
    })))
    test.socket.device_lifecycle():__queue_receive(mock_device:generate_info_changed({preferences = {humidityOffset = "5"}}))
    test.socket.matter:__expect_send({mock_device.id, clusters.RelativeHumidityMeasurement.attributes.MeasuredValue:read(mock_device)})

    test.wait_for_events()

    test.socket.matter:__queue_receive({mock_device.id, report})
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",capabilities.relativeHumidityMeasurement.humidity({
        value = 20
    })))
end,
{
   min_api_version = 17
}
)

test.set_test_init_function(test_init)

test.run_registered_tests()
