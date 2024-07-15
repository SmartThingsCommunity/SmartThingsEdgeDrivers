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
local OnOff = clusters.OnOff
local Level = clusters.Level
local TemperatureMeasurement = clusters.TemperatureMeasurement
local capabilities = require "st.capabilities"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local base64 = require "st.base64"
local data_types = require "st.zigbee.data_types"
local t_utils = require "integration_test.utils"

local KEEN_PRESSURE_ATTRIBUTE = 0x0020
local KEEN_MFG_CODE = 0x115B

local mock_device = test.mock_device.build_test_zigbee_device(
    { profile = t_utils.get_profile_definition("vent-profile-1.yml") }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device)
  zigbee_test_utils.init_noop_health_check_timer()
end

test.set_test_init_function(test_init)

test.register_message_test(
        "Reported level should be handled",
        {
          {
            channel = "zigbee",
            direction = "receive",
            message = {
              mock_device.id,
              Level.attributes.CurrentLevel:build_test_attr_report(mock_device,
                      math.floor(83 / 100 * 254))
            }
          },
          {
            channel = "capability",
            direction = "send",
            message = mock_device:generate_test_message("main", capabilities.switchLevel.level(83))
          },
          {
            channel = "capability",
            direction = "send",
            message = mock_device:generate_test_message("main", capabilities.switch.switch.on())
          }
        }
)

test.register_message_test(
        "Reported on off status should be handled: on",
        {
          {
            channel = "zigbee",
            direction = "receive",
            message = { mock_device.id, OnOff.attributes.OnOff:build_test_attr_report(mock_device,
                    true) }
          },
          {
            channel = "capability",
            direction = "send",
            message = mock_device:generate_test_message("main", capabilities.switch.switch.on())
          }
        }
)

test.register_message_test(
        "Reported on off status should be handled: off",
        {
          {
            channel = "zigbee",
            direction = "receive",
            message = { mock_device.id, OnOff.attributes.OnOff:build_test_attr_report(mock_device,
                    false) }
          },
          {
            channel = "capability",
            direction = "send",
            message = mock_device:generate_test_message("main", capabilities.switch.switch.off())
          }
        }
)

test.register_coroutine_test(
        "Capability command setLevel should be handled",
        function ()
          test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
          test.socket.capability:__queue_receive({mock_device.id, { capability = "switchLevel", component = "main", command = "setLevel", args = { 57 } }})
          test.socket.zigbee:__expect_send({mock_device.id, Level.commands.MoveToLevelWithOnOff(mock_device,
                  math.floor(57 * 0xFE / 100),
                  0xFFFF)})
          test.wait_for_events()

          test.mock_time.advance_time(1)
          test.socket.zigbee:__expect_send({mock_device.id, Level.attributes.CurrentLevel:read(mock_device)})
        end
)

test.register_message_test(
        "Temperature report should be handled (C)",
        {
          {
            channel = "zigbee",
            direction = "receive",
            message = { mock_device.id, TemperatureMeasurement.attributes.MeasuredValue:build_test_attr_report(mock_device, 2500) }
          },
          {
            channel = "capability",
            direction = "send",
            message = mock_device:generate_test_message("main", capabilities.temperatureMeasurement.temperature({ value = 25.0, unit = "C"}))
          }
        }
)

test.register_message_test(
        "Minimum & Maximum Temperature report should be handled (C)",
        {
          {
            channel = "zigbee",
            direction = "receive",
            message = { mock_device.id, TemperatureMeasurement.attributes.MinMeasuredValue:build_test_attr_report(mock_device, 2000) }
          },
          {
            channel = "zigbee",
            direction = "receive",
            message = { mock_device.id, TemperatureMeasurement.attributes.MaxMeasuredValue:build_test_attr_report(mock_device, 3000) }
          },
          {
            channel = "capability",
            direction = "send",
            message = mock_device:generate_test_message("main", capabilities.temperatureMeasurement.temperatureRange({ value = { minimum = 20.00, maximum = 30.00 }, unit = "C" }))
          }
        }
)

