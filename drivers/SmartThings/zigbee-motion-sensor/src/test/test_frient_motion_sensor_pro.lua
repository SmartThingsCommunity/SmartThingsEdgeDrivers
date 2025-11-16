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
local base64 = require "base64"
local test = require "integration_test"
local t_utils = require "integration_test.utils"

local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local zcl_clusters = require "st.zigbee.zcl.clusters"

local IASZone = zcl_clusters.IASZone
local IasEnrollResponseCode = require "st.zigbee.generated.zcl_clusters.IASZone.types.EnrollResponseCode"
local IlluminanceMeasurement = zcl_clusters.IlluminanceMeasurement
local OccupancySensing = zcl_clusters.OccupancySensing
local PowerConfiguration = zcl_clusters.PowerConfiguration
local TemperatureMeasurement = zcl_clusters.TemperatureMeasurement

local capabilities = require "st.capabilities"

local IASZONE_ENDPOINT = 0x23
local ILLUMINANCE_ENDPOINT = 0x27
local OCCUPANCY_ENDPOINT = 0x22
local POWER_CONFIGURATION_ENDPOINT = 0x23
local TAMPER_ENDPOINT = 0x23
local TEMPERATURE_MEASUREMENT_ENDPOINT = 0x26

local DEFAULT_OCCUPIED_TO_UNOCCUPIED_DELAY = 240
local DEFAULT_UNOCCUPIED_TO_OCCUPIED_DELAY = 0
local DEFAULT_UNOCCUPIED_TO_OCCUPIED_THRESHOLD = 0

local mock_device = test.mock_device.build_test_zigbee_device(
        {
            profile = t_utils.get_profile_definition("frient-motion-temp-illuminance-tamper-battery.yml"),
            zigbee_endpoints = {
                [0x22] = {
                    id = 0x22,
                    manufacturer = "frient A/S",
                    model = "MOSZB-140",
                    server_clusters = { 0x0000, 0x0003, 0x0406 }
                },
                [0x23] = {
                    id = 0x23,
                    server_clusters = { 0x0000, 0x0001, 0x000f, 0x0020, 0x0500 }
                },
                [0x26] = {
                    id = 0x26,
                    server_clusters = { 0x0000, 0x0003, 0x0402 }
                },
                [0x27] = {
                    id = 0x27,
                    server_clusters = { 0x0000, 0x0003, 0x0400 }
                },
                [0x28] = {
                    id = 0x28,
                    server_clusters = { 0x0000, 0x0003, 0x0406 }
                },
                [0x29] = {
                    id = 0x29,
                    server_clusters = { 0x0000, 0x0003, 0x0406 }
                }
            }
        }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
    test.mock_device.add_test_device(mock_device)end
test.set_test_init_function(test_init)

test.register_coroutine_test(
        "Motion inactive and tamper clear states when the device is added", function()
            test.socket.matter:__set_channel_ordering("relaxed")
            test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })

            test.socket.capability:__expect_send(
                    mock_device:generate_test_message("main", capabilities.motionSensor.motion.inactive())
            )
            test.socket.capability:__expect_send(
                    mock_device:generate_test_message("main", capabilities.tamperAlert.tamper.clear())
            )
            test.wait_for_events()
        end
)

test.register_message_test(
        "Battery voltage report should be handled",
        {
            {
                channel = "zigbee",
                direction = "receive",
                message = { mock_device.id, PowerConfiguration.attributes.BatteryVoltage:build_test_attr_report(mock_device, 24) }
            },
            {
                channel = "capability",
                direction = "send",
                message = mock_device:generate_test_message("main", capabilities.battery.battery(14))
            }
        }
)

test.register_message_test(
        "ZoneStatusChangeNotification should be handled: tamper detected",
        {
            {
                channel = "zigbee",
                direction = "receive",
                -- ZoneStatus | Bit2: Tamper set to 1
                message = { mock_device.id, IASZone.client.commands.ZoneStatusChangeNotification.build_test_rx(mock_device, 0x0004, 0x00) }
            },
            {
                channel = "capability",
                direction = "send",
                message = mock_device:generate_test_message("main", capabilities.tamperAlert.tamper.detected())
            }
        }
)

test.register_message_test(
        "ZoneStatusChangeNotification should be handled: tamper clear",
        {
            {
                channel = "zigbee",
                direction = "receive",
                -- ZoneStatus | Bit2: Tamper set to 0
                message = { mock_device.id, IASZone.client.commands.ZoneStatusChangeNotification.build_test_rx(mock_device, 0x0000, 0x00) }
            },
            {
                channel = "capability",
                direction = "send",
                message = mock_device:generate_test_message("main", capabilities.tamperAlert.tamper.clear())
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
            },
            {
            channel = "devices",
            direction = "send",
            message = {
                "register_native_capability_attr_handler",
                { device_uuid = mock_device.id, capability_id = "temperatureMeasurement", capability_attr_id = "temperature" }
            }
            }
        }
)

