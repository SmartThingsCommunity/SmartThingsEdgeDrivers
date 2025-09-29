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
local cluster_base = require "st.zigbee.cluster_base"
local IasEnrollResponseCode = require "st.zigbee.generated.zcl_clusters.IASZone.types.EnrollResponseCode"
local OnOff = clusters.OnOff
local Scenes = clusters.Scenes
local Basic = clusters.Basic
local Identify = clusters.Identify
local PowerConfiguration = clusters.PowerConfiguration
local Groups = clusters.Groups
local IASZone = clusters.IASZone
local IASWD = clusters.IASWD
local IaswdLevel = IASWD.types.IaswdLevel
local WarningMode = IASWD.types.WarningMode
local SquawkMode = IASWD.types.SquawkMode
local SirenConfiguration = IASWD.types.SirenConfiguration
local SquawkConfiguration = IASWD.types.SquawkConfiguration
local ZoneStatusAttribute = IASZone.attributes.ZoneStatus

local PRIMARY_SW_VERSION = "primary_sw_version"
local SIREN_ENDIAN = "siren_endian"
local ALARM_MAX_DURATION = "maxDuration"
local ALARM_DEFAULT_MAX_DURATION = 0x00F0
local ALARM_DURATION_TEST_VALUE = 5
local DEVELCO_BASIC_PRIMARY_SW_VERSION_ATTR = 0x8000
local DEVELCO_MANUFACTURER_CODE = 0x1015
local IASZONE_ENDPOINT = 0x2B

local capabilities = require "st.capabilities"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local data_types = require "st.zigbee.data_types"
local t_utils = require "integration_test.utils"


