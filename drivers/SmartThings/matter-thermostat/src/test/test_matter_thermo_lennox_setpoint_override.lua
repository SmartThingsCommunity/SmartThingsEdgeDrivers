-- Copyright © 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"
local clusters = require "st.matter.clusters"

local mock_lennox_device = test.mock_device.build_test_matter_device({
    profile = t_utils.get_profile_definition("thermostat-humidity-fan.yml"),
    manufacturer_info = {
        vendor_id = 0x1356,
        product_id = 0x0001,
    },
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
                {
                    cluster_id = clusters.Thermostat.ID,
                    cluster_revision = 5,
                    cluster_type = "SERVER",
                    feature_map = 35, -- Heat, Cool, and Auto features.
                },
                { cluster_id = clusters.PowerSource.ID,            cluster_type = "SERVER", feature_map = clusters.PowerSource.types.PowerSourceFeature.BATTERY },
                { cluster_id = clusters.TemperatureMeasurement.ID, cluster_type = "BOTH" },
            },
            device_types = {
                { device_type_id = 0x0301, device_type_revision = 1 } -- Thermostat
            }
        }
    }
})

local function test_init()
    local cluster_subscribe_list = {
        clusters.Thermostat.attributes.LocalTemperature,
        clusters.Thermostat.attributes.OccupiedCoolingSetpoint,
        clusters.Thermostat.attributes.OccupiedHeatingSetpoint,
        clusters.Thermostat.attributes.AbsMinCoolSetpointLimit,
        clusters.Thermostat.attributes.AbsMaxCoolSetpointLimit,
        clusters.Thermostat.attributes.AbsMinHeatSetpointLimit,
        clusters.Thermostat.attributes.AbsMaxHeatSetpointLimit,
        clusters.Thermostat.attributes.SystemMode,
        clusters.Thermostat.attributes.ThermostatRunningState,
        clusters.Thermostat.attributes.ControlSequenceOfOperation,
        clusters.PowerSource.attributes.BatPercentRemaining,
        clusters.TemperatureMeasurement.attributes.MeasuredValue,
        clusters.TemperatureMeasurement.attributes.MinMeasuredValue,
        clusters.TemperatureMeasurement.attributes.MaxMeasuredValue,
    }
    local subscribe_request = cluster_subscribe_list[1]:subscribe(mock_lennox_device)
    for i, cluster in ipairs(cluster_subscribe_list) do
        if i > 1 then
            subscribe_request:merge(cluster:subscribe(mock_lennox_device))
        end
    end
    test.socket.capability:__expect_send(
        mock_lennox_device:generate_test_message("main",
            capabilities.thermostatOperatingState.supportedThermostatOperatingStates({ "idle", "heating", "cooling" },
                { visibility = { displayed = false } }))
    )
    test.socket.matter:__expect_send({ mock_lennox_device.id, subscribe_request })

    local read_setpoint_deadband = clusters.Thermostat.attributes.MinSetpointDeadBand:read()
    test.socket.matter:__expect_send({ mock_lennox_device.id, read_setpoint_deadband })

    test.mock_device.add_test_device(mock_lennox_device)

    test.socket.device_lifecycle:__queue_receive({ mock_lennox_device.id, "added" })
    local read_req = clusters.Thermostat.attributes.ControlSequenceOfOperation:read()
    read_req:merge(clusters.FanControl.attributes.FanModeSequence:read())
    read_req:merge(clusters.FanControl.attributes.WindSupport:read())
    read_req:merge(clusters.FanControl.attributes.RockSupport:read())
    read_req:merge(clusters.FanControl.attributes.RockSupport:read())
    read_req:merge(clusters.PowerSource.attributes.AttributeList:read())
    read_req:merge(clusters.Thermostat.attributes.AttributeList:read())
    test.socket.matter:__expect_send({ mock_lennox_device.id, read_req })

    test.set_rpc_version(6)
end

test.set_test_init_function(test_init)

test.register_message_test(
    "Lennox thermostat uses 0.5 setpoint range step",
    {
        {
            channel = "matter",
            direction = "receive",
            message = {
                mock_lennox_device.id,
                clusters.Thermostat.attributes.AbsMinHeatSetpointLimit:build_test_report_data(mock_lennox_device, 1, 1000)
            }
        },
        {
            channel = "matter",
            direction = "receive",
            message = {
                mock_lennox_device.id,
                clusters.Thermostat.attributes.AbsMaxHeatSetpointLimit:build_test_report_data(mock_lennox_device, 1, 3222)
            }
        },
        {
            channel = "capability",
            direction = "send",
            message = mock_lennox_device:generate_test_message("main",
                capabilities.thermostatHeatingSetpoint.heatingSetpointRange({ value = { minimum = 10.00, maximum = 32.22, step = 0.5 }, unit =
                "C" }))
        }
    },
    {
        min_api_version = 17
    }
)

test.run_registered_tests()
