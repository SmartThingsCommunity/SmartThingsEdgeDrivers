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
local zw = require "st.zwave"
local constants = require "st.zwave.constants"
local zw_test_utilities = require "integration_test.zwave_test_utils"
local ThermostatSetpoint = (require "st.zwave.CommandClass.ThermostatSetpoint")({ version = 1 })
local ThermostatMode = (require "st.zwave.CommandClass.ThermostatMode")({ version = 2 })
local SensorMultilevel = (require "st.zwave.CommandClass.SensorMultilevel")({ version = 5 })
local t_utils = require "integration_test.utils"

-- supported comand classes
local thermostat_endpoints = {
  {
    command_classes = {
      {value = zw.THERMOSTAT_MODE},
      {value = zw.THERMOSTAT_OPERATING_STATE},
      {value = zw.THERMOSTAT_SETPOINT},
      {value = zw.SENSOR_MULTILEVEL},
    }
  }
}

local mock_device = test.mock_device.build_test_zwave_device(
  {
    profile = t_utils.get_profile_definition("thermostat-temperature-temperaturealarm.yml"),
    zwave_endpoints = thermostat_endpoints,
    zwave_manufacturer_id = 0x0239,
    zwave_product_type = 0x0001,
    zwave_product_id = 0x0001
  }
)
local function test_init()
  test.mock_device.add_test_device(mock_device)
end
test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Setting heating setpoint should be handled",
  function()
    mock_device:set_field(constants.TEMPERATURE_SCALE, 1, {persist = true})

    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({ mock_device.id, { capability = "thermostatHeatingSetpoint", command = "setHeatingSetpoint", args = { 29.0 } } })

    test.socket.zwave:__expect_send(
      zw_test_utilities.zwave_test_build_send_command(
          mock_device,
          ThermostatSetpoint:Set({
            setpoint_type = ThermostatSetpoint.setpoint_type.HEATING_1,
            scale = 1,
            value = 84.2
          })
      )
    )
  end
)

test.register_message_test(
  "Sensor multilevel report (33 CELCIUS) should be handled",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_device.id, "added" }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.thermostatMode.supportedThermostatModes({
        "heat", "eco"
      }, {visibility={displayed=false}}))
    },
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utilities.zwave_test_build_receive_command(SensorMultilevel:Report({
        sensor_type = SensorMultilevel.sensor_type.TEMPERATURE,
        scale = SensorMultilevel.scale.temperature.CELSIUS,
        sensor_value = 33 })) }
    },
		{
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.temperatureAlarm.temperatureAlarm.cleared())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.temperatureMeasurement.temperature({value = 33, unit = 'C'}))
    }
  }
)

test.register_message_test(
  "Sensor multilevel report (55 FAHRENHEIT) should be handled",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_device.id, "added" }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.thermostatMode.supportedThermostatModes({
        "heat", "eco"
      }, {visibility={displayed=false}}))
    },
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utilities.zwave_test_build_receive_command(SensorMultilevel:Report({
        sensor_type = SensorMultilevel.sensor_type.TEMPERATURE,
        scale = SensorMultilevel.scale.temperature.FAHRENHEIT,
        sensor_value = 55 })) }
    },
		{
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.temperatureAlarm.temperatureAlarm.cleared())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.temperatureMeasurement.temperature({value = 55, unit = 'F'}))
    }
  }
)

test.register_message_test(
  "Sensor multilevel report (30 FAHRENHEIT) should be handled",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_device.id, "added" }
    },
    -- {
    --   channel = "capability",
    --   direction = "send",
    --   message = mock_device:generate_test_message("main", capabilities.temperatureAlarm.temperatureAlarm.cleared())
    -- },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.thermostatMode.supportedThermostatModes({
        "heat", "eco"
      }, {visibility={displayed=false}}))
    },
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utilities.zwave_test_build_receive_command(SensorMultilevel:Report({
        sensor_type = SensorMultilevel.sensor_type.TEMPERATURE,
        scale = SensorMultilevel.scale.temperature.FAHRENHEIT,
        sensor_value = 30 })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.temperatureAlarm.temperatureAlarm.freeze())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.temperatureMeasurement.temperature({value = 30, unit = 'F'}))
    }
  }
)