test.register_message_test(
        "added lifecycle event should get initial state for device",
        {
          {
            channel = "environment_update",
            direction = "receive",
            message = { "zigbee", { hub_zigbee_id = base64.encode(zigbee_test_utils.mock_hub_eui) } },
          },
          {
            channel = "device_lifecycle",
            direction = "receive",
            message = {
              mock_device.id,
              "added"
            }
          },
          {
            channel = "zigbee",
            direction = "send",
            message = {
              mock_device.id,
              OnOff.attributes.OnOff:read(mock_device)
            }
          },
          {
            channel = "zigbee",
            direction = "send",
            message = {
              mock_device.id,
              clusters.TemperatureMeasurement.attributes.MeasuredValue:read(mock_device)
            }
          },
          {
            channel = "zigbee",
            direction = "send",
            message = {
              mock_device.id,
              clusters.TemperatureMeasurement.attributes.MinMeasuredValue:read(mock_device)
            }
          },
          {
            channel = "zigbee",
            direction = "send",
            message = {
              mock_device.id,
              clusters.TemperatureMeasurement.attributes.MaxMeasuredValue:read(mock_device)
            }
          },
          {
            channel = "zigbee",
            direction = "send",
            message = {
              mock_device.id,
              clusters.PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device)
            }
          },
          {
            channel = "zigbee",
            direction = "send",
            message = {
              mock_device.id,
              Level.attributes.CurrentLevel:read(mock_device)
            }
          },
          {
            channel = "zigbee",
            direction = "send",
            message = {
              mock_device.id,
              zigbee_test_utils.build_attribute_read(mock_device, clusters.PressureMeasurement.ID, {KEEN_PRESSURE_ATTRIBUTE}, KEEN_MFG_CODE)
            }
          }
        },
        {
          inner_block_ordering = "relaxed"
        }
)

test.register_coroutine_test(
    "doConfigure lifecycle event should configure device",
    function ()
      test.socket.device_lifecycle:__queue_receive({
                                                     mock_device.id,
                                                     "doConfigure"
                                                   })
      test.socket.zigbee:__set_channel_ordering("relaxed")
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         zigbee_test_utils.build_bind_request(mock_device,
                                                                              zigbee_test_utils.mock_hub_eui,
                                                                              OnOff.ID)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         OnOff.attributes.OnOff:configure_reporting(mock_device, 0, 300)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         zigbee_test_utils.build_bind_request(mock_device,
                                                                              zigbee_test_utils.mock_hub_eui,
                                                                              Level.ID)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         clusters.TemperatureMeasurement.attributes.MeasuredValue:configure_reporting(mock_device, 30, 300, 1)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         zigbee_test_utils.build_bind_request(mock_device,
                                                                              zigbee_test_utils.mock_hub_eui,
                                                                              clusters.PressureMeasurement.ID)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         zigbee_test_utils.build_bind_request(mock_device,
                                                                              zigbee_test_utils.mock_hub_eui,
                                                                              clusters.TemperatureMeasurement.ID)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         zigbee_test_utils.build_bind_request(mock_device,
                                                                              zigbee_test_utils.mock_hub_eui,
                                                                              clusters.PowerConfiguration.ID)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         clusters.PowerConfiguration.attributes.BatteryPercentageRemaining:configure_reporting(mock_device, 60, 21600, 1)
                                       })

      mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    end
)


test.register_coroutine_test(
        "sending on to an off device should return the device to its previous level",
        function()
          test.socket.zigbee:__queue_receive({mock_device.id, Level.attributes.CurrentLevel:build_test_attr_report(
                  mock_device, math.floor(83 / 100 * 254)
          )})
          test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.switchLevel.level(83)))
          test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.switch.switch.on()))
          test.wait_for_events()
          test.socket.zigbee:__queue_receive({mock_device.id, OnOff.attributes.OnOff:build_test_attr_report(mock_device, false)})
          test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.switch.switch.off()))
          test.wait_for_events()
          test.socket.capability:__queue_receive({mock_device.id, { capability = "switch", component = "main", command = "on", args = {}}})
          test.socket.zigbee:__expect_send({mock_device.id, Level.commands.MoveToLevelWithOnOff(mock_device, math.floor(83 / 100 * 254), 0xFFFF)})
        end
)

test.register_coroutine_test(
        "Battery reports should be handled in this device's specific (incorrect) way",
        function()
          test.socket.zigbee:__queue_receive({mock_device.id, clusters.PowerConfiguration.attributes.BatteryPercentageRemaining:build_test_attr_report(
                  mock_device, 50
          )})
          test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.battery.battery(50)))
        end
)

test.register_coroutine_test(
        "Mfr-specific humidity reports should be handled",
        function()
          test.socket.zigbee:__queue_receive({mock_device.id, zigbee_test_utils.build_attribute_report(mock_device, clusters.PressureMeasurement.ID,
                  {{ KEEN_PRESSURE_ATTRIBUTE, data_types.Uint16.ID, 10000}}, KEEN_MFG_CODE)})
          test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.atmosphericPressureMeasurement.atmosphericPressure({value = 1, unit = "kPa"})))
        end
)

test.run_registered_tests()
