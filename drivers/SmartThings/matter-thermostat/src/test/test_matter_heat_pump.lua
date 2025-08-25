-- Copyright 2024 SmartThings
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
local clusters = require "st.matter.clusters"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"
local version = require "version"
local im = require "st.matter.interaction_model"

local HEAT_PUMP_EP = 10
local THERMOSTAT_ONE_EP = 20
local THERMOSTAT_TWO_EP = 30

local HEAT_PUMP_DEVICE_TYPE_ID = 0x0309
local THERMOSTAT_DEVICE_TYPE_ID = 0x0301

if version.api < 11 then
  clusters.ElectricalEnergyMeasurement = require "ElectricalEnergyMeasurement"
  clusters.ElectricalPowerMeasurement = require "ElectricalPowerMeasurement"
end

local device_desc = {
  profile = t_utils.get_profile_definition("heat-pump-thermostat-humidity-thermostat-humidity.yml"),
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
        { device_type_id = 0x0016, device_type_revision = 1 }, -- RootNode
      }
    },
    {
      endpoint_id = HEAT_PUMP_EP,
      clusters = {
        { cluster_id = clusters.ElectricalEnergyMeasurement.ID, cluster_type = "SERVER", feature_map = 13 }, -- IMPE, CUME, PERE
        { cluster_id = clusters.ElectricalPowerMeasurement.ID, cluster_type = "SERVER" },
      },
      device_types = {
        { device_type_id = HEAT_PUMP_DEVICE_TYPE_ID, device_type_revision = 1 } -- Heat Pump
      }
    },
    {
      endpoint_id = THERMOSTAT_ONE_EP,
      clusters = {
        { cluster_id = clusters.Thermostat.ID, cluster_type = "SERVER", feature_map = 3  }, -- HEAT & COOL
        { cluster_id = clusters.TemperatureMeasurement.ID, cluster_type = "SERVER" },
        { cluster_id = clusters.RelativeHumidityMeasurement.ID, cluster_type = "SERVER" },
      },
      device_types = {
        { device_type_id = THERMOSTAT_DEVICE_TYPE_ID, device_type_revision = 1 } -- Thermostat
      }
    },
    {
      endpoint_id = THERMOSTAT_TWO_EP,
      clusters = {
        { cluster_id = clusters.Thermostat.ID, cluster_type = "SERVER", feature_map = 3 }, -- HEAT & COOL
        { cluster_id = clusters.TemperatureMeasurement.ID, cluster_type = "SERVER" },
        { cluster_id = clusters.RelativeHumidityMeasurement.ID, cluster_type = "SERVER" },
      },
      device_types = {
        { device_type_id = THERMOSTAT_DEVICE_TYPE_ID, device_type_revision = 1 } -- Thermostat
      }
    },
  }
}

local test_init_common = function(device)
  test.disable_startup_messages()
  test.mock_device.add_test_device(device)
  local cluster_subscribe_list = {
    clusters.Thermostat.attributes.SystemMode,
    clusters.Thermostat.attributes.ControlSequenceOfOperation,
    clusters.Thermostat.attributes.OccupiedHeatingSetpoint,
    clusters.Thermostat.attributes.AbsMinHeatSetpointLimit,
    clusters.Thermostat.attributes.AbsMaxHeatSetpointLimit,
    clusters.Thermostat.attributes.OccupiedCoolingSetpoint,
    clusters.Thermostat.attributes.AbsMinCoolSetpointLimit,
    clusters.Thermostat.attributes.AbsMaxCoolSetpointLimit,
    clusters.Thermostat.attributes.LocalTemperature,
    clusters.TemperatureMeasurement.attributes.MeasuredValue,
    clusters.TemperatureMeasurement.attributes.MinMeasuredValue,
    clusters.TemperatureMeasurement.attributes.MaxMeasuredValue,
    clusters.RelativeHumidityMeasurement.attributes.MeasuredValue,
    clusters.ElectricalPowerMeasurement.attributes.ActivePower,
    clusters.ElectricalEnergyMeasurement.attributes.PeriodicEnergyImported,
  }
  test.socket.matter:__set_channel_ordering("relaxed")
  local subscribe_request = cluster_subscribe_list[1]:subscribe(device)
  for i, cluster in ipairs(cluster_subscribe_list) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(device))
    end
  end
  test.socket.device_lifecycle:__queue_receive({ device.id, "added" })
  local read_request_on_added = {
    clusters.Thermostat.attributes.ControlSequenceOfOperation,
    clusters.FanControl.attributes.FanModeSequence,
    clusters.FanControl.attributes.WindSupport,
    clusters.FanControl.attributes.RockSupport,
    clusters.Thermostat.attributes.AttributeList,
  }
  local read_request = im.InteractionRequest(im.InteractionRequest.RequestType.READ, {})
  for _, clus in ipairs(read_request_on_added) do
    read_request:merge(clus:read(device))
  end
  test.socket.matter:__expect_send({
    device.id, read_request
  })

  test.socket.device_lifecycle:__queue_receive({ device.id, "init" })
  test.socket.matter:__expect_send({ device.id, subscribe_request })
