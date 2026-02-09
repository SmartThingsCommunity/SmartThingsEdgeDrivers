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

-- Mock out globals
local test = require "integration_test"
local clusters = require "st.zigbee.zcl.clusters"
local ElectricalMeasurement = clusters.ElectricalMeasurement
local SimpleMetering = clusters.SimpleMetering
local PowerConfiguration = clusters.PowerConfiguration
local capabilities = require "st.capabilities"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils = require "integration_test.utils"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"

local DEVELCO_MANUFACTURER_CODE = 0x1015
local LAST_REPORT_TIME = "LAST_REPORT_TIME"

local mock_device = test.mock_device.build_test_zigbee_device(
        {
            profile = t_utils.get_profile_definition("frient-power-energy-consumption-report.yml"),
            zigbee_endpoints = {
                [1] = {
                    id = 1,
                    model = "ZHEMI101",
                    server_clusters = { ElectricalMeasurement.ID, PowerConfiguration.ID, SimpleMetering.ID }
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
        "InstantaneousDemand Report should be handled.",
        {
            {
                channel = "zigbee",
                direction = "receive",
                message = { mock_device.id, SimpleMetering.attributes.Divisor:build_test_attr_report(mock_device, 1000) }
            },
            {
                channel = "zigbee",
                direction = "receive",
                message = { mock_device.id, SimpleMetering.attributes.Multiplier:build_test_attr_report(mock_device, 1) },
            },
            {
                channel = "zigbee",
                direction = "receive",
                message = { mock_device.id, SimpleMetering.attributes.InstantaneousDemand:build_test_attr_report(mock_device, 2700) },
            },
            {
                channel = "capability",
                direction = "send",
                message = mock_device:generate_test_message("main", capabilities.powerMeter.power({ value = 2700.0, unit = "W" }))
            }
        }
)

test.register_coroutine_test(
        "lifecycle configure event should configure the device",
        function()
            test.socket.zigbee:__set_channel_ordering("relaxed")
            test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
            test.socket.zigbee:__expect_send({
                mock_device.id,
                cluster_base.write_manufacturer_specific_attribute(mock_device, SimpleMetering.ID, 0x0300, DEVELCO_MANUFACTURER_CODE, data_types.Uint16, 1000):to_endpoint(0x02)
            })
            test.socket.zigbee:__expect_send({
                mock_device.id,
                cluster_base.write_manufacturer_specific_attribute(mock_device, SimpleMetering.ID, 0x0301, DEVELCO_MANUFACTURER_CODE, data_types.Uint48, 0):to_endpoint(0x02)
            })
            test.socket.zigbee:__expect_send({
                mock_device.id,
                SimpleMetering.attributes.Divisor:read(mock_device)
            })
            test.socket.zigbee:__expect_send({
                mock_device.id,
                SimpleMetering.attributes.Multiplier:read(mock_device)
            })
            test.socket.zigbee:__expect_send({
                mock_device.id,
                SimpleMetering.attributes.CurrentSummationDelivered:read(mock_device)
            })
            test.socket.zigbee:__expect_send({
                mock_device.id,
                SimpleMetering.attributes.InstantaneousDemand:read(mock_device)
            })
            test.socket.zigbee:__expect_send({
                mock_device.id,
                ElectricalMeasurement.attributes.ACPowerMultiplier:read(mock_device)
            })
            test.socket.zigbee:__expect_send({
                mock_device.id,
                ElectricalMeasurement.attributes.ACPowerDivisor:read(mock_device)
            })
            test.socket.zigbee:__expect_send({
                mock_device.id,
                ElectricalMeasurement.attributes.ActivePower:read(mock_device)
            })

            test.socket.zigbee:__expect_send({
                mock_device.id,
                zigbee_test_utils.build_bind_request(
                    mock_device,
                    zigbee_test_utils.mock_hub_eui,
                    SimpleMetering.ID
                )
            })
            test.socket.zigbee:__expect_send({
                mock_device.id,
                zigbee_test_utils.build_bind_request(
                    mock_device,
                    zigbee_test_utils.mock_hub_eui,
                    ElectricalMeasurement.ID
                )
            })

            test.socket.zigbee:__expect_send({
                mock_device.id,
                SimpleMetering.attributes.InstantaneousDemand:configure_reporting(
                    mock_device, 5, 3600, 1
                )
            })

            test.socket.zigbee:__expect_send({
                mock_device.id,
                ElectricalMeasurement.attributes.ACPowerMultiplier:configure_reporting(
                    mock_device, 1, 43200, 1
                )
            })

            test.socket.zigbee:__expect_send({
                mock_device.id,
                ElectricalMeasurement.attributes.ACPowerDivisor:configure_reporting(
                    mock_device, 1, 43200, 1
                )
            })


            test.socket.zigbee:__expect_send({
                mock_device.id,
                ElectricalMeasurement.attributes.ActivePower:configure_reporting(
                    mock_device, 5, 3600, 5
                )
            })

            test.socket.zigbee:__expect_send({
                mock_device.id,
                SimpleMetering.attributes.CurrentSummationDelivered:configure_reporting(
                        mock_device, 5, 3600, 1
                )
            })

            mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
        end
)

test.register_message_test(
        "Refresh should read all necessary attributes",
        {
            {
                channel = "capability",
                direction = "receive",
                message = { mock_device.id, { capability = "refresh", component = "main", command = "refresh", args = {} }}
            },
            {
                channel = "zigbee",
                direction = "send",
                message = { mock_device.id, SimpleMetering.attributes.CurrentSummationDelivered:read(mock_device) }
            },
            {
                channel = "zigbee",
                direction = "send",
                message = {
                    mock_device.id, SimpleMetering.attributes.InstantaneousDemand:read(mock_device) }
            },
            {
                channel = "zigbee",
                direction = "send",
                message = {
                    mock_device.id, ElectricalMeasurement.attributes.ACPowerMultiplier:read(mock_device) }
            },
            {
                channel = "zigbee",
                direction = "send",
                message = {
                    mock_device.id, ElectricalMeasurement.attributes.ACPowerDivisor:read(mock_device) }
            },
            {
                channel = "zigbee",
                direction = "send",
                message = {
                    mock_device.id, ElectricalMeasurement.attributes.ActivePower:read(mock_device) }
            }
        },
        {
            inner_block_ordering = "relaxed"
        }
)

test.register_coroutine_test(
        "infochanged to check for necessary preferences settings: pulseConfiguration, currentSummation",
        function()
            local updates = {
                preferences = {
                    pulseConfiguration = 400,
                    currentSummation = 500
                }
            }

            test.wait_for_events()
            test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed(updates))

            test.socket.zigbee:__expect_send({
                mock_device.id,
                cluster_base.write_manufacturer_specific_attribute(
                    mock_device,
                    SimpleMetering.ID,
                    0x0300,
                    DEVELCO_MANUFACTURER_CODE,
                    data_types.Uint16,
                    400
                ):to_endpoint(0x02)
            })

            test.socket.zigbee:__expect_send({
                mock_device.id,
                cluster_base.write_manufacturer_specific_attribute(
                        mock_device,
                        SimpleMetering.ID,
                        0x0301,
                        DEVELCO_MANUFACTURER_CODE,
                        data_types.Uint48,
                        500
                ):to_endpoint(0x02)
            })

            test.socket.zigbee:__set_channel_ordering("relaxed")

        end
)

test.register_coroutine_test(
        "CurrentSummationDelivered Report should be handled.",
        function()
            local current_time = os.time() - 60 * 16
            mock_device:set_field(LAST_REPORT_TIME, current_time)

            test.socket.zigbee:__queue_receive({ mock_device.id, SimpleMetering.attributes.Divisor:build_test_attr_report(mock_device, 1000) })
            test.socket.zigbee:__queue_receive({ mock_device.id, SimpleMetering.attributes.Multiplier:build_test_attr_report(mock_device, 1) })
            test.socket.zigbee:__queue_receive({ mock_device.id, SimpleMetering.attributes.CurrentSummationDelivered:build_test_attr_report(mock_device, 2700)  })

            test.socket.capability:__expect_send(
                    mock_device:generate_test_message("main", capabilities.energyMeter.energy({ value = 2700.0, unit = "Wh" }))
            )
            test.socket.capability:__expect_send(
                mock_device:generate_test_message("main",
                    capabilities.powerConsumptionReport.powerConsumption({
                        start = "1969-12-31T23:44:00Z",
                        ["end"] = "1969-12-31T23:59:59Z",
                        deltaEnergy = 0.0,
                        energy = 2700.0
                    })
                )
            )
        end
)

test.register_coroutine_test(
        "CurrentSummationDelivered report should be handled without powerConsumptionReport because 15 min didn't pass since last report",
        function()
            local current_time = os.time() - 60 * 14
            mock_device:set_field(LAST_REPORT_TIME, current_time)

            test.socket.zigbee:__queue_receive({ mock_device.id, SimpleMetering.attributes.Divisor:build_test_attr_report(mock_device, 1000) })
            test.socket.zigbee:__queue_receive({ mock_device.id, SimpleMetering.attributes.Multiplier:build_test_attr_report(mock_device, 1) })
            test.socket.zigbee:__queue_receive({ mock_device.id, SimpleMetering.attributes.CurrentSummationDelivered:build_test_attr_report(mock_device, 2700)  })

            test.socket.capability:__expect_send(
                    mock_device:generate_test_message("main", capabilities.energyMeter.energy({ value = 2700.0, unit = "Wh" }))
            )
        end
)

test.run_registered_tests()
