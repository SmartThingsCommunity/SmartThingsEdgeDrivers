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

local test = require "integration_test"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"
local version = require "version"
local clusters = require "st.matter.clusters"

if version.api < 13 then
  clusters.WaterHeaterMode = require "WaterHeaterMode"
end

if version.api < 11 then
  clusters.ElectricalEnergyMeasurement = require "ElectricalEnergyMeasurement"
end

local WATER_HEATER_EP = 10
local ELECTRICAL_SENSOR_EP = 11

local mock_device = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("water-heater-power-energy-powerConsumption.yml"),
  manufacturer_info = {
    vendor_id = 0x0000,
    product_id = 0x0000,
  },
  endpoints = {
    {
      endpoint_id = 0,
      clusters = {
        { cluster_id = clusters.Basic.ID, cluster_type = "SERVER" },
      },
      device_types = {
        {device_type_id = 0x0016, device_type_revision = 1}, -- RootNode
      }
    },
    {
      endpoint_id = WATER_HEATER_EP,
      clusters = {
        {
          cluster_id = clusters.Thermostat.ID,
          cluster_revision = 5,
          cluster_type = "SERVER",
          feature_map = 9, -- Heat and SCH features
        },
        { cluster_id = clusters.TemperatureMeasurement.ID, cluster_type = "SERVER" },
        { cluster_id = clusters.WaterHeaterMode.ID,        cluster_type = "SERVER" },
      },
      device_types = {
        {device_type_id = 0x050F, device_type_revision = 1}, -- Water Heater
      }
    },
    {
      endpoint_id = ELECTRICAL_SENSOR_EP,
      clusters = {
        { cluster_id = clusters.ElectricalEnergyMeasurement.ID, cluster_type = "SERVER", feature_map = 13 }, -- IMPE, CUME, PERE
        { cluster_id = clusters.ElectricalPowerMeasurement.ID,  cluster_type = "SERVER" },
      },
      device_types = {
        {device_type_id = 0x0510, device_type_revision = 1}, -- Electrical Sensor
      }
    }
  }
})

local function test_init()
  local cluster_subscribe_list = {
    clusters.Thermostat.attributes.SystemMode,
    clusters.Thermostat.attributes.ControlSequenceOfOperation,
    clusters.Thermostat.attributes.OccupiedHeatingSetpoint,
    clusters.Thermostat.attributes.AbsMinHeatSetpointLimit,
    clusters.Thermostat.attributes.AbsMaxHeatSetpointLimit,
    clusters.Thermostat.attributes.LocalTemperature,
    clusters.TemperatureMeasurement.attributes.MeasuredValue,
    clusters.TemperatureMeasurement.attributes.MinMeasuredValue,
    clusters.TemperatureMeasurement.attributes.MaxMeasuredValue,
    clusters.WaterHeaterMode.attributes.CurrentMode,
    clusters.WaterHeaterMode.attributes.SupportedModes,
    clusters.ElectricalPowerMeasurement.attributes.ActivePower,
    clusters.ElectricalEnergyMeasurement.attributes.PeriodicEnergyImported
  }
  test.socket.matter:__set_channel_ordering("relaxed")
  local subscribe_request = cluster_subscribe_list[1]:subscribe(mock_device)
  for i, cluster in ipairs(cluster_subscribe_list) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(mock_device))
    end
  end
  test.socket.matter:__expect_send({ mock_device.id, subscribe_request })
  test.mock_device.add_test_device(mock_device)
  test.socket.matter:__expect_send({
    mock_device.id, clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyImported:read(mock_device)
  })
end
test.set_test_init_function(test_init)

test.register_message_test(
  "Heating setpoint reports should generate correct messages",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.Thermostat.server.attributes.OccupiedHeatingSetpoint:build_test_report_data(mock_device, 1, 70*100)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",
        capabilities.thermostatHeatingSetpoint.heatingSetpointRange({ value = { minimum = 0.00, maximum = 100.00, step = 0.1 }, unit = "C" }))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.thermostatHeatingSetpoint.heatingSetpoint({ value = 70.0, unit = "C" }))
    }
  }
)

test.register_message_test(
  "Setting the heating setpoint should send the appropriate commands",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "thermostatHeatingSetpoint", component = "main", command = "setHeatingSetpoint", args = { 80 } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.Thermostat.attributes.OccupiedHeatingSetpoint:write(mock_device, WATER_HEATER_EP, 80*100)
      }
    }
  }
)

test.register_message_test(
  "Ensure WaterHeaderMode supportedModes are registered and setting Oven mode should send appropriate commands",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.WaterHeaterMode.attributes.SupportedModes:build_test_report_data(mock_device, WATER_HEATER_EP,
          {
            clusters.WaterHeaterMode.types.ModeOptionStruct({
              ["label"] = "Mode 1",
              ["mode"] = 0,
              ["mode_tags"] = {
                clusters.WaterHeaterMode.types.ModeTagStruct({ ["mfg_code"] = 256, ["value"] = 0 })
              }
            }),
            clusters.WaterHeaterMode.types.ModeOptionStruct({
              ["label"] = "Mode 2",
              ["mode"] = 1,
              ["mode_tags"] = {
                clusters.WaterHeaterMode.types.ModeTagStruct({ ["mfg_code"] = 256, ["value"] = 1 })
              }
            })
          }
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",
        capabilities.mode.supportedModes({ "Mode 1", "Mode 2" }, { visibility = { displayed = false } }))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",
        capabilities.mode.supportedArguments({ "Mode 1", "Mode 2" }, { visibility = { displayed = false } }))
    },
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "mode", component = "main", command = "setMode", args = { "Mode 1" } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.WaterHeaterMode.commands.ChangeToMode(mock_device, WATER_HEATER_EP, 0) -- Index where Mode 1 is stored)
      }
    }
  }
)