test.register_message_test(
        "Illuminance report should be handled",
        {
            {
                channel = "zigbee",
                direction = "receive",
                message = {
                    mock_device.id,
                    IlluminanceMeasurement.attributes.MeasuredValue:build_test_attr_report(mock_device, 21370)
                }
            },
            {
                channel = "capability",
                direction = "send",
                message = mock_device:generate_test_message("main", capabilities.illuminanceMeasurement.illuminance({ value = 137 }))
            }
        }
)

-- test.register_coroutine_test(
--         "Health check should check all relevant attributes",
--         function()
--             test.wait_for_events()
--             test.mock_time.advance_time(50000)
--             test.socket.zigbee:__set_channel_ordering("relaxed")
--             test.socket.zigbee:__expect_send(
--                 {
--                     mock_device.id,
--                     IASZone.attributes.ZoneStatus:read(mock_device):to_endpoint(TAMPER_ENDPOINT)
--                 }
--             )
--             test.socket.zigbee:__expect_send(
--                 {
--                     mock_device.id,
--                     IlluminanceMeasurement.attributes.MeasuredValue:read(mock_device):to_endpoint(ILLUMINANCE_ENDPOINT)
--                 }
--             )
--             test.socket.zigbee:__expect_send(
--                 {
--                     mock_device.id,
--                     OccupancySensing.attributes.Occupancy:read(mock_device):to_endpoint(OCCUPANCY_ENDPOINT)
--                 }
--             )
--             test.socket.zigbee:__expect_send(
--                 {
--                     mock_device.id,
--                     PowerConfiguration.attributes.BatteryVoltage:read(mock_device):to_endpoint(POWER_CONFIGURATION_ENDPOINT)
--                 }
--             )
--             test.socket.zigbee:__expect_send(
--                 {
--                     mock_device.id,
--                     TemperatureMeasurement.attributes.MeasuredValue:read(mock_device):to_endpoint(TEMPERATURE_MEASUREMENT_ENDPOINT)
--                 }
--             )
--         end,
--         {
--             test_init = function()
--                 test.mock_device.add_test_device(mock_device)
--                 test.timer.__create_and_queue_test_time_advance_timer(30, "interval", "health_check")
--             end
--         }
-- )

test.register_coroutine_test(
        "Refresh should read all necessary attributes",
        function()
            test.socket.zigbee:__set_channel_ordering("relaxed")
            test.socket.capability:__queue_receive({mock_device.id, { capability = "refresh", component = "main", command = "refresh", args = {} }})
            test.socket.zigbee:__expect_send({mock_device.id, PowerConfiguration.attributes.BatteryVoltage:read(mock_device):to_endpoint(POWER_CONFIGURATION_ENDPOINT)})
            test.socket.zigbee:__expect_send({mock_device.id, IASZone.attributes.ZoneStatus:read(mock_device):to_endpoint(TAMPER_ENDPOINT)})
            test.socket.zigbee:__expect_send({mock_device.id, OccupancySensing.attributes.Occupancy:read(mock_device):to_endpoint(OCCUPANCY_ENDPOINT)})
            test.socket.zigbee:__expect_send({mock_device.id, TemperatureMeasurement.attributes.MeasuredValue:read(mock_device):to_endpoint(TEMPERATURE_MEASUREMENT_ENDPOINT)})
            test.socket.zigbee:__expect_send({mock_device.id, IlluminanceMeasurement.attributes.MeasuredValue:read(mock_device):to_endpoint(ILLUMINANCE_ENDPOINT)})
        end
)