end

local mock_device = test.mock_device.build_test_matter_device(device_desc)
local function test_init()
  test_init_common(mock_device)
  test.socket.matter:__expect_send({
    mock_device.id, clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyImported:read(mock_device)
  })
end

-- Create device with Thermostat clusters having features AUTO, HEAT & COOL
device_desc.endpoints[3].clusters[1].feature_map = 35
device_desc.endpoints[4].clusters[1].feature_map = 35
local mock_device_with_auto = test.mock_device.build_test_matter_device(device_desc)
local test_init_auto = function()
  test_init_common(mock_device_with_auto)
  test.socket.matter:__expect_send({
    mock_device_with_auto.id, clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyImported:read(mock_device_with_auto)
  })
  test.socket.matter:__expect_send({
    mock_device_with_auto.id, clusters.Thermostat.attributes.MinSetpointDeadBand:read(mock_device_with_auto)
  })
end

-- Set feature map of ElectricalEnergyMeasurement Cluster to only PERE and IMPE
device_desc.endpoints[2].clusters[1].feature_map = 9
local mock_device_with_pere_impe = test.mock_device.build_test_matter_device(device_desc)
local test_init_pere_impe = function()
  test_init_common(mock_device_with_pere_impe)
  test.socket.matter:__expect_send({
    mock_device_with_pere_impe.id, clusters.Thermostat.attributes.MinSetpointDeadBand:read(mock_device_with_pere_impe)
  })
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Assert component to endpoint map",
  function()
    local component_to_endpoint_map = mock_device:get_field("__component_to_endpoint_map")
    assert(component_to_endpoint_map["thermostatOne"] == THERMOSTAT_ONE_EP, string.format("Thermostat One Endpoint must be %d", THERMOSTAT_ONE_EP))
    assert(component_to_endpoint_map["thermostatTwo"] == THERMOSTAT_TWO_EP, string.format("Thermostat Two Endpoint must be %d", THERMOSTAT_TWO_EP))
  end
)

test.register_message_test(
  "Heating setpoint reports from component thermostat devices should emit correct events to the correct endpoint",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.Thermostat.server.attributes.OccupiedHeatingSetpoint:build_test_report_data(mock_device, THERMOSTAT_ONE_EP, 40*100)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("thermostatOne", capabilities.thermostatHeatingSetpoint.heatingSetpointRange({ value = { maximum = 100.0, minimum = 0.0, step = 0.1 }, unit = "C" }))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("thermostatOne", capabilities.thermostatHeatingSetpoint.heatingSetpoint({ value = 40.0, unit = "C" }))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.Thermostat.server.attributes.OccupiedHeatingSetpoint:build_test_report_data(mock_device, THERMOSTAT_TWO_EP, 23*100)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("thermostatTwo", capabilities.thermostatHeatingSetpoint.heatingSetpointRange({ value = { maximum = 100.0, minimum = 0.0, step = 0.1 }, unit = "C" }))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("thermostatTwo", capabilities.thermostatHeatingSetpoint.heatingSetpoint({ value = 23.0, unit = "C" }))
    }
  }
)

test.register_message_test(
  "Cooling setpoint reports reports from component thermostat devices should emit correct events to the correct endpoint",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.Thermostat.server.attributes.OccupiedCoolingSetpoint:build_test_report_data(mock_device, THERMOSTAT_ONE_EP, 39*100)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("thermostatOne", capabilities.thermostatCoolingSetpoint.coolingSetpointRange({ value = { maximum = 100.0, minimum = 0.0, step = 0.1 }, unit = "C" }))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("thermostatOne", capabilities.thermostatCoolingSetpoint.coolingSetpoint({ value = 39.0, unit = "C" }))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.Thermostat.server.attributes.OccupiedCoolingSetpoint:build_test_report_data(mock_device, THERMOSTAT_TWO_EP, 19*100)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("thermostatTwo", capabilities.thermostatCoolingSetpoint.coolingSetpointRange({ value = { maximum = 100.0, minimum = 0.0, step = 0.1 }, unit = "C" }))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("thermostatTwo", capabilities.thermostatCoolingSetpoint.coolingSetpoint({ value = 19.0, unit = "C" }))
    }
  }
)

