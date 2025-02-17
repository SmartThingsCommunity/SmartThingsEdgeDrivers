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
local utils = require "st.utils"

local clusters = require "st.matter.clusters"

local mock_device = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("thermostat-humidity-fan.yml"),
  manufacturer_info = {
    vendor_id = 0x0000,
    product_id = 0x0000,
  },
  endpoints = {
    {
      endpoint_id = 0,
      clusters = {
        {cluster_id = clusters.Basic.ID, cluster_type = "SERVER"},
      },
      device_types = {
        device_type_id = 0x0016, device_type_revision = 1, -- RootNode
      }
    },
    {
      endpoint_id = 1,
      clusters = {
        {cluster_id = clusters.FanControl.ID, cluster_type = "SERVER"},
        {
          cluster_id = clusters.Thermostat.ID,
          cluster_revision=5,
          cluster_type="SERVER",
          feature_map=3, -- Heat and Cool features
        },
        {cluster_id = clusters.TemperatureMeasurement.ID, cluster_type = "SERVER"},
        {cluster_id = clusters.RelativeHumidityMeasurement.ID, cluster_type = "SERVER"},
        {cluster_id = clusters.PowerSource.ID, cluster_type = "SERVER"},
      }
    }
  }
})

local mock_device_auto = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("thermostat-humidity-fan.yml"),
  manufacturer_info = {
    vendor_id = 0x0000,
    product_id = 0x0000,
  },
  endpoints = {
    {
      endpoint_id = 0,
      clusters = {
        {cluster_id = clusters.Basic.ID, cluster_type = "SERVER"},
      },
      device_types = {
        device_type_id = 0x0016, device_type_revision = 1, -- RootNode
      }
    },
    {
      endpoint_id = 1,
      clusters = {
        {cluster_id = clusters.FanControl.ID, cluster_type = "SERVER"},
        {
          cluster_id = clusters.Thermostat.ID,
          cluster_revision=5,
          cluster_type="SERVER",
          feature_map=35, -- Heat, Cool, and Auto features
        },
        {cluster_id = clusters.TemperatureMeasurement.ID, cluster_type = "SERVER"},
        {cluster_id = clusters.RelativeHumidityMeasurement.ID, cluster_type = "SERVER"},
        {cluster_id = clusters.PowerSource.ID, cluster_type = "SERVER"},
      }
    }
  }
})

local function test_init()
  local cluster_subscribe_list = {
    clusters.Thermostat.attributes.LocalTemperature,
    clusters.Thermostat.attributes.OccupiedCoolingSetpoint,
    clusters.Thermostat.attributes.OccupiedHeatingSetpoint,
    clusters.Thermostat.attributes.AbsMinCoolSetpointLimit,
    clusters.Thermostat.attributes.AbsMaxCoolSetpointLimit,
    clusters.Thermostat.attributes.AbsMinHeatSetpointLimit,
    clusters.Thermostat.attributes.AbsMaxHeatSetpointLimit,
    clusters.Thermostat.attributes.SystemMode,
    clusters.Thermostat.attributes.ThermostatRunningState,
    clusters.Thermostat.attributes.ControlSequenceOfOperation,
    clusters.TemperatureMeasurement.attributes.MeasuredValue,
    clusters.TemperatureMeasurement.attributes.MinMeasuredValue,
    clusters.TemperatureMeasurement.attributes.MaxMeasuredValue,
    clusters.RelativeHumidityMeasurement.attributes.MeasuredValue,
    clusters.FanControl.attributes.FanMode,
    clusters.FanControl.attributes.FanModeSequence,
    clusters.PowerSource.attributes.BatPercentRemaining,
  }
  test.socket.matter:__set_channel_ordering("relaxed")
  local subscribe_request = cluster_subscribe_list[1]:subscribe(mock_device)
  for i, cluster in ipairs(cluster_subscribe_list) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(mock_device))
    end
  end
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})
  test.mock_device.add_test_device(mock_device)
end
test.set_test_init_function(test_init)