test.register_message_test(
  "Appropriate powerMeter capability events must be sent in 'W' on receiving ActivePower events",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.ElectricalPowerMeasurement.attributes.ActivePower:build_test_report_data(mock_device,
          ELECTRICAL_SENSOR_EP,
          15000)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.powerMeter.power({ value = 15.0, unit = "W" }))
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
  "energyMeter capability events must be sent in 'Wh' on receiving CumulativeEnergyMeasured events",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.ElectricalEnergyMeasurement.attributes
            .CumulativeEnergyImported:build_test_report_data(mock_device,
          ELECTRICAL_SENSOR_EP,
          clusters.ElectricalEnergyMeasurement.types.EnergyMeasurementStruct({ energy = 15000, start_timestamp = 0, end_timestamp = 0, start_systime = 0, end_systime = 0 }))
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.energyMeter.energy({ value = 15, unit = "Wh" }))
    }
  }
)

test.register_coroutine_test(
  "The total energy consumption of the device must be reported every 15 minutes",
  function()
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.matter:__expect_send({
      mock_device.id, clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyImported:read(mock_device)
    })

    test.socket.matter:__queue_receive({ mock_device.id, clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyImported:build_test_report_data(mock_device,
    ELECTRICAL_SENSOR_EP,
    clusters.ElectricalEnergyMeasurement.types.EnergyMeasurementStruct({ energy = 20000, start_timestamp = 0, end_timestamp = 0, start_systime = 0, end_systime = 0 })) }) -- 20Wh

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
      capabilities.energyMeter.energy({
        value = 20, unit = "Wh"
      }))
    )

    test.wait_for_events()
    test.mock_time.advance_time(60 * 15)

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
      capabilities.powerConsumptionReport.powerConsumption({
        energy = 20,
        deltaEnergy = 20,
          start = "1970-01-01T00:00:00Z",
          ["end"] = "1970-01-01T00:14:59Z"
        }))
      )

    test.wait_for_events()

    test.socket.matter:__expect_send({
      mock_device.id, clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyImported:read(mock_device)
    })

    test.socket.matter:__queue_receive({ mock_device.id, clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyImported:build_test_report_data(mock_device,
    ELECTRICAL_SENSOR_EP,
    clusters.ElectricalEnergyMeasurement.types.EnergyMeasurementStruct({ energy = 30000, start_timestamp = 0, end_timestamp = 0, start_systime = 0, end_systime = 0 })) }) -- 30Wh

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.energyMeter.energy({
          value = 30, unit = "Wh"
        }))
    )

    test.wait_for_events()
    test.mock_time.advance_time(60 * 15)

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.powerConsumptionReport.powerConsumption({
          energy = 30,
          deltaEnergy = 10,
          start = "1970-01-01T00:15:00Z",
          ["end"] = "1970-01-01T00:29:59Z"
        }))
    )
    test.wait_for_events()
  end,
  {
    test_init = function()
      test_init()
      test.timer.__create_and_queue_test_time_advance_timer(60 * 15, "interval", "polling_report_schedule_timer")
      test.timer.__create_and_queue_test_time_advance_timer(60, "interval", "create_poll_schedule")
    end
  }
)

test.register_message_test(
  "WaterHeaterMode SupportedModes must be registered. CurrentMode reports should report appropriate mode capability event. Command to setMode should send appropriate changeToMode matter command",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.WaterHeaterMode.attributes.SupportedModes:build_test_report_data(mock_device,
          WATER_HEATER_EP, {
          clusters.WaterHeaterMode.types.ModeOptionStruct({
            ["label"] = "Water Heater Mode 1",
            ["mode"] = 0,
            ["mode_tags"] = {
              clusters.WaterHeaterMode.types.ModeTagStruct({ ["mfg_code"] = 256, ["value"] = 0 })
            }
          }),
          clusters.WaterHeaterMode.types.ModeOptionStruct({
            ["label"] = "Water Heater Mode 2",
            ["mode"] = 1,
            ["mode_tags"] = {
              clusters.WaterHeaterMode.types.ModeTagStruct({ ["mfg_code"] = 256, ["value"] = 1 })
            }
          }),
          clusters.WaterHeaterMode.types.ModeOptionStruct({
            ["label"] = "Water Heater Mode 3",
            ["mode"] = 2,
            ["mode_tags"] = {
              clusters.WaterHeaterMode.types.ModeTagStruct({ ["mfg_code"] = 256, ["value"] = 2 })
            }
          })
        })
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",
        capabilities.mode.supportedModes(
        { "Water Heater Mode 1", "Water Heater Mode 2", "Water Heater Mode 3" },
          { visibility = { displayed = false } }))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",
        capabilities.mode.supportedArguments(
        { "Water Heater Mode 1", "Water Heater Mode 2", "Water Heater Mode 3" },
          { visibility = { displayed = false } }))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.WaterHeaterMode.attributes.CurrentMode:build_test_report_data(mock_device, WATER_HEATER_EP, 1) -- 1 is the index for Water Heater Mode 2 mode
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",
        capabilities.mode.mode("Water Heater Mode 2"))
    },
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "mode", component = "main", command = "setMode", args = { "Water Heater Mode 3" } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.WaterHeaterMode.commands.ChangeToMode(mock_device, WATER_HEATER_EP, 2) -- Index is Water Heater Mode 3
      }
    },
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "mode", component = "main", command = "setMode", args = { "Water Heater Mode 1" } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.WaterHeaterMode.commands.ChangeToMode(mock_device, WATER_HEATER_EP, 0) -- Index is Water Heater Mode 1
      }
    }
  }
)

test.run_registered_tests()