test.register_message_test(
  "Heating setpoint commands recieved from a particular component should send the appropriate commands to the correct corresponding thermostat endpoint",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "thermostatHeatingSetpoint", component = "thermostatOne", command = "setHeatingSetpoint", args = { 20 } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.Thermostat.attributes.OccupiedHeatingSetpoint:write(mock_device, THERMOSTAT_ONE_EP, 20*100)
      }
    },
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "thermostatHeatingSetpoint", component = "thermostatTwo", command = "setHeatingSetpoint", args = { 25 } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.Thermostat.attributes.OccupiedHeatingSetpoint:write(mock_device, THERMOSTAT_TWO_EP, 25*100)
      }
    }
  }
)

test.register_message_test(
  "Setting the cooling setpoint should send the appropriate commands",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "thermostatCoolingSetpoint", component = "thermostatOne", command = "setCoolingSetpoint", args = { 13 } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.Thermostat.attributes.OccupiedCoolingSetpoint:write(mock_device, THERMOSTAT_ONE_EP , 13*100)
      }
    },
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "thermostatCoolingSetpoint", component = "thermostatTwo", command = "setCoolingSetpoint", args = { 13 } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.Thermostat.attributes.OccupiedCoolingSetpoint:write(mock_device, THERMOSTAT_TWO_EP , 13*100)
      }
    }
  }
)


test.register_message_test(
  "Thermostat mode reports from the component endpoints should generate correct messages to the right component",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.Thermostat.server.attributes.ControlSequenceOfOperation:build_test_report_data(mock_device, THERMOSTAT_ONE_EP, 5)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("thermostatOne", capabilities.thermostatMode.supportedThermostatModes({"off", "cool", "heat"}, {visibility={displayed=false}}))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.Thermostat.server.attributes.ControlSequenceOfOperation:build_test_report_data(mock_device, THERMOSTAT_TWO_EP, 5)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("thermostatTwo", capabilities.thermostatMode.supportedThermostatModes({"off", "cool", "heat"}, {visibility={displayed=false}}))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.Thermostat.server.attributes.SystemMode:build_test_report_data(mock_device, THERMOSTAT_ONE_EP, 5)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("thermostatOne", capabilities.thermostatMode.supportedThermostatModes({"off", "cool", "heat", "emergency heat"}, {visibility={displayed=false}}))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("thermostatOne", capabilities.thermostatMode.thermostatMode.emergency_heat())
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.Thermostat.server.attributes.SystemMode:build_test_report_data(mock_device, THERMOSTAT_TWO_EP, 4)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("thermostatTwo", capabilities.thermostatMode.thermostatMode.heat())
    },
  }
)

local ControlSequenceOfOperation = clusters.Thermostat.attributes.ControlSequenceOfOperation
test.register_message_test(
  "Thermostat control sequence reports form component thermostats should generate correct messages to the right component",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        ControlSequenceOfOperation:build_test_report_data(mock_device, THERMOSTAT_ONE_EP, ControlSequenceOfOperation.COOLING_AND_HEATING_WITH_REHEAT)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("thermostatOne", capabilities.thermostatMode.supportedThermostatModes({"off", "cool", "heat"}, {visibility={displayed=false}}))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        ControlSequenceOfOperation:build_test_report_data(mock_device, THERMOSTAT_ONE_EP, ControlSequenceOfOperation.HEATING_WITH_REHEAT)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("thermostatOne", capabilities.thermostatMode.supportedThermostatModes({"off", "heat"}, {visibility={displayed=false}}))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        ControlSequenceOfOperation:build_test_report_data(mock_device, THERMOSTAT_ONE_EP, ControlSequenceOfOperation.COOLING_WITH_REHEAT)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("thermostatOne", capabilities.thermostatMode.supportedThermostatModes({"off", "cool"}, {visibility={displayed=false}}))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        ControlSequenceOfOperation:build_test_report_data(mock_device, THERMOSTAT_TWO_EP, ControlSequenceOfOperation.COOLING_AND_HEATING_WITH_REHEAT)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("thermostatTwo", capabilities.thermostatMode.supportedThermostatModes({"off", "cool", "heat"}, {visibility={displayed=false}}))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        ControlSequenceOfOperation:build_test_report_data(mock_device, THERMOSTAT_TWO_EP, ControlSequenceOfOperation.HEATING_WITH_REHEAT)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("thermostatTwo", capabilities.thermostatMode.supportedThermostatModes({"off", "heat"}, {visibility={displayed=false}}))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        ControlSequenceOfOperation:build_test_report_data(mock_device, THERMOSTAT_TWO_EP, ControlSequenceOfOperation.COOLING_WITH_REHEAT)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("thermostatTwo", capabilities.thermostatMode.supportedThermostatModes({"off", "cool"}, {visibility={displayed=false}}))
    },
  }
)

