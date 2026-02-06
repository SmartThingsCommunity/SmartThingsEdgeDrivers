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
local capabilities = require "st.capabilities"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils = require "integration_test.utils"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"

local CurrentSummationReceived = 0x0001
local LAST_REPORT_TIME = "LAST_REPORT_TIME"

local zigbee_constants = require "st.zigbee.constants"
zigbee_constants.ELECTRICAL_MEASUREMENT_AC_VOLTAGE_MULTIPLIER_KEY = "_electrical_measurement_ac_voltage_multiplier"
zigbee_constants.ELECTRICAL_MEASUREMENT_AC_CURRENT_MULTIPLIER_KEY = "_electrical_measurement_ac_current_multiplier"
zigbee_constants.ELECTRICAL_MEASUREMENT_AC_VOLTAGE_DIVISOR_KEY = "_electrical_measurement_ac_voltage_divisor"
zigbee_constants.ELECTRICAL_MEASUREMENT_AC_CURRENT_DIVISOR_KEY = "_electrical_measurement_ac_current_divisor"

local mock_device = test.mock_device.build_test_zigbee_device(
        {
            profile = t_utils.get_profile_definition("power-energy-current-voltage.yml"),
            zigbee_endpoints = {
                [1] = {
                    id = 1,
                    model = "EMIZB-151",
                    server_clusters = { ElectricalMeasurement.ID, SimpleMetering.ID }
                }
            }
        }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
    test.mock_device.add_test_device(mock_device)
end

test.set_test_init_function(test_init)

local function expected_refresh_commands()
    test.socket.zigbee:__expect_send({
        mock_device.id,
        cluster_base.read_attribute(
            mock_device,
            data_types.ClusterId(SimpleMetering.ID),
            CurrentSummationReceived
        )
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
        ElectricalMeasurement.attributes.RMSCurrent:read(mock_device)
    })
    test.socket.zigbee:__expect_send({
        mock_device.id,
        ElectricalMeasurement.attributes.RMSCurrentPhB:read(mock_device)
    })
    test.socket.zigbee:__expect_send({
        mock_device.id,
        ElectricalMeasurement.attributes.RMSCurrentPhC:read(mock_device)
    })
    test.socket.zigbee:__expect_send({
        mock_device.id,
        ElectricalMeasurement.attributes.RMSVoltage:read(mock_device)
    })
    test.socket.zigbee:__expect_send({
        mock_device.id,
        ElectricalMeasurement.attributes.RMSVoltagePhB:read(mock_device)
    })
    test.socket.zigbee:__expect_send({
        mock_device.id,
        ElectricalMeasurement.attributes.RMSVoltagePhC:read(mock_device)
    })
    test.socket.zigbee:__expect_send({
        mock_device.id,
        ElectricalMeasurement.attributes.ActivePower:read(mock_device)
    })
    test.socket.zigbee:__expect_send({
        mock_device.id,
        ElectricalMeasurement.attributes.ActivePowerPhB:read(mock_device)
    })
    test.socket.zigbee:__expect_send({
        mock_device.id,
        ElectricalMeasurement.attributes.ActivePowerPhC:read(mock_device)
    })
end




test.register_coroutine_test(
        "Refresh should read all necessary attributes",
        function()
            test.socket.zigbee:__set_channel_ordering("relaxed")
            test.socket.capability:__queue_receive({ mock_device.id, { capability = "refresh", command = "refresh", args = {} } })

            expected_refresh_commands()
        end
)

test.register_coroutine_test(
        "ALl reports (for all phases) should be handled properly",
        function()
            test.socket.zigbee:__set_channel_ordering("relaxed")

            test.socket.zigbee:__queue_receive({ mock_device.id, SimpleMetering.attributes.Multiplier:build_test_attr_report(mock_device, 1) })
            test.socket.zigbee:__queue_receive({ mock_device.id, SimpleMetering.attributes.Divisor:build_test_attr_report(mock_device, 1000) })
            test.socket.zigbee:__queue_receive({ mock_device.id, ElectricalMeasurement.attributes.ACVoltageMultiplier:build_test_attr_report(mock_device, 1) })
            test.socket.zigbee:__queue_receive({ mock_device.id, ElectricalMeasurement.attributes.ACVoltageDivisor:build_test_attr_report(mock_device, 1000) })
            test.socket.zigbee:__queue_receive({ mock_device.id, ElectricalMeasurement.attributes.ACCurrentMultiplier:build_test_attr_report(mock_device, 1) })
            test.socket.zigbee:__queue_receive({ mock_device.id, ElectricalMeasurement.attributes.ACCurrentDivisor:build_test_attr_report(mock_device, 1000) })

            test.socket.zigbee:__queue_receive({ mock_device.id, SimpleMetering.attributes.CurrentSummationDelivered:build_test_attr_report(mock_device, 30) })
            test.socket.capability:__expect_send(
                mock_device:generate_test_message("main", capabilities.energyMeter.energy({ value = 30.0, unit = "Wh"}))
            )

            test.socket.zigbee:__queue_receive({ mock_device.id, SimpleMetering.attributes.InstantaneousDemand:build_test_attr_report(mock_device, 40) })
            test.socket.capability:__expect_send(
                mock_device:generate_test_message("main", capabilities.powerMeter.power({ value = 40.0, unit = "W"}))
            )

            test.socket.zigbee:__queue_receive({ mock_device.id, ElectricalMeasurement.attributes.ActivePower:build_test_attr_report(mock_device, 50) })
            test.socket.capability:__expect_send(
                mock_device:generate_test_message("phaseA", capabilities.powerMeter.power({ value = 50.0, unit = "W"}))
            )

            test.socket.zigbee:__queue_receive({ mock_device.id, ElectricalMeasurement.attributes.RMSVoltage:build_test_attr_report(mock_device, 50) })
            test.socket.capability:__expect_send(
                mock_device:generate_test_message("phaseA", capabilities.voltageMeasurement.voltage({ value = 0.05, unit = "V"}))
            )

            test.socket.zigbee:__queue_receive({ mock_device.id, ElectricalMeasurement.attributes.RMSCurrent:build_test_attr_report(mock_device, 60) })
            test.socket.capability:__expect_send(
                mock_device:generate_test_message("phaseA", capabilities.currentMeasurement.current({ value = 0.06, unit = "A"}))
            )

            test.socket.zigbee:__queue_receive({ mock_device.id, ElectricalMeasurement.attributes.ActivePowerPhB:build_test_attr_report(mock_device, 70) })
            test.socket.capability:__expect_send(
                mock_device:generate_test_message("phaseB", capabilities.powerMeter.power({ value = 70.0, unit = "W"}))
            )

            test.socket.zigbee:__queue_receive({ mock_device.id, ElectricalMeasurement.attributes.RMSVoltagePhB:build_test_attr_report(mock_device, 80) })
            test.socket.capability:__expect_send(
                mock_device:generate_test_message("phaseB", capabilities.voltageMeasurement.voltage({ value = 0.08, unit = "V"}))
            )

            test.socket.zigbee:__queue_receive({ mock_device.id, ElectricalMeasurement.attributes.RMSCurrentPhB:build_test_attr_report(mock_device, 90) })
            test.socket.capability:__expect_send(
                mock_device:generate_test_message("phaseB", capabilities.currentMeasurement.current({ value = 0.09, unit = "A"}))
            )

            test.socket.zigbee:__queue_receive({ mock_device.id, ElectricalMeasurement.attributes.ActivePowerPhC:build_test_attr_report(mock_device, 100) })
            test.socket.capability:__expect_send(
                mock_device:generate_test_message("phaseC", capabilities.powerMeter.power({ value = 100.0, unit = "W"}))
            )

            test.socket.zigbee:__queue_receive({ mock_device.id, ElectricalMeasurement.attributes.RMSVoltagePhC:build_test_attr_report(mock_device, 110) })
            test.socket.capability:__expect_send(
                mock_device:generate_test_message("phaseC", capabilities.voltageMeasurement.voltage({ value = 0.11, unit = "V"}))
            )

            test.socket.zigbee:__queue_receive({ mock_device.id, ElectricalMeasurement.attributes.RMSCurrentPhC:build_test_attr_report(mock_device, 120) })
            test.socket.capability:__expect_send(
                mock_device:generate_test_message("phaseC", capabilities.currentMeasurement.current({ value = 0.12, unit = "A"}))
            )

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

test.register_coroutine_test(
        "lifecycle configure event should configure the device",
        function()
            test.socket.zigbee:__set_channel_ordering("relaxed")
            test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })

            expected_refresh_commands()

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
                ElectricalMeasurement.attributes.RMSCurrent:configure_reporting(
                    mock_device, 5, 3600, 5
                )
            })
            test.socket.zigbee:__expect_send({
                mock_device.id,
                ElectricalMeasurement.attributes.RMSCurrentPhB:configure_reporting(
                    mock_device, 5, 3600, 5
                )
            })
            test.socket.zigbee:__expect_send({
                mock_device.id,
                ElectricalMeasurement.attributes.RMSCurrentPhC:configure_reporting(
                    mock_device, 5, 3600, 5
                )
            })
            test.socket.zigbee:__expect_send({
                mock_device.id,
                ElectricalMeasurement.attributes.RMSVoltage:configure_reporting(
                    mock_device, 5, 3600, 5
                )
            })
            test.socket.zigbee:__expect_send({
                mock_device.id,
                ElectricalMeasurement.attributes.RMSVoltagePhB:configure_reporting(
                    mock_device, 5, 3600, 5
                )
            })
            test.socket.zigbee:__expect_send({
                mock_device.id,
                ElectricalMeasurement.attributes.RMSVoltagePhC:configure_reporting(
                    mock_device, 5, 3600, 5
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
                ElectricalMeasurement.attributes.ActivePowerPhB:configure_reporting(
                    mock_device, 5, 3600, 5
                )
            })
            test.socket.zigbee:__expect_send({
                mock_device.id,
                ElectricalMeasurement.attributes.ActivePowerPhC:configure_reporting(
                    mock_device, 5, 3600, 5
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
                SimpleMetering.attributes.CurrentSummationDelivered:configure_reporting(
                    mock_device, 5, 3600, 1
                )
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
                ElectricalMeasurement.attributes.ACPowerDivisor:read(mock_device)
            })
            test.socket.zigbee:__expect_send({
                mock_device.id,
                ElectricalMeasurement.attributes.ACPowerMultiplier:read(mock_device)
            })
            test.socket.zigbee:__expect_send({
                mock_device.id,
                ElectricalMeasurement.attributes.ACVoltageDivisor:read(mock_device)
            })
            test.socket.zigbee:__expect_send({
                mock_device.id,
                ElectricalMeasurement.attributes.ACVoltageMultiplier:read(mock_device)
            })
            test.socket.zigbee:__expect_send({
                mock_device.id,
                ElectricalMeasurement.attributes.ACCurrentDivisor:read(mock_device)
            })
            test.socket.zigbee:__expect_send({
                mock_device.id,
                ElectricalMeasurement.attributes.ACCurrentMultiplier:read(mock_device)
            })

            test.socket.zigbee:__expect_send({
                mock_device.id,
                cluster_base.configure_reporting(
                    mock_device,
                    data_types.ClusterId(SimpleMetering.ID),
                    data_types.AttributeId(CurrentSummationReceived),
                    data_types.ZigbeeDataType(data_types.Uint48.ID),
                    5,
                    3600,
                    1
                )
            })

            mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
        end
)

test.run_registered_tests()
