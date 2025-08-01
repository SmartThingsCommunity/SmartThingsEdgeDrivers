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

local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local constants = require "st.zigbee.constants"

local OnOff = clusters.OnOff
local ElectricalMeasurement = clusters.ElectricalMeasurement
local SimpleMetering = clusters.SimpleMetering
local Alarms = clusters.Alarms

local AlarmCmd = require "st.zigbee.generated.zcl_clusters.Alarms.client.commands.Alarm"
local t_utils = require "integration_test.utils"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local test = require "integration_test"
local base64 = require "base64"

local POWER_FAILURE_ALARM_CODE = 0x03


local mock_device = test.mock_device.build_test_zigbee_device({
    profile = t_utils.get_profile_definition("frient-switch-power-energy-voltage.yml"),
    zigbee_endpoints = {
      [0x02] = {
        id = 0x02,
        manufacturer = "frient A/S",
        model = "SPLZB-132",
        server_clusters = { SimpleMetering.ID, ElectricalMeasurement.ID, Alarms.ID, OnOff.ID },
        client_clusters = {}
      },
    }}
)

zigbee_test_utils.prepare_zigbee_env_info()

local function test_init()
    test.mock_device.add_test_device(mock_device)
    zigbee_test_utils.init_noop_health_check_timer()
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.powerSource.powerSource.mains()))
end

test.set_test_init_function(test_init)

test.register_message_test(
        "Voltage divisor, multiplier, and summation should be handled ",
        {
            {
                channel = "zigbee",
                direction = "receive",
                message = {
                    mock_device.id,
                    ElectricalMeasurement.attributes.ACVoltageMultiplier:build_test_read_attr_response(mock_device, 10)
                }
            },
            {
                channel = "zigbee",
                direction = "receive",
                message = {
                    mock_device.id,
                    ElectricalMeasurement.attributes.ACVoltageDivisor:build_test_read_attr_response(mock_device, 1)
                }
            },
            {
                channel = "zigbee",
                direction = "receive",
                message = {
                    mock_device.id,
                    ElectricalMeasurement.attributes.RMSVoltage:build_test_attr_report(mock_device, 20)
                }
            },
            {
                channel = "capability",
                direction = "send",
                message = mock_device:generate_test_message("main", capabilities.voltageMeasurement.voltage({ value = 200.0, unit = "V" }))
            },
            {
                channel = "capability",
                direction = "send",
                message = mock_device:generate_test_message("main", capabilities.powerSource.powerSource.mains())
            }
        }
)

test.register_message_test("Current divisor, multiplier, summation should be handled",
        {
            {
                channel = "zigbee",
                direction = "receive",
                message = {
                    mock_device.id,
                    ElectricalMeasurement.attributes.ACCurrentMultiplier:build_test_read_attr_response(mock_device, 10)
                }
            },
            {
                channel = "zigbee",
                direction = "receive",
                message = {
                    mock_device.id,
                    ElectricalMeasurement.attributes.ACCurrentDivisor:build_test_read_attr_response(mock_device, 1)
                }
            },
            {
                channel = "zigbee",
                direction = "receive",
                message = {
                    mock_device.id,
                    ElectricalMeasurement.attributes.RMSCurrent:build_test_attr_report(mock_device, 20)
                }
            },
            {
                channel = "capability",
                direction = "send",
                message = mock_device:generate_test_message("main", capabilities.currentMeasurement.current({ value = 200.0, unit = "A" }))
            },
        })

test.register_coroutine_test("Refresh command should read all necessary attributes", function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.capability:__queue_receive({
        mock_device.id,
        {
            capability = "refresh",
            component = "main",
            command = "refresh",
            args = {}
        }
    })
    test.socket.zigbee:__expect_send(
            {mock_device.id, ElectricalMeasurement.attributes.ACPowerMultiplier:read(mock_device)}
    )
    test.socket.zigbee:__expect_send(
            {mock_device.id, ElectricalMeasurement.attributes.ACPowerDivisor:read(mock_device)}
    )
    test.socket.zigbee:__expect_send(
            {mock_device.id, ElectricalMeasurement.attributes.ActivePower:read(mock_device) }
    )
    test.socket.zigbee:__expect_send(
            {mock_device.id, SimpleMetering.attributes.CurrentSummationDelivered:read(mock_device) }
    )
    test.socket.zigbee:__expect_send(
            {mock_device.id, SimpleMetering.attributes.InstantaneousDemand:read(mock_device) }
    )
    test.socket.zigbee:__expect_send(
            {mock_device.id, OnOff.attributes.OnOff:read(mock_device) }
    )
end)

