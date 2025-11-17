-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

-- Mock out globals
local test = require "integration_test"
local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"

local IASZone = clusters.IASZone
local PowerConfiguration = clusters.PowerConfiguration
local ZoneStatusAttribute = IASZone.attributes.ZoneStatus

local mock_device = test.mock_device.build_test_zigbee_device(
        {
            profile = t_utils.get_profile_definition("range-extender-battery-source.yml"),
            zigbee_endpoints = {
                [0x01] = {
                    id = 0x01,
                    manufacturer = "frient A/S",
                    model = "REXZB-111",
                    server_clusters = {IASZone.ID, PowerConfiguration.ID }
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
        "Refresh necessary attributes",
    function()
            test.socket.zigbee:__set_channel_ordering("relaxed")
            test.socket.capability:__queue_receive({ mock_device.id, { capability = "refresh", component = "main", command = "refresh", args = {} } })
            test.socket.zigbee:__expect_send(
                    {
                        mock_device.id,
                        IASZone.attributes.ZoneStatus:read(mock_device)
                    }
            )
            test.socket.zigbee:__expect_send(
                    {
                        mock_device.id,
                        PowerConfiguration.attributes.BatteryVoltage:read(mock_device)
                    }
            )
        end
)

test.register_coroutine_test(
        "lifecycles - init and doConfigure test",
        function()
            test.socket.device_lifecycle:__queue_receive({ mock_device.id, "init" })
            test.wait_for_events()
            test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })

            test.socket.zigbee:__expect_send({
                mock_device.id,
                PowerConfiguration.attributes.BatteryVoltage:read( mock_device )
            })

            test.socket.zigbee:__expect_send({
                mock_device.id,
                IASZone.attributes.ZoneStatus:read( mock_device )
            })

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
                PowerConfiguration.attributes.BatteryVoltage:configure_reporting(
                        mock_device,
                        30,
                        21600,
                        1
                )
            })

            mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })

        end
)

test.register_message_test(
        "Power source / mains should be handled",
        {
            {
                channel = "zigbee",
                direction = "receive",
                message = { mock_device.id, ZoneStatusAttribute:build_test_attr_report(mock_device, 0x0001) }
            },
            {
                channel = "capability",
                direction = "send",
                message = mock_device:generate_test_message("main", capabilities.powerSource.powerSource.mains())
            }
        }
)

test.register_message_test(
        "Power source / battery should be handled",
        {
            {
                channel = "zigbee",
                direction = "receive",
                message = { mock_device.id, ZoneStatusAttribute:build_test_attr_report(mock_device, 0x0081) }
            },
            {
                channel = "capability",
                direction = "send",
                message = mock_device:generate_test_message("main", capabilities.powerSource.powerSource.battery())
            }
        }
)

test.register_message_test(
        "Min battery voltage report should be handled",
        {
            {
                channel = "zigbee",
                direction = "receive",
                message = { mock_device.id, PowerConfiguration.attributes.BatteryVoltage:build_test_attr_report(mock_device, 33) }
            },
            {
                channel = "capability",
                direction = "send",
                message = mock_device:generate_test_message("main", capabilities.battery.battery(0))
            }
        }
)

test.register_message_test(
        "Medium battery voltage report should be handled",
        {
            {
                channel = "zigbee",
                direction = "receive",
                message = { mock_device.id, PowerConfiguration.attributes.BatteryVoltage:build_test_attr_report(mock_device, 37) }
            },
            {
                channel = "capability",
                direction = "send",
                message = mock_device:generate_test_message("main", capabilities.battery.battery(50))
            }
        }
)

test.register_message_test(
        "Max battery voltage report should be handled",
        {
            {
                channel = "zigbee",
                direction = "receive",
                message = { mock_device.id, PowerConfiguration.attributes.BatteryVoltage:build_test_attr_report(mock_device, 41) }
            },
            {
                channel = "capability",
                direction = "send",
                message = mock_device:generate_test_message("main", capabilities.battery.battery(100))
            }
        }
)

test.run_registered_tests()