test.register_message_test(
  "Additional mode reports from component thermostat endpoints should extend the supported modes for the correct component",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.Thermostat.server.attributes.ControlSequenceOfOperation:build_test_report_data(mock_device, THERMOSTAT_TWO_EP, 5)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("thermostatTwo", capabilities.thermostatMode.supportedThermostatModes({"off", "cool", "heat"}, {visibility={displayed=false}}))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.Thermostat.server.attributes.ControlSequenceOfOperation:build_test_report_data(mock_device, THERMOSTAT_ONE_EP, 5)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("thermostatOne", capabilities.thermostatMode.supportedThermostatModes({"off", "cool", "heat"}, {visibility={displayed=false}}))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.Thermostat.server.attributes.SystemMode:build_test_report_data(mock_device, THERMOSTAT_ONE_EP, 5)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("thermostatOne", capabilities.thermostatMode.supportedThermostatModes({"off", "cool", "heat", "emergency heat"}, {visibility={displayed=false}}))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("thermostatOne", capabilities.thermostatMode.thermostatMode.emergency_heat())
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.Thermostat.server.attributes.SystemMode:build_test_report_data(mock_device, THERMOSTAT_TWO_EP, 5)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("thermostatTwo", capabilities.thermostatMode.supportedThermostatModes({"off", "cool", "heat", "emergency heat"}, {visibility={displayed=false}}))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("thermostatTwo", capabilities.thermostatMode.thermostatMode.emergency_heat())
    },
  }
)

test.register_message_test(
  "Additional mode reports from component thermostat endpoints should extend the supported modes for their corresponding components when auto is supported",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device_with_auto.id,
        clusters.Thermostat.server.attributes.ControlSequenceOfOperation:build_test_report_data(mock_device_with_auto, THERMOSTAT_ONE_EP, 5)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device_with_auto:generate_test_message("thermostatOne", capabilities.thermostatMode.supportedThermostatModes({"off", "cool", "heat", "auto"}, {visibility={displayed=false}}))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device_with_auto.id,
        clusters.Thermostat.server.attributes.SystemMode:build_test_report_data(mock_device_with_auto, THERMOSTAT_ONE_EP, 5)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device_with_auto:generate_test_message("thermostatOne", capabilities.thermostatMode.supportedThermostatModes({"off", "cool", "heat", "auto", "emergency heat"}, {visibility={displayed=false}}))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device_with_auto:generate_test_message("thermostatOne", capabilities.thermostatMode.thermostatMode.emergency_heat())
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device_with_auto.id,
        clusters.Thermostat.server.attributes.ControlSequenceOfOperation:build_test_report_data(mock_device_with_auto, THERMOSTAT_TWO_EP, 5)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device_with_auto:generate_test_message("thermostatTwo", capabilities.thermostatMode.supportedThermostatModes({"off",  "emergency heat", "cool", "heat", "auto"}, {visibility={displayed=false}}))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device_with_auto.id,
        clusters.Thermostat.server.attributes.SystemMode:build_test_report_data(mock_device_with_auto, THERMOSTAT_TWO_EP, 5)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device_with_auto:generate_test_message("thermostatTwo", capabilities.thermostatMode.thermostatMode.emergency_heat())
    },
  },
  { test_init = test_init_auto }
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
          HEAT_PUMP_EP,
          15000)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.powerMeter.power({ value = 15.0, unit = "W" }))
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
          HEAT_PUMP_EP,
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
    HEAT_PUMP_EP,
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
    HEAT_PUMP_EP,
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

test.register_coroutine_test(
  "Ensure the driver does not send read request to devices without CUME & IMPE features",
  function()
    local timer = mock_device_with_pere_impe:get_field("__recurring_poll_timer")
    assert(timer == nil, "Polling timer must not be created if the device does not support CUME & IMPE features")
  end,
  {
    test_init = function()
      test_init_pere_impe()
    end
  }
)