test.register_message_test(
  "Sensor multilevel report (122 FAHRENHEIT) should be handled",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_device.id, "added" }
    },
    -- {
    --   channel = "capability",
    --   direction = "send",
    --   message = mock_device:generate_test_message("main", capabilities.temperatureAlarm.temperatureAlarm.cleared())
    -- },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.thermostatMode.supportedThermostatModes({
        "heat", "eco"
      }, {visibility={displayed=false}}))
    },
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utilities.zwave_test_build_receive_command(SensorMultilevel:Report({
        sensor_type = SensorMultilevel.sensor_type.TEMPERATURE,
        scale = SensorMultilevel.scale.temperature.FAHRENHEIT,
        sensor_value = 122 })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.temperatureAlarm.temperatureAlarm.heat())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.temperatureMeasurement.temperature({value = 122, unit = 'F'}))
    }
  }
)

test.register_message_test(
  "Sensor multilevel report (specific value 0x7ffd)  should be handled",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_device.id, "added" }
    },
    -- {
    --   channel = "capability",
    --   direction = "send",
    --   message = mock_device:generate_test_message("main", capabilities.temperatureAlarm.temperatureAlarm.cleared())
    -- },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.thermostatMode.supportedThermostatModes({
        "heat", "eco"
      }, {visibility={displayed=false}}))
    },
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utilities.zwave_test_build_receive_command(SensorMultilevel:Report({
        sensor_type = SensorMultilevel.sensor_type.TEMPERATURE,
        scale = 0x02,
        sensor_value = 0x7ffd })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.temperatureAlarm.temperatureAlarm.freeze())
    }
  }
)

test.register_message_test(
  "Sensor multilevel report (specific value 0x7fff) should be handled",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_device.id, "added" }
    },
    -- {
    --   channel = "capability",
    --   direction = "send",
    --   message = mock_device:generate_test_message("main", capabilities.temperatureAlarm.temperatureAlarm.cleared())
    -- },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.thermostatMode.supportedThermostatModes({
        "heat", "eco"
      }, {visibility={displayed=false}}))
    },
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utilities.zwave_test_build_receive_command(SensorMultilevel:Report({
        sensor_type = SensorMultilevel.sensor_type.TEMPERATURE,
        scale = 0x02,
        sensor_value = 0x7fff })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.temperatureAlarm.temperatureAlarm.heat())
    }
  }
)

test.register_message_test(
  "Supported thermostat modes report should generate nothing",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utilities.zwave_test_build_receive_command(ThermostatMode:SupportedReport({
        heat = true,
        cool = true,
        energy_save_heat = true
      })) }
    }
  }
)

test.register_message_test(
  "Mode report of ENERGY_SAVE_HEAT should generate an 'eco' event",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utilities.zwave_test_build_receive_command(ThermostatMode:Report({
        mode = ThermostatMode.mode.ENERGY_SAVE_HEAT
      })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.thermostatMode.thermostatMode({ value = "eco" }))
    }
  }
)

test.register_coroutine_test(
  "Setting the thermostat mode to eco should generate the appropriate commands",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({ mock_device.id, { capability = "thermostatMode", command = "setThermostatMode", args = { "eco" } } })
    test.socket.zwave:__expect_send(
      zw_test_utilities.zwave_test_build_send_command(
        mock_device,
        ThermostatMode:Set({ mode = ThermostatMode.mode.ENERGY_SAVE_HEAT })
      )
    )
    test.wait_for_events()

    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utilities.zwave_test_build_send_command(
        mock_device,
        ThermostatMode:Get({})
      )
    )
  end
)


test.run_registered_tests()