local mock_device = test.mock_device.build_test_zigbee_device(
        {
            profile = t_utils.get_profile_definition("frient-siren-battery-source-tamper.yml"),
            zigbee_endpoints = {
                [0x01] = {
                    id = 0x01,
                    manufacturer = "frient A/S",
                    model = "SIRZB-111",
                    server_clusters = { Scenes.ID, OnOff.ID}
                },
                [0x2B] = {
                    id = 0x2B,
                    server_clusters = { Basic.ID, Identify.ID, PowerConfiguration.ID, Groups.ID, IASZone.ID, IASWD.ID }
                }
            }
        }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
    test.mock_device.add_test_device(mock_device)
end

test.set_test_init_function(test_init)

local function set_new_firmware_and_defaults()
    -- set the firmware version and endian format for testing
    mock_device:set_field(PRIMARY_SW_VERSION, "010903", {persist = true})
    mock_device:set_field(SIREN_ENDIAN, nil, {persist = true})
    -- set test durations and parameters
    mock_device:set_field(ALARM_MAX_DURATION, ALARM_DURATION_TEST_VALUE, {persist = true})
end

local function set_older_firmware_and_defaults()
    -- set the firmware version and endian format for testing
    mock_device:set_field(PRIMARY_SW_VERSION, "010901", {persist = true})
    mock_device:set_field(SIREN_ENDIAN, nil, {persist = true})
    -- set test durations and parameters
    mock_device:set_field(ALARM_MAX_DURATION, ALARM_DURATION_TEST_VALUE, {persist = true})
end

local function get_siren_commands_new_fw(warningMode, sirenLevel)
    local expectedSirenONConfiguration = SirenConfiguration(0x00)
    expectedSirenONConfiguration:set_warning_mode(warningMode) --WarningMode.BURGLAR
    expectedSirenONConfiguration:set_siren_level(sirenLevel) --IaswdLevel.VERY_HIGH_LEVEL

    test.socket.zigbee:__expect_send({
        mock_device.id,
        IASWD.server.commands.StartWarning(
                mock_device,
                expectedSirenONConfiguration,
                data_types.Uint16(ALARM_DURATION_TEST_VALUE),
                data_types.Uint8(0x00),
                data_types.Enum8(0x00)
        )
    })
end

local function get_siren_commands_old_fw(warningMode, sirenLevel)
    local expectedSirenONConfiguration
    local siren_config_value = (sirenLevel << 6) | warningMode
    expectedSirenONConfiguration = SirenConfiguration(siren_config_value)

    test.socket.zigbee:__expect_send({
        mock_device.id,
        IASWD.server.commands.StartWarning(
                mock_device,
                expectedSirenONConfiguration,
                data_types.Uint16(ALARM_DURATION_TEST_VALUE),
                data_types.Uint8(0x00),
                data_types.Enum8(0x00)
        )
    })
end

local function get_siren_OFF_commands()
    local expectedSirenONConfiguration = SirenConfiguration(0x00)
    expectedSirenONConfiguration:set_warning_mode(WarningMode.STOP)
    expectedSirenONConfiguration:set_siren_level(IaswdLevel.LOW_LEVEL)

    test.socket.zigbee:__expect_send({
        mock_device.id,
        IASWD.server.commands.StartWarning(
                mock_device,
                expectedSirenONConfiguration,
                data_types.Uint16(ALARM_DURATION_TEST_VALUE),
                data_types.Uint8(0x00),
                data_types.Enum8(0x00)
        )
    })
end

local function get_squawk_command_new_fw(squawk_mode, squawk_siren_level)
    local expected_squawk_configuration = SquawkConfiguration(0x00)
    expected_squawk_configuration:set_squawk_mode(squawk_mode)
    expected_squawk_configuration:set_squawk_level(squawk_siren_level)

    test.socket.zigbee:__expect_send({
        mock_device.id,
        IASWD.server.commands.Squawk(
                mock_device,
                expected_squawk_configuration
        )
    })
end

local function get_squawk_command_older_fw(squawk_mode, squawk_siren_level)
    local expected_squawk_configuration
    local squawk_config_value = (squawk_siren_level << 6) | squawk_mode
    expected_squawk_configuration = SquawkConfiguration(squawk_config_value)

    test.socket.zigbee:__expect_send({
        mock_device.id,
        IASWD.server.commands.Squawk(
                mock_device,
                expected_squawk_configuration
        )
    })
end

test.register_coroutine_test(
        "lifecycles - init and doConfigure test",
        function()
            test.socket.device_lifecycle:__queue_receive({ mock_device.id, "init" })
            test.wait_for_events()
            test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })

            test.socket.zigbee:__expect_send({
                mock_device.id,
                IASWD.attributes.MaxDuration:write(
                        mock_device,
                        ALARM_DEFAULT_MAX_DURATION
                )
            })

            test.socket.zigbee:__expect_send({
                mock_device.id,
                cluster_base.read_manufacturer_specific_attribute(
                        mock_device,
                        Basic.ID,
                        DEVELCO_BASIC_PRIMARY_SW_VERSION_ATTR,
                        DEVELCO_MANUFACTURER_CODE)
            })

            test.socket.zigbee:__expect_send({
                mock_device.id,
                zigbee_test_utils.build_bind_request(
                        mock_device,
                        zigbee_test_utils.mock_hub_eui,
                        PowerConfiguration.ID,
                        0x2B
                ):to_endpoint(0x2B)
            })

            test.socket.zigbee:__expect_send({
                mock_device.id,
                PowerConfiguration.attributes.BatteryPercentageRemaining:configure_reporting(
                        mock_device,
                        30,
                        21600,
                        1
                )
            })

            test.socket.zigbee:__expect_send({
                mock_device.id,
                zigbee_test_utils.build_bind_request(
                        mock_device,
                        zigbee_test_utils.mock_hub_eui,
                        IASZone.ID,
                        0x2B
                ):to_endpoint(0x2B)
            })

            test.socket.zigbee:__expect_send({
                mock_device.id,
                IASZone.attributes.ZoneStatus:configure_reporting(
                        mock_device,
                        0,
                        21600,
                        1
                )
            })

            test.socket.zigbee:__expect_send({
                mock_device.id,
                IASZone.attributes.IASCIEAddress:write(
                        mock_device,
                        zigbee_test_utils.mock_hub_eui
                )
            })

            test.socket.zigbee:__expect_send({
                mock_device.id,
                IASZone.server.commands.ZoneEnrollResponse(
                        mock_device,
                        IasEnrollResponseCode.SUCCESS,
                        0x00
                )
            })

            mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })

        end
)

