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
local ColorControl = clusters.ColorControl
local ElectricalMeasurement = clusters.ElectricalMeasurement
local SimpleMetering = clusters.SimpleMetering
local capabilities = require "st.capabilities"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"

local zigbee_bulb_all_caps = {
  components = {
    main = {
      capabilities = {
        [capabilities.switch.ID] = { id = capabilities.switch.ID },
        [capabilities.switchLevel.ID] = { id = capabilities.switchLevel.ID },
        [capabilities.colorControl.ID] = { id = capabilities.colorControl.ID },
        [capabilities.colorTemperature.ID] = { id = capabilities.colorTemperature.ID },
        [capabilities.powerMeter.ID] = { id = capabilities.powerMeter.ID },
        [capabilities.energyMeter.ID] = { id = capabilities.energyMeter.ID },
        [capabilities.refresh.ID] = { id = capabilities.refresh.ID },
      },
      id = "main"
    }
  }
}
local mock_device = test.mock_device.build_test_zigbee_device({ profile = zigbee_bulb_all_caps })

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

test.register_message_test(
    "Capability command setLevel should be handled",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_device.id, { capability = "switchLevel", component = "main", command = "setLevel", args = { 57, 0 } } }
      },
      {
        channel = "devices",
        direction = "send",
        message = {
          "register_native_capability_cmd_handler",
          { device_uuid = mock_device.id, capability_id = "switchLevel", capability_cmd_id = "setLevel" }
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_device.id, Level.server.commands.MoveToLevelWithOnOff(mock_device,
                                                                               math.floor(57 * 0xFE / 100),
                                                                               0) }
      }
    }
)

test.register_message_test(
    "ActivePower Report should be handled. Sensor value is in W, capability attribute value is in W",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, ElectricalMeasurement.attributes.ActivePower:build_test_attr_report(mock_device,
                                                                                                        27) },
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.powerMeter.power({ value = 27.0, unit = "W" }))
      }
    }
)

test.register_message_test(
    "InstaneousDemand Report should be handled. Sensor value is in kW, capability attribute value is in W",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, SimpleMetering.attributes.InstantaneousDemand:build_test_attr_report(mock_device,
                                                                                                         27) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.powerMeter.power({ value = 27000.0, unit = "W" }))
      }
    }
)

test.register_message_test(
    "Color Control Hue should generate event",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, ColorControl.attributes.CurrentHue:build_test_read_attr_response(mock_device,
                                                                                                     0) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.colorControl.hue(0))
      }
    }
)

test.register_message_test(
    "Color control saturation should generate event",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, ColorControl.attributes.CurrentSaturation:build_test_read_attr_response(mock_device,
                                                                                                            127) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.colorControl.saturation(50))
      }
    }
)

test.register_coroutine_test(
    "lifecycle configure event should configure device",
    function ()
      test.socket.zigbee:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle:__queue_receive({mock_device.id, "doConfigure"})
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         OnOff.attributes.OnOff:read(mock_device)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         Level.attributes.CurrentLevel:read(mock_device)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         ColorControl.attributes.ColorTemperatureMireds:read(mock_device)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         ColorControl.attributes.CurrentHue:read(mock_device)
      })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         ColorControl.attributes.CurrentSaturation:read(mock_device)
      })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         zigbee_test_utils.build_bind_request(mock_device,
                                                                              zigbee_test_utils.mock_hub_eui,
                                                                              OnOff.ID)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         SimpleMetering.attributes.InstantaneousDemand:read(mock_device)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         SimpleMetering.attributes.CurrentSummationDelivered:read(mock_device)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         ElectricalMeasurement.attributes.ActivePower:read(mock_device)
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
                                         Level.attributes.CurrentLevel:configure_reporting(mock_device, 1, 3600, 1)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         zigbee_test_utils.build_bind_request(mock_device,
                                                                              zigbee_test_utils.mock_hub_eui,
                                                                              ColorControl.ID)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         ColorControl.attributes.ColorTemperatureMireds:configure_reporting(mock_device, 1, 3600, 0x0010)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         ColorControl.attributes.CurrentHue:configure_reporting(mock_device, 1, 3600, 0x0010)
      })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         ColorControl.attributes.CurrentSaturation:configure_reporting(mock_device, 1, 3600, 0x0010)
      })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         zigbee_test_utils.build_bind_request(mock_device,
                                                                              zigbee_test_utils.mock_hub_eui,
                                                                              SimpleMetering.ID)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         SimpleMetering.attributes.InstantaneousDemand:configure_reporting(mock_device, 1, 3600, 5)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         SimpleMetering.attributes.CurrentSummationDelivered:configure_reporting(mock_device, 5, 3600, 1)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         zigbee_test_utils.build_bind_request(mock_device,
                                                                              zigbee_test_utils.mock_hub_eui,
                                                                              ElectricalMeasurement.ID)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         ElectricalMeasurement.attributes.ActivePower:configure_reporting(mock_device, 1, 3600, 5)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         ElectricalMeasurement.attributes.ACPowerDivisor:read(mock_device)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         ElectricalMeasurement.attributes.ACPowerMultiplier:read(mock_device)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         SimpleMetering.attributes.Multiplier:read(mock_device)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         SimpleMetering.attributes.Divisor:read(mock_device)
                                       })

      mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    end
)

