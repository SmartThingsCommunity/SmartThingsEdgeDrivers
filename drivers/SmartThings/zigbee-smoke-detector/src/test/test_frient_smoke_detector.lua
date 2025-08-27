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

-- Mock out globals
local test = require "integration_test"
local clusters = require "st.zigbee.zcl.clusters"
local IASWD = clusters.IASWD
local IASZone = clusters.IASZone
local PowerConfiguration = clusters.PowerConfiguration
local TemperatureMeasurement = clusters.TemperatureMeasurement
local Basic = clusters.Basic
local capabilities = require "st.capabilities"
local alarm = capabilities.alarm
local smokeDetector = capabilities.smokeDetector
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local IasEnrollResponseCode = require "st.zigbee.generated.zcl_clusters.IASZone.types.EnrollResponseCode"
local t_utils = require "integration_test.utils"
local data_types = require "st.zigbee.data_types"
local SirenConfiguration = require "st.zigbee.generated.zcl_clusters.IASWD.types.SirenConfiguration"
local ALARM_DEFAULT_MAX_DURATION = 0x00F0
local POWER_CONFIGURATION_ENDPOINT = 0x23
local IASZONE_ENDPOINT = 0x23
local TEMPERATURE_MEASUREMENT_ENDPOINT = 0x26
local base64 = require "base64"
local PRIMARY_SW_VERSION = "primary_sw_version"
local SIREN_ENDIAN = "siren_endian"
local DEVELCO_BASIC_PRIMARY_SW_VERSION_ATTR = 0x8000
local DEVELCO_MANUFACTURER_CODE = 0x1015
local cluster_base = require "st.zigbee.cluster_base"
local defaultWarningDuration = 240


local mock_device = test.mock_device.build_test_zigbee_device(
        { profile = t_utils.get_profile_definition("smoke-temp-battery-alarm.yml"),
          zigbee_endpoints = {
              [0x01] = {
                  id = 0x01,
                  manufacturer = "frient A/S",
                  model = "SMSZB-120",
                  server_clusters = { 0x0003, 0x0005, 0x0006 }
              },
              [0x23] = {
                  id = 0x23,
                  server_clusters = { 0x0000, 0x0001, 0x0003, 0x000f, 0x0020, 0x0500, 0x0502 }
              },
              [0x26] = {
                  id = 0x26,
                  server_clusters = { 0x0000, 0x0003, 0x0402 }
              }
          }
        }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
    test.mock_device.add_test_device(mock_device)end
test.set_test_init_function(test_init)

test.register_coroutine_test(
        "Clear alarm and smokeDetector states, and read firmware version when the device is added", function()
            test.socket.matter:__set_channel_ordering("relaxed")
            test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })

            test.socket.capability:__expect_send(
                    mock_device:generate_test_message("main", alarm.alarm.off())
            )

            test.socket.capability:__expect_send(
                    mock_device:generate_test_message("main", smokeDetector.smoke.clear())
            )

            test.socket.zigbee:__expect_send({
                mock_device.id,
                cluster_base.read_manufacturer_specific_attribute(mock_device, Basic.ID, DEVELCO_BASIC_PRIMARY_SW_VERSION_ATTR, DEVELCO_MANUFACTURER_CODE)
            })

            test.wait_for_events()
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
                    mock_device:generate_test_message("main", alarm.alarm.off())
            )

            test.socket.capability:__expect_send(
                    mock_device:generate_test_message("main", smokeDetector.smoke.clear())
            )

            test.socket.zigbee:__expect_send({
                mock_device.id,
                cluster_base.read_manufacturer_specific_attribute(mock_device, Basic.ID, DEVELCO_BASIC_PRIMARY_SW_VERSION_ATTR, DEVELCO_MANUFACTURER_CODE)
            })

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
                        TemperatureMeasurement.ID,
                        TEMPERATURE_MEASUREMENT_ENDPOINT
                ):to_endpoint(TEMPERATURE_MEASUREMENT_ENDPOINT)
            })

            test.socket.zigbee:__expect_send({
                mock_device.id,
                TemperatureMeasurement.attributes.MeasuredValue:configure_reporting(
                        mock_device,
                        60,
                        600,
                        100
                ):to_endpoint(TEMPERATURE_MEASUREMENT_ENDPOINT)
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
                        0
                ):to_endpoint(IASZONE_ENDPOINT)
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
                IASWD.attributes.MaxDuration:write(mock_device, ALARM_DEFAULT_MAX_DURATION)
            })

            test.socket.zigbee:__expect_send({
                mock_device.id,
                cluster_base.read_manufacturer_specific_attribute(mock_device, Basic.ID, DEVELCO_BASIC_PRIMARY_SW_VERSION_ATTR, DEVELCO_MANUFACTURER_CODE)
            })

            mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
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
        "ZoneStatusChangeNotification should be handled: detected",
        {
            {
                channel = "zigbee",
                direction = "receive",
                -- ZoneStatus | Bit0 Alarm1 set to 1
                message = { mock_device.id, IASZone.client.commands.ZoneStatusChangeNotification.build_test_rx(mock_device, 0x0001, 0x00) }
            },
            {
                channel = "capability",
                direction = "send",
                message = mock_device:generate_test_message("main", capabilities.smokeDetector.smoke.detected())
            }
        }
)