test.register_message_test(
  "Handle switch ON report",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, OnOff.attributes.OnOff:build_test_attr_report(mock_device, true) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switch.switch.on())
    },
    {
        channel = "devices",
        direction = "send",
        message = {
            "register_native_capability_attr_handler",
            { device_uuid = mock_device.id, capability_id = "switch", capability_attr_id = "switch" }
        }
    },
  }
)

test.register_message_test(
  "Handle switch OFF report",
  {
      {
          channel = "zigbee",
          direction = "receive",
          message = { mock_device.id, OnOff.attributes.OnOff:build_test_attr_report(mock_device, false)}
      },
      {
          channel = "capability",
          direction = "send",
          message = mock_device:generate_test_message("main", capabilities.switch.switch.off())
      },
      {
          channel = "devices",
          direction = "send",
          message = {
              "register_native_capability_attr_handler",
              { device_uuid = mock_device.id, capability_id = "switch", capability_attr_id = "switch" }
          }
      },
  }
)

test.register_message_test(
    "ActivePower Report should be handled. Sensor value is in W, capability attribute value is in hectowatts",
    {
        {
            channel = "zigbee",
            direction = "receive",
            message = { mock_device.id, ElectricalMeasurement.attributes.ACPowerDivisor:build_test_attr_report(mock_device, 0x0A) }
        },
        {
            channel = "zigbee",
            direction = "receive",
            message = { mock_device.id, ElectricalMeasurement.attributes.ActivePower:build_test_attr_report(mock_device, 27) }
        },
        {
            channel = "capability",
            direction = "send",
            message = mock_device:generate_test_message("main", capabilities.powerMeter.power({ value = 2.7, unit = "W" }))
        },
        {
        channel = "devices",
        direction = "send",
        message = {
            "register_native_capability_attr_handler",
            { device_uuid = mock_device.id, capability_id = "powerMeter", capability_attr_id = "power" }
        }
        }
    }
)

test.register_message_test(
    "CurrentSummationDelivered Report should be handled.",
    {
        {
            channel = "zigbee",
            direction = "receive",
            message = { mock_device.id, SimpleMetering.attributes.Divisor:build_test_attr_report(mock_device, 0x3E8) }
        },
        {
            channel = "zigbee",
            direction = "receive",
            message = { mock_device.id, SimpleMetering.attributes.CurrentSummationDelivered:build_test_attr_report(mock_device, 27) }
        },
        {
            channel = "capability",
            direction = "send",
            message = mock_device:generate_test_message("main", capabilities.energyMeter.energy({ value = 0.027, unit = "kWh" }))

        }
    }
)

test.register_coroutine_test(
        "device_init should set fields and emmit powerSource if supported",
        function()
            test.socket.device_lifecycle:__queue_receive({ mock_device.id, "init" })
            assert(mock_device:get_field(constants.SIMPLE_METERING_DIVISOR_KEY) == 1000)
            assert(mock_device:get_field(constants.ELECTRICAL_MEASUREMENT_DIVISOR_KEY) == 1000)
            test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.powerSource.powerSource.mains()))
        end
)