test.register_coroutine_test(
    "health check coroutine",
    function()
      test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
      test.wait_for_events()

      test.mock_time.advance_time(10000)
      test.socket.zigbee:__set_channel_ordering("relaxed")
      test.socket.zigbee:__expect_send({ mock_device.id, OnOff.attributes.OnOff:read(mock_device) })
      test.socket.zigbee:__expect_send({ mock_device.id, Level.attributes.CurrentLevel:read(mock_device) })
      test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.ColorTemperatureMireds:read(mock_device) })
      test.socket.zigbee:__expect_send({ mock_device.id, ElectricalMeasurement.attributes.ActivePower:read(mock_device) })
      test.socket.zigbee:__expect_send({ mock_device.id, SimpleMetering.attributes.InstantaneousDemand:read(mock_device) })
      test.socket.zigbee:__expect_send({ mock_device.id, SimpleMetering.attributes.CurrentSummationDelivered:read(mock_device) })
      test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.CurrentHue:read(mock_device) })
      test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.CurrentSaturation:read(mock_device) })

    end,
    {
      test_init = function()
        test.mock_device.add_test_device(mock_device)
        test.timer.__create_and_queue_test_time_advance_timer(30, "interval", "health_check")
      end
    }
)

test.register_coroutine_test(
    "set color command test",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
      test.socket.capability:__queue_receive({mock_device.id, { capability = "colorControl", component = "main", command = "setColor", args = { { hue = 50, saturation = 50 } } } })
      mock_device:expect_native_cmd_handler_registration("colorControl", "setColor")
      test.socket.zigbee:__expect_send(
          {
            mock_device.id,
            OnOff.server.commands.On(mock_device)
          }
      )
      local hue = math.floor((50 * 0xFE) / 100.0 + 0.5)
      local sat = math.floor((50 * 0xFE) / 100.0 + 0.5)
      test.socket.zigbee:__expect_send(
          {
            mock_device.id,
            ColorControl.server.commands.MoveToHueAndSaturation(
                mock_device,
                hue,
                sat,
                0x0000
            )
          }
      )

      test.wait_for_events()

      test.mock_time.advance_time(2)
      test.socket.zigbee:__expect_send({mock_device.id, ColorControl.attributes.CurrentHue:read(mock_device)})
      test.socket.zigbee:__expect_send({mock_device.id, ColorControl.attributes.CurrentSaturation:read(mock_device)})
    end
)

-- This tests that our code responsible for handling conversion errors from Kelvin<->Mireds works as expected
test.register_coroutine_test(
  "set color temperature command test",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.capability:__queue_receive({mock_device.id, { capability = "colorTemperature", component = "main", command = "setColorTemperature", args = {1800}}})
    mock_device:expect_native_cmd_handler_registration("colorTemperature", "setColorTemperature")
    test.socket.zigbee:__expect_send({mock_device.id, ColorControl.server.commands.MoveToColorTemperature(mock_device, 556, 0x0000)})
    test.socket.zigbee:__expect_send({mock_device.id, OnOff.server.commands.On(mock_device)})
    test.wait_for_events()
    test.socket.zigbee:__queue_receive({mock_device.id, ColorControl.attributes.ColorTemperatureMireds:build_test_attr_report(mock_device, 556)})
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.colorTemperature.colorTemperature(1800)))
  end
)

test.register_coroutine_test(
  "energy meter reset command test",
  function()
    test.socket.capability:__queue_receive({mock_device.id, { capability = "energyMeter", component = "main", command = "resetEnergyMeter", args = {}}})
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.energyMeter.energy({ value = 0.0, unit = "kWh" })))
    test.wait_for_events()
    test.socket.zigbee:__queue_receive({mock_device.id, SimpleMetering.attributes.CurrentSummationDelivered:build_test_attr_report(mock_device, 15)})
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.energyMeter.energy({ value = 15.0, unit = "kWh" })))
    test.wait_for_events()
    test.socket.capability:__queue_receive({mock_device.id, { capability = "energyMeter", component = "main", command = "resetEnergyMeter", args = {}}})
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.energyMeter.energy({ value = 0.0, unit = "kWh" })))
    test.wait_for_events()
    test.socket.zigbee:__queue_receive({mock_device.id, SimpleMetering.attributes.CurrentSummationDelivered:build_test_attr_report(mock_device, 15)})
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.energyMeter.energy({ value = 0.0, unit = "kWh" })))
    test.wait_for_events()
    --- offset should be reset by a reading under the previous offset
    test.socket.zigbee:__queue_receive({mock_device.id, SimpleMetering.attributes.CurrentSummationDelivered:build_test_attr_report(mock_device, 14)})
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.energyMeter.energy({ value = 14.0, unit = "kWh" })))
  end
)


test.run_registered_tests()