test.register_coroutine_test(
        "lifecycle - added test",
        function()
            test.socket.capability:__set_channel_ordering("relaxed")
            test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
            test.socket.capability:__expect_send(
                    mock_device:generate_test_message(
                            "SirenVoice",
                            capabilities.mode.supportedModes({ "Burglar", "Fire", "Emergency", "Panic", "Panic Fire", "Panic Emergency" }, { visibility = { displayed = false } }
                            )
                    )
            )
            test.socket.capability:__expect_send(
                    mock_device:generate_test_message(
                            "SirenVoice",
                            capabilities.mode.supportedArguments({ "Burglar", "Fire", "Emergency", "Panic", "Panic Fire", "Panic Emergency" }, { visibility = { displayed = false } })
                    )
            )
            test.socket.capability:__expect_send(
                    mock_device:generate_test_message(
                            "SirenVoice",
                            capabilities.mode.mode("Burglar")
                    )
            )
            test.socket.capability:__expect_send(
                    mock_device:generate_test_message(
                            "SirenVolume",
                            capabilities.mode.supportedModes({ "Low", "Medium", "High", "Very High" }, { visibility = { displayed = false } })
                    )
            )
            test.socket.capability:__expect_send(
                    mock_device:generate_test_message(
                            "SirenVolume",
                            capabilities.mode.supportedArguments({ "Low", "Medium", "High", "Very High" }, { visibility = { displayed = false } })
                    )
            )
            test.socket.capability:__expect_send(
                    mock_device:generate_test_message(
                            "SirenVolume",
                            capabilities.mode.mode({value = "Very High"})
                    )
            )
            test.socket.capability:__expect_send(
                    mock_device:generate_test_message(
                            "SquawkVoice",
                            capabilities.mode.supportedModes({ "Armed", "Disarmed" }, { visibility = { displayed = false } })
                    )
            )
            test.socket.capability:__expect_send(
                    mock_device:generate_test_message(
                            "SquawkVoice",
                            capabilities.mode.supportedArguments({ "Armed", "Disarmed" }, { visibility = { displayed = false } })
                    )
            )
            test.socket.capability:__expect_send(
                    mock_device:generate_test_message(
                            "SquawkVoice",
                            capabilities.mode.mode("Armed")
                    )
            )
            test.socket.capability:__expect_send(
                    mock_device:generate_test_message(
                            "SquawkVolume",
                            capabilities.mode.supportedModes({ "Low", "Medium", "High", "Very High" }, { visibility = { displayed = false } })
                    )
            )
            test.socket.capability:__expect_send(
                    mock_device:generate_test_message(
                            "SquawkVolume",
                            capabilities.mode.supportedArguments({ "Low", "Medium", "High", "Very High" }, { visibility = { displayed = false } })
                    )
            )
            test.socket.capability:__expect_send(
                    mock_device:generate_test_message(
                            "SquawkVolume",
                            capabilities.mode.mode("Very High")
                    )
            )

            test.socket.capability:__expect_send(
                    mock_device:generate_test_message(
                            "main",
                            capabilities.alarm.alarm.off()
                    )
            )

            test.socket.capability:__expect_send(
                    mock_device:generate_test_message(
                            "main",
                            capabilities.tamperAlert.tamper.clear()
                    )
            )
        end
)

test.register_coroutine_test(
        "Should detect newer firmware version and use correct endian format to turn on the siren (test with default settings)",
        function()
            set_new_firmware_and_defaults()

            -- Verify fields are set correctly
            assert(mock_device:get_field(PRIMARY_SW_VERSION) >= "010903", "PRIMARY_SW_VERSION should be greater than or equal to '010903'")

            test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
            test.timer.__create_and_queue_test_time_advance_timer(5, "oneshot")

            -- Test the siren command with reversed endian
            test.socket.capability:__queue_receive({
                mock_device.id,
                { capability = "alarm", component = "main", command = "siren", args = {} }
            })

            test.mock_time.advance_time(1)
            -- Expect the command with given configuration
            get_siren_commands_new_fw(WarningMode.BURGLAR,IaswdLevel.VERY_HIGH_LEVEL)
            test.mock_time.advance_time(ALARM_DURATION_TEST_VALUE)
            -- stop the siren
            -- Expect the OFF command
            get_siren_OFF_commands()
            test.wait_for_events()
        end
)