test.register_coroutine_test(
  "PeriodicEnergyImported should report the energyMeter values",
  function()
    test.socket.matter:__queue_receive({ mock_device_with_pere_impe.id, clusters.ElectricalEnergyMeasurement.attributes.PeriodicEnergyImported:build_test_report_data(mock_device_with_pere_impe,
    HEAT_PUMP_EP,
    clusters.ElectricalEnergyMeasurement.types.EnergyMeasurementStruct({ energy = 30000, start_timestamp = 0, end_timestamp = 100, start_systime = 0, end_systime = 0 })) }) -- 30Wh

    test.socket.capability:__expect_send(
      mock_device_with_pere_impe:generate_test_message("main",
        capabilities.energyMeter.energy({
          value = 30, unit = "Wh"
        }))
    )
  end,
  {
    test_init = function()
      test_init_pere_impe()
    end
  }
)

test.register_coroutine_test(
  "Ensure only the cumulative energy reports are considered if the device supports both PERE and CUME features.",
  function()
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.matter:__expect_send({
      mock_device.id, clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyImported:read(mock_device)
    })

    test.socket.matter:__queue_receive({ mock_device.id, clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyImported:build_test_report_data(mock_device,
    HEAT_PUMP_EP,
    clusters.ElectricalEnergyMeasurement.types.EnergyMeasurementStruct({ energy = 20000, start_timestamp = 0, end_timestamp = 0, start_systime = 0, end_systime = 0 })) }) -- 20Wh

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
      capabilities.energyMeter.energy({
        value = 20, unit = "Wh"
      }))
    )

    test.wait_for_events()

    -- do not expect energyMeter event for this report.
    test.socket.matter:__queue_receive({ mock_device.id, clusters.ElectricalEnergyMeasurement.attributes.PeriodicEnergyImported:build_test_report_data(mock_device,
    HEAT_PUMP_EP,
    clusters.ElectricalEnergyMeasurement.types.EnergyMeasurementStruct({ energy = 20000, start_timestamp = 0, end_timestamp = 800, start_systime = 0, end_systime = 0 })) }) -- 20Wh

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
  end,
  {
    test_init = function()
      test_init()
      test.timer.__create_and_queue_test_time_advance_timer(60 * 15, "interval", "polling_report_schedule_timer")
      test.timer.__create_and_queue_test_time_advance_timer(60, "interval", "create_poll_schedule")
    end
  }
)

test.register_coroutine_test(
  "Consider the device reported time interval in case it is greater than 15 minutes for powerConsumptionReport capability reports",
  function()
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.matter:__expect_send({
      mock_device.id, clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyImported:read(mock_device)
    })

    test.socket.matter:__queue_receive({ mock_device.id, clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyImported:build_test_report_data(mock_device,
    HEAT_PUMP_EP,
    clusters.ElectricalEnergyMeasurement.types.EnergyMeasurementStruct({ energy = 20000, start_timestamp = 0, end_timestamp = 0, start_systime = 0, end_systime = 0 })) }) -- 20Wh

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
      capabilities.energyMeter.energy({
        value = 20, unit = "Wh"
      }))
    )

    test.wait_for_events()

    -- do not expect energyMeter event for this report. Only consider the time interval as it is greater than 15 minutes.
    test.socket.matter:__queue_receive({ mock_device.id, clusters.ElectricalEnergyMeasurement.attributes.PeriodicEnergyImported:build_test_report_data(mock_device,
    HEAT_PUMP_EP,
    clusters.ElectricalEnergyMeasurement.types.EnergyMeasurementStruct({ energy = 20000, start_timestamp = 0, end_timestamp = 1080, start_systime = 0, end_systime = 0 })) }) -- 20Wh 18 minutes


    test.wait_for_events()
    test.mock_time.advance_time(60 * 18)

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
      capabilities.powerConsumptionReport.powerConsumption({
        energy = 20,
        deltaEnergy = 20,
          start = "1970-01-01T00:00:00Z",
          ["end"] = "1970-01-01T00:17:59Z"
        }))
    )

    test.wait_for_events()
  end,
  {
    test_init = function()
      test_init()
      test.timer.__create_and_queue_test_time_advance_timer(60 * 15, "interval", "polling_report_schedule_timer")
      test.timer.__create_and_queue_test_time_advance_timer(60 * 18, "interval", "polling_report_schedule_timer")
      test.timer.__create_and_queue_test_time_advance_timer(60, "interval", "create_poll_schedule")
    end
  }
)

test.run_registered_tests()