local function test_init_auto()
  local cluster_subscribe_list = {
    clusters.Thermostat.attributes.LocalTemperature,
    clusters.Thermostat.attributes.OccupiedCoolingSetpoint,
    clusters.Thermostat.attributes.OccupiedHeatingSetpoint,
    clusters.Thermostat.attributes.AbsMinCoolSetpointLimit,
    clusters.Thermostat.attributes.AbsMaxCoolSetpointLimit,
    clusters.Thermostat.attributes.AbsMinHeatSetpointLimit,
    clusters.Thermostat.attributes.AbsMaxHeatSetpointLimit,
    clusters.Thermostat.attributes.SystemMode,
    clusters.Thermostat.attributes.ThermostatRunningState,
    clusters.Thermostat.attributes.ControlSequenceOfOperation,
    clusters.TemperatureMeasurement.attributes.MeasuredValue,
    clusters.TemperatureMeasurement.attributes.MinMeasuredValue,
    clusters.TemperatureMeasurement.attributes.MaxMeasuredValue,
    clusters.RelativeHumidityMeasurement.attributes.MeasuredValue,
    clusters.FanControl.attributes.FanMode,
    clusters.FanControl.attributes.FanModeSequence,
    clusters.PowerSource.attributes.BatPercentRemaining,
  }
  test.socket.matter:__set_channel_ordering("relaxed")
  local subscribe_request = cluster_subscribe_list[1]:subscribe(mock_device_auto)
  for i, cluster in ipairs(cluster_subscribe_list) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(mock_device_auto))
    end
  end
  test.socket.matter:__expect_send({mock_device_auto.id, subscribe_request})
  test.socket.matter:__expect_send({mock_device_auto.id, clusters.Thermostat.attributes.MinSetpointDeadBand:read(mock_device_auto)})
  test.mock_device.add_test_device(mock_device_auto)
end

test.register_message_test(
  "Relative humidity reports should generate correct messages",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.RelativeHumidityMeasurement.server.attributes.MeasuredValue:build_test_report_data(mock_device, 1, 40*100)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.relativeHumidityMeasurement.humidity({ value = 40 }))
    }
  }
)

test.register_message_test(
  "Temperature reports should generate correct messages",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.TemperatureMeasurement.server.attributes.MeasuredValue:build_test_report_data(mock_device, 1, 40*100)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.temperatureMeasurement.temperature({ value = 40.0, unit = "C" }))
    }
  }
)

test.register_message_test(
  "Temperature reports from the thermostat cluster should generate correct messages",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.Thermostat.server.attributes.LocalTemperature:build_test_report_data(mock_device, 1, 40*100)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.temperatureMeasurement.temperature({ value = 40.0, unit = "C" }))
    }
  }
)

test.register_message_test(
  "Heating setpoint reports should generate correct messages",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.Thermostat.server.attributes.OccupiedHeatingSetpoint:build_test_report_data(mock_device, 1, 40*100)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.thermostatHeatingSetpoint.heatingSetpoint({ value = 40.0, unit = "C" }))
    }
  }
)

test.register_message_test(
  "Cooling setpoint reports should generate correct messages",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.Thermostat.server.attributes.OccupiedCoolingSetpoint:build_test_report_data(mock_device, 1, 40*100)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.thermostatCoolingSetpoint.coolingSetpoint({ value = 40.0, unit = "C" }))
    }
  }
)

test.register_message_test(
  "Thermostat running state reports (cooling) should generate correct messages",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.Thermostat.server.attributes.ThermostatRunningState:build_test_report_data(mock_device, 1, 2)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.thermostatOperatingState.thermostatOperatingState.cooling())
    }
  }
)

test.register_message_test(
  "Thermostat running state reports (heating) should generate correct messages",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.Thermostat.server.attributes.ThermostatRunningState:build_test_report_data(mock_device, 1, 1)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.thermostatOperatingState.thermostatOperatingState.heating())
    }
  }
)

test.register_message_test(
  "Thermostat running state reports (fan only) should generate correct messages",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.Thermostat.server.attributes.ThermostatRunningState:build_test_report_data(mock_device, 1, 4)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.thermostatOperatingState.thermostatOperatingState.fan_only())
    }
  }
)