test.register_coroutine_test("doConfigure should send bind request, read attributes and configure reporting", function()
    test.socket.environment_update:__queue_receive({ "zigbee", { hub_zigbee_id = base64.encode(zigbee_test_utils.mock_hub_eui) } })
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
    test.socket.zigbee:__expect_send({mock_device.id, zigbee_test_utils.build_bind_request(
            mock_device,
            zigbee_test_utils.mock_hub_eui,
            ElectricalMeasurement.ID,
            0x02
    )})
    test.socket.zigbee:__expect_send({mock_device.id, ElectricalMeasurement.attributes.ACPowerMultiplier:configure_reporting(mock_device, 0x0001, 0xA8C0,0x0001)})
    test.socket.zigbee:__expect_send({mock_device.id, ElectricalMeasurement.attributes.ACPowerDivisor:configure_reporting(mock_device, 0x0001, 0xA8C0,0x0001)})
    test.socket.zigbee:__expect_send({mock_device.id, ElectricalMeasurement.attributes.RMSVoltage:configure_reporting(mock_device, 0x0005, 0x0E10,0x0001)})
    test.socket.zigbee:__expect_send({mock_device.id, ElectricalMeasurement.attributes.RMSCurrent:configure_reporting(mock_device, 0x0005, 0x0E10,0x0001)})
    test.socket.zigbee:__expect_send({mock_device.id, ElectricalMeasurement.attributes.ActivePower:configure_reporting(mock_device, 0x0005, 0x0E10,0x0001)})

    test.socket.zigbee:__expect_send({ mock_device.id, ElectricalMeasurement.attributes.ACVoltageMultiplier:read(mock_device )})
    test.socket.zigbee:__expect_send({ mock_device.id, ElectricalMeasurement.attributes.ACVoltageDivisor:read(mock_device )})
    test.socket.zigbee:__expect_send({ mock_device.id, ElectricalMeasurement.attributes.RMSVoltage:read(mock_device )})

    test.socket.zigbee:__expect_send({ mock_device.id, ElectricalMeasurement.attributes.ACCurrentMultiplier:read(mock_device )})
    test.socket.zigbee:__expect_send({ mock_device.id, ElectricalMeasurement.attributes.ACCurrentDivisor:read(mock_device )})
    test.socket.zigbee:__expect_send({ mock_device.id, ElectricalMeasurement.attributes.RMSCurrent:read(mock_device )})

    test.socket.zigbee:__expect_send({ mock_device.id, ElectricalMeasurement.attributes.ACPowerMultiplier:read(mock_device )})
    test.socket.zigbee:__expect_send({ mock_device.id, ElectricalMeasurement.attributes.ACPowerDivisor:read(mock_device )})
    test.socket.zigbee:__expect_send({ mock_device.id, ElectricalMeasurement.attributes.ActivePower:read(mock_device )})

    test.socket.zigbee:__expect_send({mock_device.id, zigbee_test_utils.build_bind_request(
            mock_device,
            zigbee_test_utils.mock_hub_eui,
            SimpleMetering.ID,
            0x02
    )})
    test.socket.zigbee:__expect_send({mock_device.id, SimpleMetering.attributes.CurrentSummationDelivered:configure_reporting(mock_device, 0x0005, 0x0E10,1)})
    test.socket.zigbee:__expect_send({mock_device.id, SimpleMetering.attributes.InstantaneousDemand:configure_reporting(mock_device, 0x0005, 0x0E10,1)})
    test.socket.zigbee:__expect_send({ mock_device.id, SimpleMetering.attributes.CurrentSummationDelivered:read(mock_device )})
    test.socket.zigbee:__expect_send({ mock_device.id, SimpleMetering.attributes.InstantaneousDemand:read(mock_device )})

    test.socket.zigbee:__expect_send({mock_device.id, zigbee_test_utils.build_bind_request(
            mock_device,
            zigbee_test_utils.mock_hub_eui,
            OnOff.ID,
            0x02
    )})
    test.socket.zigbee:__expect_send({mock_device.id, OnOff.attributes.OnOff:configure_reporting(mock_device, 0x0000, 0x012C)})
    test.socket.zigbee:__expect_send({ mock_device.id, OnOff.attributes.OnOff:read(mock_device )})

    test.socket.zigbee:__expect_send({mock_device.id , zigbee_test_utils.build_bind_request(
            mock_device,
            zigbee_test_utils.mock_hub_eui,
            Alarms.ID,
            0x02
    )})
    test.socket.zigbee:__expect_send({mock_device.id, Alarms.attributes.AlarmCount:configure_reporting(mock_device, 1, 0x0E10, 1)})
    test.socket.zigbee:__expect_send({mock_device.id, Alarms.attributes.AlarmCount:read(mock_device)})

    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
end)

test.register_coroutine_test(
        "Alarm report should be handled",
        function()
            test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")

            test.socket.zigbee:__queue_receive({ mock_device.id, AlarmCmd.build_test_rx(mock_device,POWER_FAILURE_ALARM_CODE,SimpleMetering.ID)})

            test.mock_time.advance_time(2)

            test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.powerSource.powerSource.unknown()))
        end
)

test.run_registered_tests()