test.register_coroutine_test(
        "Should detect older firmware version and use correct endian format to turn on the siren (test with default settings)",
        function()
            set_older_firmware_and_defaults()
            -- Verify fields are set correctly
            assert(mock_device:get_field(PRIMARY_SW_VERSION) < "010903", "PRIMARY_SW_VERSION should be lower than '010903'")

            test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
            test.timer.__create_and_queue_test_time_advance_timer(5, "oneshot")

            -- Test the siren command with reversed endian
            test.socket.capability:__queue_receive({
                mock_device.id,
                { capability = "alarm", component = "main", command = "siren", args = {} }
            })

            test.mock_time.advance_time(1)
            -- Expect the command with given configuration
            get_siren_commands_old_fw(WarningMode.BURGLAR,IaswdLevel.VERY_HIGH_LEVEL)
            test.mock_time.advance_time(ALARM_DURATION_TEST_VALUE)
            -- stop the siren
            -- Expect the OFF command
            get_siren_OFF_commands()
            test.wait_for_events()
        end
)

test.register_coroutine_test(
        "Alarm OFF should be handled",
        function()
            set_new_firmware_and_defaults()
            test.socket.capability:__queue_receive({
                mock_device.id,
                { capability = "alarm", component = "main", command = "off", args = {} }
            })
            get_siren_OFF_commands()
            test.wait_for_events()
        end
)

test.register_coroutine_test(
        "SirenVoice mode 'Fire' and SirenVolume mode 'LOW' should be handled",
        function()
            set_new_firmware_and_defaults()
            test.socket.capability:__set_channel_ordering("relaxed")
            test.socket.zigbee:__set_channel_ordering("relaxed")
            test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
            test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
            test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
            test.timer.__create_and_queue_test_time_advance_timer(5, "oneshot")

            test.socket.capability:__queue_receive({
                mock_device.id,
                { capability = "mode", component = "SirenVoice", command = "setMode", args = {"Fire"} }
            })
            test.mock_time.advance_time(2)
            test.socket.capability:__expect_send(
                    mock_device:generate_test_message("SirenVoice", capabilities.mode.mode("Fire"))
            )

            test.socket.capability:__queue_receive({
                mock_device.id,
                { capability = "mode", component = "SirenVolume", command = "setMode", args = {"Low"} }
            })
            test.mock_time.advance_time(2)
            test.socket.capability:__expect_send(
                    mock_device:generate_test_message("SirenVolume", capabilities.mode.mode("Low"))
            )

            -- Test siren with update configuration
            test.socket.capability:__queue_receive({
                mock_device.id,
                { capability = "alarm", component = "main", command = "siren", args = {} }
            })

            test.mock_time.advance_time(1)
            -- Expect the command with given configuration
            get_siren_commands_new_fw(WarningMode.FIRE,IaswdLevel.LOW_LEVEL)
            test.mock_time.advance_time(ALARM_DURATION_TEST_VALUE)
            -- stop the siren
            -- Expect the OFF command
            get_siren_OFF_commands()
            test.wait_for_events()
        end
)

test.register_coroutine_test(
        "Should detect newer firmware version and use correct endian format to turn on squawk (test with default settings)",
        function()
            set_new_firmware_and_defaults()

            -- Verify fields are set correctly
            assert(mock_device:get_field(PRIMARY_SW_VERSION) >= "010903", "PRIMARY_SW_VERSION should be greater than or equal to '010903'")

            test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")

            -- Test the siren command with reversed endian
            test.socket.capability:__queue_receive({
                mock_device.id,
                { capability = "tone", component = "main", command = "beep", args = {} }
            })

            test.mock_time.advance_time(1)
            -- Expect the command with given configuration
            get_squawk_command_new_fw( SquawkMode.SOUND_FOR_SYSTEM_IS_ARMED, IaswdLevel.VERY_HIGH_LEVEL )
            test.wait_for_events()
        end
)

test.register_coroutine_test(
        "Should detect older firmware version and use correct endian format to turn on squawk (test with default settings)",
        function()
            set_older_firmware_and_defaults()

            -- Verify fields are set correctly
            assert(mock_device:get_field(PRIMARY_SW_VERSION) < "010903", "PRIMARY_SW_VERSION should be lower than '010903'")

            test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")

            -- Test the siren command with reversed endian
            test.socket.capability:__queue_receive({
                mock_device.id,
                { capability = "tone", component = "main", command = "beep", args = {} }
            })

            test.mock_time.advance_time(1)
            -- Expect the command with given configuration
            get_squawk_command_older_fw( SquawkMode.SOUND_FOR_SYSTEM_IS_ARMED, IaswdLevel.VERY_HIGH_LEVEL )
            test.wait_for_events()
        end
)