test.register_message_test(
  "Thermostat running state reports (idle) should generate correct messages",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.Thermostat.server.attributes.ThermostatRunningState:build_test_report_data(mock_device, 1, 0)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.thermostatOperatingState.thermostatOperatingState.idle())
    }
  }
)

test.register_message_test(
  "Thermostat mode reports should generate correct messages",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.Thermostat.server.attributes.ControlSequenceOfOperation:build_test_report_data(mock_device, 1, 5)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.thermostatMode.supportedThermostatModes({"off", "cool", "heat"}, {visibility={displayed=false}}))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.Thermostat.server.attributes.SystemMode:build_test_report_data(mock_device, 1, 3)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.thermostatMode.thermostatMode.cool())
    },
  }
)

local ControlSequenceOfOperation = clusters.Thermostat.attributes.ControlSequenceOfOperation
test.register_message_test(
  "Thermostat control sequence reports should generate correct messages",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        ControlSequenceOfOperation:build_test_report_data(mock_device, 1, ControlSequenceOfOperation.COOLING_AND_HEATING_WITH_REHEAT)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.thermostatMode.supportedThermostatModes({"off", "cool", "heat"}, {visibility={displayed=false}}))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        ControlSequenceOfOperation:build_test_report_data(mock_device, 1, ControlSequenceOfOperation.HEATING_WITH_REHEAT)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.thermostatMode.supportedThermostatModes({"off", "heat"}, {visibility={displayed=false}}))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        ControlSequenceOfOperation:build_test_report_data(mock_device, 1, ControlSequenceOfOperation.COOLING_WITH_REHEAT)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.thermostatMode.supportedThermostatModes({"off", "cool"}, {visibility={displayed=false}}))
    },
  }
)

test.register_message_test(
  "Thermostat control sequence reports should generate correct messages when auto feature is supported",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device_auto.id,
        ControlSequenceOfOperation:build_test_report_data(mock_device_auto, 1, ControlSequenceOfOperation.COOLING_AND_HEATING_WITH_REHEAT)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device_auto:generate_test_message("main", capabilities.thermostatMode.supportedThermostatModes({"off", "cool", "heat", "auto"}, {visibility={displayed=false}}))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device_auto.id,
        ControlSequenceOfOperation:build_test_report_data(mock_device_auto, 1, ControlSequenceOfOperation.HEATING_WITH_REHEAT)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device_auto:generate_test_message("main", capabilities.thermostatMode.supportedThermostatModes({"off", "heat", "auto"}, {visibility={displayed=false}}))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device_auto.id,
        ControlSequenceOfOperation:build_test_report_data(mock_device_auto, 1, ControlSequenceOfOperation.COOLING_WITH_REHEAT)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device_auto:generate_test_message("main", capabilities.thermostatMode.supportedThermostatModes({"off", "cool", "auto"}, {visibility={displayed=false}}))
    },
  },
  { test_init = test_init_auto }
)

test.register_message_test(
  "Additional mode reports should extend the supported modes",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.Thermostat.server.attributes.ControlSequenceOfOperation:build_test_report_data(mock_device, 1, 5)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.thermostatMode.supportedThermostatModes({"off", "cool", "heat"}, {visibility={displayed=false}}))
    },
		{
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.Thermostat.server.attributes.SystemMode:build_test_report_data(mock_device, 1, 5)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.thermostatMode.supportedThermostatModes({"off", "cool", "heat", "emergency heat"}, {visibility={displayed=false}}))
    },
		{
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.thermostatMode.thermostatMode.emergency_heat())
    }
  }
)

test.register_message_test(
  "Additional mode reports should extend the supported modes when auto is supported",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device_auto.id,
        clusters.Thermostat.server.attributes.ControlSequenceOfOperation:build_test_report_data(mock_device_auto, 1, 5)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device_auto:generate_test_message("main", capabilities.thermostatMode.supportedThermostatModes({"off", "cool", "heat", "auto"}, {visibility={displayed=false}}))
    },
		{
      channel = "matter",
      direction = "receive",
      message = {
        mock_device_auto.id,
        clusters.Thermostat.server.attributes.SystemMode:build_test_report_data(mock_device_auto, 1, 5)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device_auto:generate_test_message("main", capabilities.thermostatMode.supportedThermostatModes({"off", "cool", "heat", "auto", "emergency heat"}, {visibility={displayed=false}}))
    },
		{
      channel = "capability",
      direction = "send",
      message = mock_device_auto:generate_test_message("main", capabilities.thermostatMode.thermostatMode.emergency_heat())
    }
  },
  { test_init = test_init_auto }
)