test.register_coroutine_test(
        "init and doConfigure lifecycles should be handled properly",
        function()
            test.socket.environment_update:__queue_receive({ "zigbee", { hub_zigbee_id = base64.encode(zigbee_test_utils.mock_hub_eui) } })
            test.socket.zigbee:__set_channel_ordering("relaxed")

            test.socket.device_lifecycle:__queue_receive({ mock_device.id, "init" })
            test.wait_for_events()
            test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })

            test.socket.capability:__expect_send(
                    mock_device:generate_test_message("main", capabilities.motionSensor.motion.inactive())
            )
            test.socket.capability:__expect_send(
                    mock_device:generate_test_message("main", capabilities.tamperAlert.tamper.clear())
            )

            test.wait_for_events()
            test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })

            test.socket.zigbee:__expect_send({
                mock_device.id,
                zigbee_test_utils.build_bind_request(
                        mock_device,
                        zigbee_test_utils.mock_hub_eui,
                        PowerConfiguration.ID,
                        POWER_CONFIGURATION_ENDPOINT
                ):to_endpoint(POWER_CONFIGURATION_ENDPOINT)
            })

            test.socket.zigbee:__expect_send({
                mock_device.id,
                PowerConfiguration.attributes.BatteryVoltage:configure_reporting(
                        mock_device,
                        30,
                        21600,
                        1
                ):to_endpoint(POWER_CONFIGURATION_ENDPOINT)
            })

            test.socket.zigbee:__expect_send({
                mock_device.id,
                zigbee_test_utils.build_bind_request(
                        mock_device,
                        zigbee_test_utils.mock_hub_eui,
                        IASZone.ID,
                        IASZONE_ENDPOINT
                ):to_endpoint(IASZONE_ENDPOINT)
            })

            test.socket.zigbee:__expect_send({
                mock_device.id,
                IASZone.attributes.ZoneStatus:configure_reporting(
                        mock_device,
                        30,
                        300,
                        1
                ):to_endpoint(IASZONE_ENDPOINT)
            })

            test.socket.zigbee:__expect_send({
                mock_device.id,
                zigbee_test_utils.build_bind_request(
                        mock_device,
                        zigbee_test_utils.mock_hub_eui,
                        OccupancySensing.ID,
                        OCCUPANCY_ENDPOINT
                ):to_endpoint(OCCUPANCY_ENDPOINT)
            })

            test.socket.zigbee:__expect_send({
                mock_device.id,
                OccupancySensing.attributes.Occupancy:configure_reporting(
                        mock_device,
                        0,
                        3600
                ):to_endpoint(OCCUPANCY_ENDPOINT)
            })

            test.socket.zigbee:__expect_send({
                mock_device.id,
                IASZone.attributes.IASCIEAddress:write(
                        mock_device,
                        zigbee_test_utils.mock_hub_eui
                ):to_endpoint(IASZONE_ENDPOINT)
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
                        TemperatureMeasurement.ID,
                        TEMPERATURE_MEASUREMENT_ENDPOINT
                ):to_endpoint(TEMPERATURE_MEASUREMENT_ENDPOINT)
            })

            test.socket.zigbee:__expect_send({
                mock_device.id,
                TemperatureMeasurement.attributes.MeasuredValue:configure_reporting(
                        mock_device,
                        30,
                        3600,
                        10
                ):to_endpoint(TEMPERATURE_MEASUREMENT_ENDPOINT)
            })

            test.socket.zigbee:__expect_send({
                mock_device.id,
                zigbee_test_utils.build_bind_request(
                        mock_device,
                        zigbee_test_utils.mock_hub_eui,
                        IlluminanceMeasurement.ID,
                        ILLUMINANCE_ENDPOINT
                ):to_endpoint(ILLUMINANCE_ENDPOINT)
            })

            test.socket.zigbee:__expect_send({
                mock_device.id,
                IlluminanceMeasurement.attributes.MeasuredValue:configure_reporting(
                        mock_device,
                        10,
                        3600,
                        0x2711
                ):to_endpoint(ILLUMINANCE_ENDPOINT)
            })

            test.socket.zigbee:__expect_send({
                mock_device.id,
                OccupancySensing.attributes.PIROccupiedToUnoccupiedDelay:write(mock_device, DEFAULT_OCCUPIED_TO_UNOCCUPIED_DELAY)
                    :to_endpoint(OCCUPANCY_ENDPOINT)
            })

            test.socket.zigbee:__expect_send({
                mock_device.id,
                OccupancySensing.attributes.PIRUnoccupiedToOccupiedDelay:write(mock_device, DEFAULT_UNOCCUPIED_TO_OCCUPIED_DELAY)
                    :to_endpoint(OCCUPANCY_ENDPOINT)
            })

            test.socket.zigbee:__expect_send({
                mock_device.id,
                OccupancySensing.attributes.PIRUnoccupiedToOccupiedThreshold:write(mock_device, DEFAULT_UNOCCUPIED_TO_OCCUPIED_THRESHOLD)
                    :to_endpoint(OCCUPANCY_ENDPOINT)
            })

            mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
        end
)

test.register_coroutine_test(
        "infochanged to check for necessary preferences settings: Temperature Sensitivity, Motion Turn-Off Delay, Motion Turn-On Delay, Movement Threshold in Turn-On Delay",
        function()
            local updates = {
                preferences = {
                    temperatureSensitivity = 0.9,
                    occupiedToUnoccupiedD = 200,
                    unoccupiedToOccupiedD = 1,
                    unoccupiedToOccupiedT = 2
                }
            }
            test.socket.zigbee:__set_channel_ordering("relaxed")
            test.wait_for_events()

            test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed(updates))

            test.socket.zigbee:__expect_send({ mock_device.id,
                                               OccupancySensing.attributes.PIRUnoccupiedToOccupiedDelay:write(mock_device, 1):to_endpoint(OCCUPANCY_ENDPOINT)
            })

            test.socket.zigbee:__expect_send({ mock_device.id,
                                               OccupancySensing.attributes.PIRUnoccupiedToOccupiedThreshold:write(mock_device, 2):to_endpoint(OCCUPANCY_ENDPOINT)
            })

            test.socket.zigbee:__expect_send({ mock_device.id,
                                               OccupancySensing.attributes.PIROccupiedToUnoccupiedDelay:write(mock_device, 200):to_endpoint(OCCUPANCY_ENDPOINT)
            })

            local temperatureSensitivity = math.floor(0.9 * 100 + 0.5)
            test.socket.zigbee:__expect_send({ mock_device.id,
                                               TemperatureMeasurement.attributes.MeasuredValue:configure_reporting(
                                                       mock_device,
                                                       30,
                                                       3600,
                                                       temperatureSensitivity
                                               ):to_endpoint(TEMPERATURE_MEASUREMENT_ENDPOINT)
            })
        end
)

test.run_registered_tests()