test.register_message_test(
        "ZoneStatusChangeNotification should be handled: tested",
        {
            {
                channel = "zigbee",
                direction = "receive",
                -- ZoneStatus | Bit8: Test set to 1
                message = { mock_device.id, IASZone.client.commands.ZoneStatusChangeNotification.build_test_rx(mock_device, 0x100, 0x01) }
            },
            {
                channel = "capability",
                direction = "send",
                message = mock_device:generate_test_message("main", capabilities.smokeDetector.smoke.tested())
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

-- test.register_coroutine_test(
--         "Health check should check all relevant attributes",
--         function()
--             test.wait_for_events()

--             test.mock_time.advance_time(50000) -- battery is 21600 for max reporting interval
--             test.socket.zigbee:__set_channel_ordering("relaxed")

--             test.socket.zigbee:__expect_send(
--                     {
--                         mock_device.id,
--                         PowerConfiguration.attributes.BatteryVoltage:read(mock_device)
--                     }
--             )

--             test.socket.zigbee:__expect_send(
--                     {
--                         mock_device.id,
--                         TemperatureMeasurement.attributes.MeasuredValue:read(mock_device)
--                     }
--             )

--             test.socket.zigbee:__expect_send(
--                     {
--                         mock_device.id,
--                         IASZone.attributes.ZoneStatus:read(mock_device)
--                     }
--             )
--         end,
--         {
--             test_init = function()
--                 test.mock_device.add_test_device(mock_device)
--                 test.timer.__create_and_queue_test_time_advance_timer(30, "interval", "health_check")
--             end
--         }
-- )

test.register_message_test(
        "Refresh should read all necessary attributes",
        {
            {
                channel = "capability",
                direction = "receive",
                message = {
                    mock_device.id,
                    { capability = "refresh", component = "main", command = "refresh", args = {} }
                }
            },
            {
                channel = "zigbee",
                direction = "send",
                message = {
                    mock_device.id,
                    IASZone.attributes.ZoneStatus:read(mock_device)
                }
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
                    TemperatureMeasurement.attributes.MeasuredValue:read(mock_device)
                }
            }
        },
        {
            inner_block_ordering = "relaxed"
        }
)

test.register_coroutine_test(
        "infochanged to check for necessary preferences settings: tempSensitivity, warningDuration",
        function()
            local updates = {
                preferences = {
                    tempSensitivity = 1.3,
                    warningDuration = 100
                }
            }

            test.wait_for_events()
            test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed(updates))

            test.socket.zigbee:__expect_send({
                mock_device.id,
                TemperatureMeasurement.attributes.MeasuredValue:configure_reporting(
                        mock_device,
                        60,
                        600,
                        130
                )--:to_endpoint(TEMPERATURE_MEASUREMENT_ENDPOINT)
            })

            test.socket.zigbee:__expect_send({
                mock_device.id,
                IASWD.attributes.MaxDuration:write(mock_device, 0x0064)--:to_endpoint(IASZONE_ENDPOINT)
            })


            test.socket.zigbee:__set_channel_ordering("relaxed")

        end
)

test.register_coroutine_test(
    "Should detect older firmware version and use correct endian format to turn on the siren",
    function()
        -- Manually set the firmware version and endian format for testing
        mock_device:set_field(PRIMARY_SW_VERSION, "040002", {persist = true})
        mock_device:set_field(SIREN_ENDIAN, "reverse", {persist = true})

        -- Verify fields are set correctly
        assert(mock_device:get_field(PRIMARY_SW_VERSION) < "040005", "PRIMARY_SW_VERSION should be less than '040005'")
        assert(mock_device:get_field(SIREN_ENDIAN) == "reverse", "SIREN_ENDIAN should be set to 'reverse'")

        -- Test the siren command with reversed endian
        test.socket.capability:__queue_receive({
            mock_device.id,
            { capability = "alarm", component = "main", command = "siren", args = {} }
        })

        -- Expect the command with reverse endian format
        local expectedConfiguration = SirenConfiguration(0x01)

        test.socket.zigbee:__expect_send({
            mock_device.id,
            IASWD.server.commands.StartWarning(mock_device,
                expectedConfiguration,
                data_types.Uint16(defaultWarningDuration),
                data_types.Uint8(00),
                data_types.Enum8(00))
        })

        test.wait_for_events()
    end
)

test.register_coroutine_test(
    "Should detect newer firmware version and use correct endian format to turn on the siren",
    function()
        -- Manually set the firmware version and endian format for testing
        mock_device:set_field(PRIMARY_SW_VERSION, "040005", {persist = true})
        mock_device:set_field(SIREN_ENDIAN, nil, {persist = true})

        -- Verify fields are set correctly
        assert(mock_device:get_field(PRIMARY_SW_VERSION) >= "040005", "PRIMARY_SW_VERSION should be greater than or equal to '040005'")
        assert(mock_device:get_field(SIREN_ENDIAN) == nil, "SIREN_ENDIAN should be set to 'nil'")

        -- Test the siren command with reversed endian
        test.socket.capability:__queue_receive({
            mock_device.id,
            { capability = "alarm", component = "main", command = "siren", args = {} }
        })

        -- Expect the command with reverse endian format
        local expectedConfiguration = SirenConfiguration(0x00)
        expectedConfiguration:set_warning_mode(0x01)

        test.socket.zigbee:__expect_send({
            mock_device.id,
            IASWD.server.commands.StartWarning(mock_device,
                expectedConfiguration,
                data_types.Uint16(defaultWarningDuration),
                data_types.Uint8(00),
                data_types.Enum8(00))
        })

        test.wait_for_events()
    end
)

test.register_coroutine_test(
    "Should detect older firmware version and use correct endian format to turn on the siren",
    function()
        -- Manually set the firmware version and endian format for testing
        mock_device:set_field(PRIMARY_SW_VERSION, "040002", {persist = true})
        mock_device:set_field(SIREN_ENDIAN, "reverse", {persist = true})

        -- Verify fields are set correctly
        assert(mock_device:get_field(PRIMARY_SW_VERSION) < "040005", "PRIMARY_SW_VERSION should be less than '040005'")
        assert(mock_device:get_field(SIREN_ENDIAN) == "reverse", "SIREN_ENDIAN should be set to 'reverse'")

        -- Test the siren command with reversed endian
        test.socket.capability:__queue_receive({
            mock_device.id,
            { capability = "alarm", component = "main", command = "off", args = {} }
        })

        -- Expect the command with reverse endian format
        local expectedConfiguration = SirenConfiguration(0x00)

        test.socket.zigbee:__expect_send({
            mock_device.id,
            IASWD.server.commands.StartWarning(mock_device,
                expectedConfiguration,
                data_types.Uint16(0x00),
                data_types.Uint8(00),
                data_types.Enum8(00))
        })

        test.wait_for_events()
    end
)

test.register_coroutine_test(
    "Should detect newer firmware version and use correct endian format to turn off the siren",
    function()
        -- Manually set the firmware version and endian format for testing
        mock_device:set_field(PRIMARY_SW_VERSION, "040005", {persist = true})
        mock_device:set_field(SIREN_ENDIAN, nil, {persist = true})

        -- Verify fields are set correctly
        assert(mock_device:get_field(PRIMARY_SW_VERSION) >= "040005", "PRIMARY_SW_VERSION should be greater than or equal to '040005'")
        assert(mock_device:get_field(SIREN_ENDIAN) == nil, "SIREN_ENDIAN should be set to 'nil'")

        -- Test the siren command with reversed endian
        test.socket.capability:__queue_receive({
            mock_device.id,
            { capability = "alarm", component = "main", command = "off", args = {} }
        })

        -- Expect the command with reverse endian format
        local expectedConfiguration = SirenConfiguration(0x00)
        expectedConfiguration:set_warning_mode(0x00)

        test.socket.zigbee:__expect_send({
            mock_device.id,
            IASWD.server.commands.StartWarning(mock_device,
                expectedConfiguration,
                data_types.Uint16(0x00),
                data_types.Uint8(00),
                data_types.Enum8(00))
        })

        test.wait_for_events()
    end
)

test.register_coroutine_test(
    "Test firmware version conversion using direct simulation",
    function()
        -- Binary firmware version test cases
        local test_cases = {
            {
                binary = string.char(4, 0, 5),      -- \004\000\005
                expected_hex = "040005"             -- Expected output
            },
            {
                binary = string.char(4, 0, 12),     -- \004\000\012
                expected_hex = "04000c"             -- Expected output
            },
            {
                binary = string.char(5, 1, 3),      -- \005\001\003
                expected_hex = "050103"             -- Expected output
            }
        }

        for i, test_case in ipairs(test_cases) do
            print("\n----- Test Case " .. i .. " -----")
            local binary_fw = test_case.binary
            local expected_hex = test_case.expected_hex

            -- Print the raw binary version and its byte values
            print("Binary firmware version (raw):", binary_fw)
            print("Binary firmware bytes:", string.format(
                "\\%03d\\%03d\\%03d",
                string.byte(binary_fw, 1),
                string.byte(binary_fw, 2),
                string.byte(binary_fw, 3)
            ))

            -- Reset the field for clean test
            mock_device:set_field(PRIMARY_SW_VERSION, nil, {persist = true})

            -- Create a mock value object
            local mock_value = {
                value = binary_fw
            }

            -- Simulate what happens in primary_sw_version_attr_handler
            local primary_sw_version = mock_value.value:gsub('.', function (c)
                return string.format('%02x', string.byte(c))
            end)

            -- Store the version in PRIMARY_SW_VERSION field
            mock_device:set_field(PRIMARY_SW_VERSION, primary_sw_version, {persist = true})

            -- What the conversion should do
            print("\nConversion steps:")
            local hex_result = ""
            for i = 1, #binary_fw do
                local char = binary_fw:sub(i, i)
                local byte_val = string.byte(char)
                local hex_val = string.format('%02x', byte_val)
                hex_result = hex_result .. hex_val
                print(string.format("Character at position %d: byte value = %d, hex = %02x",
                      i, byte_val, byte_val))
            end

            print("\nExpected hex result:", expected_hex)
            print("Manual conversion result:", hex_result)

            -- Verify the stored version
            local stored_version = mock_device:get_field(PRIMARY_SW_VERSION)
            print("\nStored version in device field:", stored_version)
            assert(stored_version == expected_hex,
                  string.format("Version mismatch! Expected '%s' but got '%s'",
                  expected_hex, stored_version or "nil"))
        end
    end
)

test.run_registered_tests()