test.register_message_test(
  "Additional mode reports should not extend the supported modes if they are disallowed",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device_auto.id,
        clusters.Thermostat.server.attributes.ControlSequenceOfOperation:build_test_report_data(mock_device_auto, 1, 3)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device_auto:generate_test_message("main", capabilities.thermostatMode.supportedThermostatModes({"off", "heat", "auto"}, {visibility={displayed=false}}))
    },
		{
      channel = "matter",
      direction = "receive",
      message = {
        mock_device_auto.id,
        clusters.Thermostat.server.attributes.SystemMode:build_test_report_data(mock_device_auto, 1, 3)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device_auto.id,
        clusters.Thermostat.server.attributes.ControlSequenceOfOperation:build_test_report_data(mock_device_auto, 1, 1)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device_auto:generate_test_message("main", capabilities.thermostatMode.supportedThermostatModes({"off", "cool", "auto"}, {visibility={displayed=false}}))
    },
		{
      channel = "matter",
      direction = "receive",
      message = {
        mock_device_auto.id,
        clusters.Thermostat.server.attributes.SystemMode:build_test_report_data(mock_device_auto, 1, 5)
      }
    },
  },
  { test_init = test_init_auto }
)

local FanMode = clusters.FanControl.attributes.FanMode
test.register_message_test(
  "Thermostat fan mode reports should generate correct messages",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        FanMode:build_test_report_data(mock_device, 1, FanMode.SMART)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.thermostatFanMode.thermostatFanMode.auto())
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        FanMode:build_test_report_data(mock_device, 1, FanMode.AUTO)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.thermostatFanMode.thermostatFanMode.auto())
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        FanMode:build_test_report_data(mock_device, 1, FanMode.MEDIUM)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.thermostatFanMode.thermostatFanMode.on())
    },

  }
)

local FanModeSequence = clusters.FanControl.attributes.FanModeSequence
test.register_message_test(
  "Thermostat fan mode sequence reports should generate the appropriate supported modes",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        FanModeSequence:build_test_report_data(mock_device, 1, FanModeSequence.OFF_ON)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.thermostatFanMode.supportedThermostatFanModes({"on"}, {visibility={displayed=false}}))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        FanModeSequence:build_test_report_data(mock_device, 1, FanModeSequence.OFF_LOW_MED_HIGH_AUTO)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.thermostatFanMode.supportedThermostatFanModes({"auto", "on"}, {visibility={displayed=false}}))
    },
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
				{ capability = "thermostatHeatingSetpoint", component = "main", command = "setHeatingSetpoint", args = { 15 } }
			}
		},
		{
			channel = "matter",
			direction = "send",
			message = {
				mock_device.id,
				clusters.Thermostat.attributes.OccupiedHeatingSetpoint:write(mock_device, 1, 15*100)
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
				{ capability = "thermostatCoolingSetpoint", component = "main", command = "setCoolingSetpoint", args = { 25 } }
			}
		},
		{
			channel = "matter",
			direction = "send",
			message = {
				mock_device.id,
				clusters.Thermostat.attributes.OccupiedCoolingSetpoint:write(mock_device, 1, 25*100)
			}
		}
	}
)

test.register_message_test(
	"Setting the heating setpoint to a Fahrenheit value should send the appropriate commands",
	{
		{
			channel = "capability",
			direction = "receive",
			message = {
				mock_device.id,
				{ capability = "thermostatHeatingSetpoint", component = "main", command = "setHeatingSetpoint", args = { 64 } }
			}
		},
		{
			channel = "matter",
			direction = "send",
			message = {
				mock_device.id,
				clusters.Thermostat.attributes.OccupiedHeatingSetpoint:write(mock_device, 1, utils.round((64 - 32) * (5 / 9.0) * 100))
			}
		}
	}
)