test.register_coroutine_test(
        "SquawkVoice mode 'Disarmed'  and SquawkVolume mode 'Medium' should be handled",
        function()
            set_new_firmware_and_defaults()
            test.socket.capability:__set_channel_ordering("relaxed")
            test.socket.zigbee:__set_channel_ordering("relaxed")
            test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
            test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
            test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")

            test.socket.capability:__queue_receive({
                mock_device.id,
                { capability = "mode", component = "SquawkVoice", command = "setMode", args = { "Disarmed" } }
            })
            test.mock_time.advance_time(2)
            test.socket.capability:__expect_send(
                    mock_device:generate_test_message("SquawkVoice", capabilities.mode.mode("Disarmed"))
            )

            test.socket.capability:__queue_receive({
                mock_device.id,
                { capability = "mode", component = "SquawkVolume", command = "setMode", args = { "Medium" } }
            })
            test.mock_time.advance_time(2)
            test.socket.capability:__expect_send(
                    mock_device:generate_test_message("SquawkVolume", capabilities.mode.mode("Medium"))
            )

            -- Test siren with update configuration
            test.socket.capability:__queue_receive({
                mock_device.id,
                { capability = "tone", component = "main", command = "beep", args = {} }
            })

            test.mock_time.advance_time(1)
            -- Expect the command with given configuration
            get_squawk_command_new_fw(SquawkMode.SOUND_FOR_SYSTEM_IS_DISARMED, IaswdLevel.MEDIUM_LEVEL)
            test.wait_for_events()
        end
)

test.register_coroutine_test(
        "Refresh should be handled - new FW",
        function()
            set_new_firmware_and_defaults()
            test.socket.capability:__queue_receive({
                mock_device.id,
                { capability = "refresh", component = "main", command = "refresh", args = {} }
            })

            test.socket.zigbee:__expect_send(
                    {
                        mock_device.id,
                        IASZone.attributes.ZoneStatus:read(mock_device)
                    }
            )
            test.wait_for_events()
        end
)

test.register_coroutine_test(
        "Refresh should be handled - FW not known",
        function()
            test.socket.zigbee:__set_channel_ordering("relaxed")
            test.socket.capability:__queue_receive({
                mock_device.id,
                { capability = "refresh", component = "main", command = "refresh", args = {} }
            })

            test.socket.zigbee:__expect_send(
                    {
                        mock_device.id,
                        IASZone.attributes.ZoneStatus:read(mock_device)
                    }
            )

            test.socket.zigbee:__expect_send(
                    {
                        mock_device.id,
                        cluster_base.read_manufacturer_specific_attribute(
                                mock_device,
                                Basic.ID,
                                DEVELCO_BASIC_PRIMARY_SW_VERSION_ATTR,
                                DEVELCO_MANUFACTURER_CODE
                        )
                    }
            )

            test.wait_for_events()
        end
)

test.register_message_test(
        "Power source / mains should be handled",
        {
            {
                channel = "zigbee",
                direction = "receive",
                message = { mock_device.id, ZoneStatusAttribute:build_test_attr_report(mock_device, 0x0005) }
            },
            {
                channel = "capability",
                direction = "send",
                message = mock_device:generate_test_message("main", capabilities.powerSource.powerSource.mains())
            },
            {
                channel = "capability",
                direction = "send",
                message = mock_device:generate_test_message("main", capabilities.tamperAlert.tamper.detected())
            }
        },
        {
            inner_block_ordering = "relaxed"
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
            },
            {
                channel = "capability",
                direction = "send",
                message = mock_device:generate_test_message("main", capabilities.tamperAlert.tamper.clear())
            }
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
                message = { mock_device.id, PowerConfiguration.attributes.BatteryPercentageRemaining:build_test_attr_report(mock_device, 0xC8) }
            },
            {
                channel = "capability",
                direction = "send",
                message = mock_device:generate_test_message("main", capabilities.battery.battery(100))
            }
        }
)

test.register_message_test(
        "Medium battery voltage report should be handled",
        {
            {
                channel = "zigbee",
                direction = "receive",
                message = { mock_device.id, PowerConfiguration.attributes.BatteryPercentageRemaining:build_test_attr_report(mock_device, 0x64) }
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
                message = { mock_device.id, PowerConfiguration.attributes.BatteryPercentageRemaining:build_test_attr_report(mock_device, 0) }
            },
            {
                channel = "capability",
                direction = "send",
                message = mock_device:generate_test_message("main", capabilities.battery.battery(0))
            }
        }
)

test.run_registered_tests()
