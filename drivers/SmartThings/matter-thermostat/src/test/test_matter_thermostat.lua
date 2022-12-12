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
      endpoint_id = 1,
      clusters = {
        {cluster_id = clusters.FanControl.ID, cluster_type = "SERVER"},
        {
          cluster_id = clusters.Thermostat.ID,
          attributes={
            0,
            18,
            26,
            27,
            28,
            65528,
            65529,
            65531,
            65532,
            65533,
          },
          client_commands={
            0,
          },
          cluster_revision=5,
          cluster_type="SERVER",
          events={},
          feature_map=3, -- Heat and Cool features
          server_commands={},
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
    clusters.Thermostat.attributes.SystemMode,
    clusters.Thermostat.attributes.ThermostatRunningState,
    clusters.Thermostat.attributes.ControlSequenceOfOperation,
    clusters.Thermostat.attributes.LocalTemperature,
    clusters.TemperatureMeasurement.attributes.MeasuredValue,
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
        clusters.Thermostat.server.attributes.SystemMode:build_test_report_data(mock_device, 1, 5)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.thermostatMode.thermostatMode.emergency_heat())
    },
		{
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.thermostatMode.supportedThermostatModes({"emergency heat"}))
    },
  }
)

test.register_message_test(
  "Thermostat control sequence reports should generate correct messages",
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
      message = mock_device:generate_test_message("main", capabilities.thermostatMode.supportedThermostatModes({"off", "cool", "heat", "auto"}))
    }
  }
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
      message = mock_device:generate_test_message("main", capabilities.thermostatMode.supportedThermostatModes({"off", "cool", "heat", "auto"}))
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
      message = mock_device:generate_test_message("main", capabilities.thermostatMode.thermostatMode.emergency_heat())
    },
		{
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.thermostatMode.supportedThermostatModes({"off", "cool", "heat", "auto", "emergency heat"}))
    }
  }
)

test.register_message_test(
  "Thermostat fan mode reports should generate correct messages",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.FanControl.server.attributes.FanMode:build_test_report_data(mock_device, 1, 5)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.thermostatFanMode.thermostatFanMode.auto())
    }
  }
)

test.register_message_test(
  "Thermostat fan mode sequence reports should generate the appropriate supported modes",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.FanControl.server.attributes.FanModeSequence:build_test_report_data(mock_device, 1, 5)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.thermostatFanMode.supportedThermostatFanModes({"on"}))
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
				clusters.FanControl.attributes.FanMode:write(mock_device, 1, 5)
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

local refresh_request = nil
local attribute_refresh_list = {
  clusters.Thermostat.attributes.LocalTemperature,
  clusters.Thermostat.attributes.OccupiedCoolingSetpoint,
  clusters.Thermostat.attributes.OccupiedHeatingSetpoint,
  clusters.Thermostat.attributes.SystemMode,
  clusters.Thermostat.attributes.ThermostatRunningState,
  clusters.Thermostat.attributes.ControlSequenceOfOperation,
  clusters.Thermostat.attributes.LocalTemperature,
  clusters.TemperatureMeasurement.attributes.MeasuredValue,
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