test.register_message_test(
	"Setting the mode to cool should send the appropriate commands",
	{
		{
			channel = "capability",
			direction = "receive",
			message = {
				mock_device.id,
				{ capability = "thermostatMode", component = "main", command = "setThermostatMode", args = { "cool" } }
			}
		},
		{
			channel = "matter",
			direction = "send",
			message = {
				mock_device.id,
				clusters.Thermostat.attributes.SystemMode:write(mock_device, 1, 3)
			}
		}
	}
)

test.register_message_test(
	"Setting the fan mode to auto should send the appropriate commands",
	{
		{
			channel = "capability",
			direction = "receive",
			message = {
				mock_device.id,
				{ capability = "thermostatFanMode", component = "main", command = "setThermostatFanMode", args = { "auto" } }
			}
		},
		{
			channel = "matter",
			direction = "send",
			message = {
				mock_device.id,
				FanMode:write(mock_device, 1, FanMode.AUTO)
			}
		},
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "thermostatFanMode", component = "main", command = "setThermostatFanMode", args = { "on" } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        FanMode:write(mock_device, 1, FanMode.ON)
      }
    },
	}
)

test.register_message_test(
	"Setting the fan mode to auto should send the appropriate commands",
	{
		{
			channel = "capability",
			direction = "receive",
			message = {
				mock_device.id,
				{ capability = "thermostatFanMode", component = "main", command = "fanAuto", args = { } }
			}
		},
		{
			channel = "matter",
			direction = "send",
			message = {
				mock_device.id,
				clusters.FanControl.attributes.FanMode:write(mock_device, 1, 5)
			}
		}
	}
)

test.register_coroutine_test("Battery percent reports should generate correct messages", function()
  test.socket.matter:__queue_receive(
    {
      mock_device.id,
      clusters.PowerSource.attributes.BatPercentRemaining:build_test_report_data(
        mock_device, 1, 150
      ),
    }
  )
  test.socket.capability:__expect_send(
    mock_device:generate_test_message(
      "main", capabilities.battery.battery(math.floor(150/2.0+0.5))
    )
  )
  test.wait_for_events()
end)

local refresh_request = nil
local attribute_refresh_list = {
  clusters.Thermostat.attributes.LocalTemperature,
  clusters.Thermostat.attributes.OccupiedCoolingSetpoint,
  clusters.Thermostat.attributes.OccupiedHeatingSetpoint,
  clusters.Thermostat.attributes.AbsMinCoolSetpointLimit,
  clusters.Thermostat.attributes.AbsMaxCoolSetpointLimit,
  clusters.Thermostat.attributes.AbsMinHeatSetpointLimit,
  clusters.Thermostat.attributes.AbsMaxHeatSetpointLimit,
  clusters.Thermostat.attributes.SystemMode,
  clusters.Thermostat.attributes.ThermostatRunningState,
  clusters.Thermostat.attributes.ControlSequenceOfOperation,
  clusters.TemperatureMeasurement.attributes.MeasuredValue,
  clusters.TemperatureMeasurement.attributes.MinMeasuredValue,
  clusters.TemperatureMeasurement.attributes.MaxMeasuredValue,
  clusters.RelativeHumidityMeasurement.attributes.MeasuredValue,
  clusters.FanControl.attributes.FanMode,
  clusters.FanControl.attributes.FanModeSequence,
  clusters.PowerSource.attributes.BatPercentRemaining,
}
for _, cluster in ipairs(attribute_refresh_list) do
	local req = cluster:read(mock_device)
	if refresh_request == nil then
		refresh_request = req
	else
		refresh_request:merge(req)
	end
end
print("build refresh req", refresh_request)

test.register_message_test(
	"Default refresh should be handled",
	{
		{
			channel = "capability",
			direction = "receive",
			message = {
				mock_device.id,
				{ capability = "refresh", component = "main", command = "refresh", args = { } }
			}
		},
		{
			channel = "matter",
			direction = "send",
			message = {
				mock_device.id,
				refresh_request
			}
		}
	}
)

test.run_registered_tests()
