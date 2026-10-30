-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local log = require "log"
local test = require "integration_test"
local capabilities = require "st.capabilities"
local zw_test_utilities = require "integration_test.zwave_test_utils"
local zw = require "st.zwave"
local t_utils = require "integration_test.utils"

--- @type st.zwave.CommandClass.ThermostatSetpoint
local ThermostatSetpoint = (require "st.zwave.CommandClass.ThermostatSetpoint")({version=3})
--- @type st.zwave.CommandClass.ThermostatOperatingState
local ThermostatOperatingState = (require "st.zwave.CommandClass.ThermostatOperatingState")({version=1})
--- @type st.zwave.CommandClass.ThermostatMode
local ThermostatMode = (require "st.zwave.CommandClass.ThermostatMode")({version=3})
--- @type st.zwave.CommandClass.SensorMultilevel
local SensorMultilevel = (require "st.zwave.CommandClass.SensorMultilevel")({version=11})
--- @type st.zwave.CommandClass.Configuration
local Configuration = (require "st.zwave.CommandClass.Configuration")({version=1})
--- @type st.zwave.CommandClass.MultiChannelAssociation
local MultiChannelAssociation = (require "st.zwave.CommandClass.MultiChannelAssociation")({version=3})
--- @type st.zwave.CommandClass.Meter
local Meter = (require "st.zwave.CommandClass.Meter")({version=2})

-- supported command classes
local thermostat_endpoints = {
  {
    command_classes = {
      {value = zw.THERMOSTAT_MODE},
      {value = zw.THERMOSTAT_SETPOINT},
      {value = zw.THERMOSTAT_OPERATING_STATE},
      {value = zw.SENSOR_MULTILEVEL},
    }
  }
}

local mock_device = test.mock_device.build_test_zwave_device(
  {
    profile = t_utils.get_profile_definition("heatit-ztrm6-thermostat.yml"),
    zwave_endpoints = thermostat_endpoints,
    zwave_manufacturer_id = 0x019B,
    zwave_product_type = 0x0030,
    zwave_product_id = 0x3001,
  }
)

local mock_device_extra_temp = test.mock_device.build_test_zwave_device(
  {
    profile = t_utils.get_profile_definition("heatit-ztrm6-thermostat-extra-temp.yml"),
    zwave_endpoints = thermostat_endpoints,
    zwave_manufacturer_id = 0x019B,
    zwave_product_type = 0x0030,
    zwave_product_id = 0x3001,
  }
)

local mock_device_regulator = test.mock_device.build_test_zwave_device(
  {
    profile = t_utils.get_profile_definition("heatit-ztrm6-thermostat-regulator.yml"),
    zwave_endpoints = thermostat_endpoints,
    zwave_manufacturer_id = 0x019B,
    zwave_product_type = 0x0030,
    zwave_product_id = 0x3001,
  }
)

local function test_init()
  test.mock_device.add_test_device(mock_device)
  test.mock_device.add_test_device(mock_device_extra_temp)
  test.mock_device.add_test_device(mock_device_regulator)
end
test.set_test_init_function(test_init)

local CURRENT_THERMOSTAT_HEATING_MODE = "current_mode"
local CURRENT_SENSOR_CHANNEL = "current_channel"
local CURRENT_SENSOR_MODE = "current_sensor_mode"

-- ----- L I F E   C Y C L E   T e s t s -----

test.register_coroutine_test(
  "1.1 Lifecycle: added should be handled",
  function()
    mock_device:set_field(CURRENT_THERMOSTAT_HEATING_MODE, ThermostatMode.mode.HEAT, { persist = true })

    test.socket.device_lifecycle():__queue_receive({mock_device.id, "added"})

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.thermostatMode.supportedThermostatModes(
        {"off", "heat", "cool", "eco"}, { visibility = { displayed = false } }))
    )

    test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command(mock_device, Meter:Get({scale = Meter.scale.electric_meter.WATTS}) ) )
    test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command(mock_device, Meter:Get({scale = Meter.scale.electric_meter.KILOWATT_HOURS}) ) )

    -- Do Refresh
    test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command(mock_device, ThermostatMode:Get({}) ) )
    test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command(mock_device, ThermostatOperatingState:Get({}) ) )

    test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command(mock_device, SensorMultilevel:Get({}, {dst_channels = {2}}) ) ) -- roomTemperature
    test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command(mock_device, SensorMultilevel:Get({}, {dst_channels = {3}}) ) ) -- roomTemperatureExternal
    test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command(mock_device, SensorMultilevel:Get({}, {dst_channels = {4}}) ) ) -- floorTemperature

    test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command(mock_device, Meter:Get({scale = Meter.scale.electric_meter.WATTS}) ) )
    test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command(mock_device, Meter:Get({scale = Meter.scale.electric_meter.KILOWATT_HOURS}) ) )

    test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command(mock_device, ThermostatSetpoint:Get({setpoint_type = ThermostatSetpoint.setpoint_type.HEATING_1}) ) )
  end
)

test.register_coroutine_test(
  "1.3.1 Lifecycle: info_changed",
  function()
    local paramNumber = 14
    local paramSize = 1
    local paramValue = 6
    local _preferences = {}
    _preferences.tempHysteresis = paramValue
    test.socket.device_lifecycle():__queue_receive(mock_device:generate_info_changed({ preferences = _preferences }))

    test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command( mock_device, Configuration:Set({ parameter_number = paramNumber, configuration_value = paramValue, size = paramSize }) ))
    test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command( mock_device, Configuration:Get({ parameter_number = paramNumber }) ))
  end
)

test.register_coroutine_test(
  "Temperature report hysteresis preference writes configuration parameter 19",
  function()
    test.socket.device_lifecycle():__queue_receive(mock_device:generate_info_changed({
      preferences = {tempReportHysteresis = 11}
    }))
    test.socket.zwave:__expect_send(zw_test_utilities.zwave_test_build_send_command(
      mock_device, Configuration:Set({parameter_number = 19, size = 1, configuration_value = 11})
    ))
    test.socket.zwave:__expect_send(zw_test_utilities.zwave_test_build_send_command(
      mock_device, Configuration:Get({parameter_number = 19})
    ))
  end
)

test.register_coroutine_test(
  "1.3.1a Lifecycle: two-byte update interval accepts its default above 32767",
  function()
    test.socket.device_lifecycle():__queue_receive(mock_device:generate_info_changed({
      preferences = { updateInterval = 43200 }
    }))
    test.socket.zwave:__expect_send(zw_test_utilities.zwave_test_build_send_command(
      mock_device, Configuration:Set({parameter_number = 26, size = 2, configuration_value = -22336})
    ))
    test.socket.zwave:__expect_send(zw_test_utilities.zwave_test_build_send_command(
      mock_device, Configuration:Get({parameter_number = 26})
    ))
  end
)

test.register_coroutine_test(
  "1.3.1b Lifecycle: two-byte update interval accepts 65535",
  function()
    test.socket.device_lifecycle():__queue_receive(mock_device:generate_info_changed({
      preferences = { updateInterval = 65535 }
    }))
    test.socket.zwave:__expect_send(zw_test_utilities.zwave_test_build_send_command(
      mock_device, Configuration:Set({parameter_number = 26, size = 2, configuration_value = -1})
    ))
    test.socket.zwave:__expect_send(zw_test_utilities.zwave_test_build_send_command(
      mock_device, Configuration:Get({parameter_number = 26})
    ))
  end
)

test.register_coroutine_test(
  "1.3.2 Lifecycle: info_changed - Show floor temperature and back to default",
  function()
    local paramValue = 1
    local _preferences = {}
    _preferences.showFloorTemp = paramValue

    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.device_lifecycle():__queue_receive(mock_device:generate_info_changed({ preferences = _preferences }))

    mock_device:expect_metadata_update({profile = "heatit-ztrm6-thermostat-extra-temp"})

    test.wait_for_events()
    test.mock_time.advance_time(2)

    -- Refresh
    test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command(mock_device, ThermostatMode:Get({}) ) )
    test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command(mock_device, ThermostatOperatingState:Get({}) ) )

    test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command(mock_device, SensorMultilevel:Get({}, {dst_channels = {2}}) ) ) -- roomTemperature
    test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command(mock_device, SensorMultilevel:Get({}, {dst_channels = {3}}) ) ) -- roomTemperatureExternal
    test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command(mock_device, SensorMultilevel:Get({}, {dst_channels = {4}}) ) ) -- floorTemperature

    test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command(mock_device, Meter:Get({scale = Meter.scale.electric_meter.WATTS}) ) )
    test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command(mock_device, Meter:Get({scale = Meter.scale.electric_meter.KILOWATT_HOURS}) ) )

    test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command(mock_device, ThermostatSetpoint:Get({setpoint_type = ThermostatSetpoint.setpoint_type.HEATING_1}) ) )
  end
)

test.register_coroutine_test(
  "1.3.3 Lifecycle: info_changed - Hide floor temperature",
  function()
    test.socket.zwave:__set_channel_ordering("relaxed")

    -- Set showFloorTemp = 1
    local paramValue = "1"
    local _preferences = {}
    _preferences.showFloorTemp = paramValue
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.device_lifecycle():__queue_receive(mock_device_extra_temp:generate_info_changed({ preferences = _preferences }))

    mock_device_extra_temp:expect_metadata_update({profile = "heatit-ztrm6-thermostat-extra-temp"})

    test.wait_for_events()
    test.mock_time.advance_time(2)

    -- Refresh
    test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command(mock_device_extra_temp, ThermostatMode:Get({}) ) )
    test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command(mock_device_extra_temp, ThermostatOperatingState:Get({}) ) )

    test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command(mock_device_extra_temp, SensorMultilevel:Get({}, {dst_channels = {2}}) ) ) -- roomTemperature
    test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command(mock_device_extra_temp, SensorMultilevel:Get({}, {dst_channels = {3}}) ) ) -- roomTemperatureExternal
    test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command(mock_device_extra_temp, SensorMultilevel:Get({}, {dst_channels = {4}}) ) ) -- floorTemperature

    test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command(mock_device_extra_temp, Meter:Get({scale = Meter.scale.electric_meter.WATTS}) ) )
    test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command(mock_device_extra_temp, Meter:Get({scale = Meter.scale.electric_meter.KILOWATT_HOURS}) ) )

    test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command(mock_device_extra_temp, ThermostatSetpoint:Get({setpoint_type = ThermostatSetpoint.setpoint_type.HEATING_1}) ) )

    test.wait_for_events()
    test.mock_time.advance_time(2)

    -- Set showFloorTemp = 0
    _preferences.showFloorTemp = 0
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.device_lifecycle():__queue_receive(mock_device_extra_temp:generate_info_changed({ preferences = _preferences }))

    mock_device_extra_temp:expect_metadata_update({profile = "heatit-ztrm6-thermostat"})

    test.wait_for_events()
    test.mock_time.advance_time(2)

    -- Refresh
    test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command(mock_device_extra_temp, ThermostatMode:Get({}) ) )
    test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command(mock_device_extra_temp, ThermostatOperatingState:Get({}) ) )

    test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command(mock_device_extra_temp, SensorMultilevel:Get({}, {dst_channels = {2}}) ) ) -- roomTemperature
    test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command(mock_device_extra_temp, SensorMultilevel:Get({}, {dst_channels = {3}}) ) ) -- roomTemperatureExternal
    test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command(mock_device_extra_temp, SensorMultilevel:Get({}, {dst_channels = {4}}) ) ) -- floorTemperature

    test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command(mock_device_extra_temp, Meter:Get({scale = Meter.scale.electric_meter.WATTS}) ) )
    test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command(mock_device_extra_temp, Meter:Get({scale = Meter.scale.electric_meter.KILOWATT_HOURS}) ) )

    test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command(mock_device_extra_temp, ThermostatSetpoint:Get({setpoint_type = ThermostatSetpoint.setpoint_type.HEATING_1}) ) )
  end
)

-- ----- C A P A B I L I T Y   T e s t s -----

test.register_coroutine_test(
  "2.1.1 Capability: set_thermostat_mode HEAT Should send zwave ThermostatMode:Set",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.capability:__queue_receive({ mock_device.id, { capability = "thermostatMode", command = "setThermostatMode", args = { "heat" } } })

      test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command( mock_device, ThermostatMode:Set({mode = ThermostatMode.mode.HEAT}) ) )

      test.wait_for_events()
      test.mock_time.advance_time(1)

      -- Do refresh
      test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command(mock_device, ThermostatMode:Get({}) ) )
      test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command(mock_device, ThermostatOperatingState:Get({}) ) )

      test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command(mock_device, SensorMultilevel:Get({}, {dst_channels = {2}}) ) )
      test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command(mock_device, SensorMultilevel:Get({}, {dst_channels = {3}}) ) )
      test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command(mock_device, SensorMultilevel:Get({}, {dst_channels = {4}}) ) )

      test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command(mock_device, Meter:Get({scale = Meter.scale.electric_meter.WATTS}) ) )
      test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command(mock_device, Meter:Get({scale = Meter.scale.electric_meter.KILOWATT_HOURS}) ) )

      test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command(mock_device, ThermostatSetpoint:Get({setpoint_type = ThermostatSetpoint.setpoint_type.HEATING_1}) ) )
    end
)

test.register_coroutine_test(
  "2.1.3 Capability: set_thermostat_mode ENERGY_SAVE_HEAT Should send zwave ThermostatMode:Set",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.capability:__queue_receive({ mock_device.id, { capability = "thermostatMode", command = "setThermostatMode", args = { "energysaveheat" } } })

      test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command( mock_device, ThermostatMode:Set({mode = ThermostatMode.mode.ENERGY_SAVE_HEAT}) ) )

      test.wait_for_events()
      test.mock_time.advance_time(1)

      -- Do refresh
      test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command(mock_device, ThermostatMode:Get({}) ) )
      test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command(mock_device, ThermostatOperatingState:Get({}) ) )

      test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command(mock_device, SensorMultilevel:Get({}, {dst_channels = {2}}) ) )
      test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command(mock_device, SensorMultilevel:Get({}, {dst_channels = {3}}) ) )
      test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command(mock_device, SensorMultilevel:Get({}, {dst_channels = {4}}) ) )

      test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command(mock_device, Meter:Get({scale = Meter.scale.electric_meter.WATTS}) ) )
      test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command(mock_device, Meter:Get({scale = Meter.scale.electric_meter.KILOWATT_HOURS}) ) )

      test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command(mock_device, ThermostatSetpoint:Get({setpoint_type = ThermostatSetpoint.setpoint_type.ENERGY_SAVE_HEATING}) ) )
  end
)

test.register_coroutine_test(
  "2.1.4 Capability: set_thermostat_mode COOL Should send zwave ThermostatMode:Set",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.capability:__queue_receive({ mock_device.id, { capability = "thermostatMode", command = "setThermostatMode", args = { "cool" } } })

      test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command( mock_device, ThermostatMode:Set({mode = ThermostatMode.mode.COOL}) ) )

      test.wait_for_events()
      test.mock_time.advance_time(1)

      -- Do refresh
      test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command(mock_device, ThermostatMode:Get({}) ) )
      test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command(mock_device, ThermostatOperatingState:Get({}) ) )

      test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command(mock_device, SensorMultilevel:Get({}, {dst_channels = {2}}) ) )
      test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command(mock_device, SensorMultilevel:Get({}, {dst_channels = {3}}) ) )
      test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command(mock_device, SensorMultilevel:Get({}, {dst_channels = {4}}) ) )

      test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command(mock_device, Meter:Get({scale = Meter.scale.electric_meter.WATTS}) ) )
      test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command(mock_device, Meter:Get({scale = Meter.scale.electric_meter.KILOWATT_HOURS}) ) )

      test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command(mock_device, ThermostatSetpoint:Get({setpoint_type = ThermostatSetpoint.setpoint_type.COOLING_1}) ) )
  end
)

test.register_coroutine_test(
  "2.2.1 Capability: set_setpoint_factory mode = HEAT Should send zwave ThermostatSetpoint:Set",
    function()
      mock_device:set_field(CURRENT_THERMOSTAT_HEATING_MODE, ThermostatMode.mode.HEAT, { persist = true })

      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.capability:__queue_receive({ mock_device.id, { capability = "thermostatHeatingSetpoint", command = "setHeatingSetpoint", args = { 21.5 } } })

      test.socket.zwave:__expect_send(
          zw_test_utilities.zwave_test_build_send_command(
              mock_device,
              ThermostatSetpoint:Set({setpoint_type = ThermostatSetpoint.setpoint_type.HEATING_1, value = 21.5, size = 2})
          )
      )

      test.wait_for_events()
      test.mock_time.advance_time(1)

      test.socket.zwave:__expect_send(
          zw_test_utilities.zwave_test_build_send_command(mock_device,
              ThermostatSetpoint:Get({setpoint_type = ThermostatSetpoint.setpoint_type.HEATING_1})
            )
      )
      test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command(mock_device, SensorMultilevel:Get({}) ) )
    end
)

test.register_coroutine_test(
  "2.2.2 Capability: setting a setpoint while OFF uses the last active COOL setpoint",
  function()
    mock_device:set_field(CURRENT_THERMOSTAT_HEATING_MODE, ThermostatMode.mode.COOL)
    test.socket.capability:__queue_receive({
      mock_device.id, {capability = "thermostatMode", command = "setThermostatMode", args = {"off"}}
    })
    test.socket.zwave:__expect_send(zw_test_utilities.zwave_test_build_send_command(
      mock_device, ThermostatMode:Set({mode = ThermostatMode.mode.OFF})
    ))
    test.wait_for_events()

    test.socket.capability:__queue_receive({
      mock_device.id, {capability = "thermostatHeatingSetpoint", command = "setHeatingSetpoint", args = {21.5}}
    })
    test.socket.zwave:__expect_send(zw_test_utilities.zwave_test_build_send_command(
      mock_device, ThermostatSetpoint:Set({setpoint_type = ThermostatSetpoint.setpoint_type.COOLING_1, value = 21.5, size = 2})
    ))
  end
)

test.register_coroutine_test(
  "2.2.3 Capability: setting a setpoint after startup in OFF mode defaults to HEAT",
  function()
    test.socket.zwave:__queue_receive({
      mock_device.id, zw_test_utilities.zwave_test_build_receive_command(
        ThermostatMode:Report({mode = ThermostatMode.mode.OFF})
      )
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.thermostatMode.thermostatMode.off())
    )
    test.wait_for_events()

    test.socket.capability:__queue_receive({
      mock_device.id, {capability = "thermostatHeatingSetpoint", command = "setHeatingSetpoint", args = {21.5}}
    })
    test.socket.zwave:__expect_send(zw_test_utilities.zwave_test_build_send_command(
      mock_device, ThermostatMode:Get({})
    ))
    test.socket.zwave:__expect_send(zw_test_utilities.zwave_test_build_send_command(
      mock_device, ThermostatSetpoint:Set({setpoint_type = ThermostatSetpoint.setpoint_type.HEATING_1, value = 21.5, size = 2})
    ))
    test.wait_for_events()

    test.socket.zwave:__queue_receive({
      mock_device.id, zw_test_utilities.zwave_test_build_receive_command(ThermostatSetpoint:Report({
        setpoint_type = ThermostatSetpoint.setpoint_type.HEATING_1, value = 21.5
      }))
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.thermostatHeatingSetpoint.heatingSetpoint({value = 21.5, unit = "C"}))
    )
  end
)

test.register_coroutine_test(
  "2.3  Capability: do_refresh",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")

      mock_device:set_field(CURRENT_THERMOSTAT_HEATING_MODE, ThermostatMode.mode.HEAT, { persist = true })
      log.debug("#### Lifecycle: added: current_mode: " .. mock_device:get_field(CURRENT_THERMOSTAT_HEATING_MODE))

      test.socket.capability:__queue_receive({ mock_device.id, { capability = "refresh", component = "main", command = "refresh", args = {} } })

      -- Do refresh
      test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command(mock_device, ThermostatMode:Get({}) ) )
      test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command(mock_device, ThermostatOperatingState:Get({}) ) )

      test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command(mock_device, SensorMultilevel:Get({}, {dst_channels = {2}}) ) )
      test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command(mock_device, SensorMultilevel:Get({}, {dst_channels = {3}}) ) )
      test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command(mock_device, SensorMultilevel:Get({}, {dst_channels = {4}}) ) )

      test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command(mock_device, Meter:Get({scale = Meter.scale.electric_meter.WATTS}) ) )
      test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command(mock_device, Meter:Get({scale = Meter.scale.electric_meter.KILOWATT_HOURS}) ) )

      test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command(mock_device, ThermostatSetpoint:Get({setpoint_type = ThermostatSetpoint.setpoint_type.HEATING_1}) ) )
    end
)

-- ----- Z - W A V E   R e c e i v e   T e s t s -----

test.register_message_test(
    "3.1.1 Thermostat mode HEAT reports should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_device.id,
                    zw_test_utilities.zwave_test_build_receive_command(ThermostatMode:Report({ mode = ThermostatMode.mode.HEAT })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.thermostatMode.thermostatMode({ value = "heat" }))
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utilities.zwave_test_build_send_command(mock_device,
          ThermostatSetpoint:Get({setpoint_type = ThermostatSetpoint.setpoint_type.HEATING_1})
        )
      },
    }
)

test.register_message_test(
    "3.1.2 Thermostat mode OFF reports should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_device.id,
                    zw_test_utilities.zwave_test_build_receive_command(ThermostatMode:Report({ mode = ThermostatMode.mode.OFF })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.thermostatMode.thermostatMode({ value = "off" }))
      }
    }
)

test.register_message_test(
    "3.1.3 Thermostat mode ENERGY_SAVE_HEAT reports should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_device.id,
                    zw_test_utilities.zwave_test_build_receive_command(ThermostatMode:Report({ mode = ThermostatMode.mode.ENERGY_SAVE_HEAT })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.thermostatMode.thermostatMode({ value = "eco" }))
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utilities.zwave_test_build_send_command(mock_device,
          ThermostatSetpoint:Get({setpoint_type = ThermostatSetpoint.setpoint_type.ENERGY_SAVE_HEATING})
        )
      }
    }
)

test.register_message_test(
    "3.1.4 Thermostat mode COOL reports should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_device.id,
                    zw_test_utilities.zwave_test_build_receive_command(ThermostatMode:Report({ mode = ThermostatMode.mode.COOL })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.thermostatMode.thermostatMode({ value = "cool" }))
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utilities.zwave_test_build_send_command(mock_device,
          ThermostatSetpoint:Get({setpoint_type = ThermostatSetpoint.setpoint_type.COOLING_1})
        )
      }
    }
)

test.register_coroutine_test(
  "3.2.1 Z-wave receive: Heating setpoint report should be handled for mode HEAT.",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    mock_device:set_field(CURRENT_THERMOSTAT_HEATING_MODE, ThermostatMode.mode.HEAT, { persist = true })

    test.socket.zwave:__queue_receive({mock_device.id, ThermostatSetpoint:Report({
      setpoint_type = ThermostatSetpoint.setpoint_type.HEATING_1, value = 235
    }) })

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.thermostatHeatingSetpoint.heatingSetpoint({value = 235, unit = "C"}))
    )
  end
)

test.register_coroutine_test(
  "3.2.2 Z-wave receive: inactive ECO setpoint must not replace the displayed HEAT setpoint",
  function()
    mock_device:set_field(CURRENT_THERMOSTAT_HEATING_MODE, ThermostatMode.mode.HEAT)
    test.socket.zwave:__queue_receive({
      mock_device.id, zw_test_utilities.zwave_test_build_receive_command(ThermostatSetpoint:Report({
        setpoint_type = ThermostatSetpoint.setpoint_type.ENERGY_SAVE_HEATING, value = 18
      }))
    })
    test.wait_for_events()
    test.socket.zwave:__queue_receive({
      mock_device.id, zw_test_utilities.zwave_test_build_receive_command(ThermostatSetpoint:Report({
        setpoint_type = ThermostatSetpoint.setpoint_type.HEATING_1, value = 21
      }))
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.thermostatHeatingSetpoint.heatingSetpoint({value = 21, unit = "C"}))
    )
  end
)

test.register_message_test(
  "3.3.1 Configuration 27 selects HEAT mode without assuming the relay is heating",
  {
    {channel = "zwave", direction = "receive", message = {
      mock_device.id, zw_test_utilities.zwave_test_build_receive_command(Configuration:Report({
        parameter_number = 27, size = 1, configuration_value = 1
      }))
    }},
    {channel = "zwave", direction = "send", message = zw_test_utilities.zwave_test_build_send_command(
      mock_device, ThermostatSetpoint:Get({setpoint_type = ThermostatSetpoint.setpoint_type.HEATING_1})
    )},
    {channel = "capability", direction = "send", message =
      mock_device:generate_test_message("main", capabilities.thermostatMode.thermostatMode.heat())
    },
    {channel = "zwave", direction = "send", message = zw_test_utilities.zwave_test_build_send_command(
      mock_device, ThermostatOperatingState:Get({})
    )}
  },
  {inner_block_ordering = "relaxed"}
)

test.register_message_test(
  "3.3.2 Configuration 27 selects ECO mode without assuming the relay is heating",
  {
    {channel = "zwave", direction = "receive", message = {
      mock_device.id, zw_test_utilities.zwave_test_build_receive_command(Configuration:Report({
        parameter_number = 27, size = 1, configuration_value = 3
      }))
    }},
    {channel = "zwave", direction = "send", message = zw_test_utilities.zwave_test_build_send_command(
      mock_device, ThermostatSetpoint:Get({setpoint_type = ThermostatSetpoint.setpoint_type.ENERGY_SAVE_HEATING})
    )},
    {channel = "capability", direction = "send", message =
      mock_device:generate_test_message("main", capabilities.thermostatMode.thermostatMode.eco())
    },
    {channel = "zwave", direction = "send", message = zw_test_utilities.zwave_test_build_send_command(
      mock_device, ThermostatOperatingState:Get({})
    )}
  },
  {inner_block_ordering = "relaxed"}
)

test.register_message_test(
  "3.3.3 Operating state reports actual idle instead of assuming the selected HEAT mode is heating",
  {
    {channel = "zwave", direction = "receive", message = {
      mock_device.id, zw_test_utilities.zwave_test_build_receive_command(ThermostatOperatingState:Report({
        operating_state = ThermostatOperatingState.operating_state.IDLE
      }))
    }},
    {channel = "capability", direction = "send", message =
      mock_device:generate_test_message("main", capabilities.thermostatOperatingState.thermostatOperatingState.idle())
    }
  }
)

test.register_message_test(
  "3.3.4 Configuration 27 selects OFF without emitting an operating state",
  {
    {channel = "zwave", direction = "receive", message = {
      mock_device.id, zw_test_utilities.zwave_test_build_receive_command(Configuration:Report({
        parameter_number = 27, size = 1, configuration_value = 0
      }))
    }},
    {channel = "capability", direction = "send", message =
      mock_device:generate_test_message("main", capabilities.thermostatMode.thermostatMode.off())
    },
    {channel = "zwave", direction = "send", message = zw_test_utilities.zwave_test_build_send_command(
      mock_device, ThermostatOperatingState:Get({})
    )}
  },
  {inner_block_ordering = "relaxed"}
)

test.register_message_test(
  "3.3.5 Configuration 27 selects COOL without emitting an operating state",
  {
    {channel = "zwave", direction = "receive", message = {
      mock_device.id, zw_test_utilities.zwave_test_build_receive_command(Configuration:Report({
        parameter_number = 27, size = 1, configuration_value = 2
      }))
    }},
    {channel = "zwave", direction = "send", message = zw_test_utilities.zwave_test_build_send_command(
      mock_device, ThermostatSetpoint:Get({setpoint_type = ThermostatSetpoint.setpoint_type.COOLING_1})
    )},
    {channel = "capability", direction = "send", message =
      mock_device:generate_test_message("main", capabilities.thermostatMode.thermostatMode.cool())
    },
    {channel = "zwave", direction = "send", message = zw_test_utilities.zwave_test_build_send_command(
      mock_device, ThermostatOperatingState:Get({})
    )}
  },
  {inner_block_ordering = "relaxed"}
)

-- ----- A d d i t i o n a l   Z - w a v e   r e c e i v e   t e s t s -----

test.register_coroutine_test(
    "4.2.1 Air Temperature received with Sensor setting A",
    function()
      mock_device:set_field(CURRENT_SENSOR_CHANNEL, 2, { persist = true })
      test.socket.zwave:__queue_receive({mock_device.id, SensorMultilevel:Report({sensor_type = SensorMultilevel.sensor_type.TEMPERATURE,  scale = 0, sensor_value = 21.5}
        , { encap = zw.ENCAP.AUTO, src_channel = 2, dst_channels = {}  }) })
        test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.temperatureMeasurement.temperature({ value = 21.5, unit = "C" })))
    end
)

test.register_coroutine_test(
    "4.2.12 Floor Temperature received with Sensor setting F",
    function()
      mock_device:set_field(CURRENT_SENSOR_CHANNEL, 4)
      test.socket.zwave:__queue_receive({mock_device.id, SensorMultilevel:Report({sensor_type = SensorMultilevel.sensor_type.TEMPERATURE,  scale = 0, sensor_value = 22.5}
        , { encap = zw.ENCAP.AUTO, src_channel = 4, dst_channels = {}  }) })
      test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.temperatureMeasurement.temperature({ value = 22.5, unit = "C" })))
    end
)

test.register_message_test(
    "Energy meter reports should be handled",
    {
      { channel = "zwave", direction = "receive",
        message = { mock_device.id, zw_test_utilities.zwave_test_build_receive_command( Meter:Report({ scale = Meter.scale.electric_meter.KILOWATT_HOURS, meter_value = 5}) )}
      },
      { channel = "capability", direction = "send",
        message = mock_device:generate_test_message("main", capabilities.energyMeter.energy({ value = 5, unit = "kWh" })) }
    }
)

test.register_message_test(
    "Power meter reports should be handled",
    {
      { channel = "zwave", direction = "receive",
        message = { mock_device.id, zw_test_utilities.zwave_test_build_receive_command(Meter:Report({ scale = Meter.scale.electric_meter.WATTS, meter_value = 5 }))}
      },
      { channel = "capability", direction = "send",
        message = mock_device:generate_test_message("main", capabilities.powerMeter.power({ value = 5, unit = "W" }))
      }
    }
)

-- Update to handle settings update for MultiChannelAssociation
test.register_coroutine_test(
    "4.3.1 MultiChannelAssociation update",
    function()
      local _preferences = {}
      _preferences.assocGroup2OnOff = "41.3 1"

      test.socket.device_lifecycle():__queue_receive(mock_device:generate_info_changed({ preferences = _preferences }))

      test.socket.zwave:__expect_send(zw_test_utilities.zwave_test_build_send_command( mock_device,
          MultiChannelAssociation:Remove({ grouping_identifier = 2, node_ids = {} })
      ))

      test.socket.zwave:__expect_send(zw_test_utilities.zwave_test_build_send_command( mock_device,
          MultiChannelAssociation:Set({ grouping_identifier = 2, multi_channel_nodes = {{ multi_channel_node_id = 41, end_point=3, bit_address = false }}, node_ids = {1} })
      ))
      test.socket.zwave:__expect_send(zw_test_utilities.zwave_test_build_send_command( mock_device,
        MultiChannelAssociation:Get({ grouping_identifier = 2 })
      ))
    end
)

test.register_coroutine_test(
  "4.4 Change Floor sensor type. First 12k then 10k",
  function()
    local _preferences = {}
    _preferences.floorSensorType = 1
    test.socket.device_lifecycle():__queue_receive(mock_device:generate_info_changed({ preferences = _preferences }))

    test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command( mock_device, Configuration:Set({ parameter_number = 3, configuration_value = 1, size = 1 }) ) )
    test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command( mock_device, Configuration:Get({ parameter_number = 3 }) ) )

    test.wait_for_events()
    test.mock_time.advance_time(1)

    _preferences.floorSensorType = 0
    test.socket.device_lifecycle():__queue_receive(mock_device:generate_info_changed({ preferences = _preferences }))
    test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command( mock_device, Configuration:Set({ parameter_number = 3, configuration_value = 0, size = 1 }) ) )

    test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command (mock_device, Configuration:Get({ parameter_number = 3 }) ) )
  end
)

test.register_coroutine_test(
  "2.5.1 Capability: resetEnergyMeter Should send zwave Meter:Reset and emit 0 kWh",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1.5, "oneshot")
    test.socket.capability:__queue_receive({ mock_device.id, { capability = "energyMeter", command = "resetEnergyMeter", args = {}, component = "main" } })

    test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command( mock_device, Meter:Reset({}) ) )
    test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.energyMeter.energy({ value = 0, unit = "kWh" })) )

    test.wait_for_events()
    test.mock_time.advance_time(1.5)

    test.socket.zwave:__expect_send( zw_test_utilities.zwave_test_build_send_command( mock_device, Meter:Get({scale = Meter.scale.electric_meter.KILOWATT_HOURS}) ) )
  end
)

test.register_message_test(
    "1.2 Lifecycle: do_configure",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_device.id, "do_configure" }
      }
    },
    {
      inner_block_ordering = "relaxed"
    }
)

test.register_coroutine_test(
  "PWER level command maps 30 percent to parameter 25 even before a mode report",
  function()
    test.socket.capability:__queue_receive({
      mock_device_regulator.id, {capability = "level", command = "setLevel", component = "main", args = {30}}
    })
    test.socket.zwave:__expect_send(zw_test_utilities.zwave_test_build_send_command(
      mock_device_regulator, Configuration:Set({parameter_number = 25, size = 1, configuration_value = 3})
    ))
    test.socket.zwave:__expect_send(zw_test_utilities.zwave_test_build_send_command(
      mock_device_regulator, Configuration:Get({parameter_number = 25})
    ))
  end
)

test.register_coroutine_test(
  "PWER level command maps 100 percent to configuration parameter 25 value 10",
  function()
    mock_device_regulator:set_field(CURRENT_SENSOR_MODE, 5)
    test.socket.capability:__queue_receive({
      mock_device_regulator.id, {capability = "level", command = "setLevel", component = "main", args = {100}}
    })
    test.socket.zwave:__expect_send(zw_test_utilities.zwave_test_build_send_command(
      mock_device_regulator, Configuration:Set({parameter_number = 25, size = 1, configuration_value = 10})
    ))
    test.socket.zwave:__expect_send(zw_test_utilities.zwave_test_build_send_command(
      mock_device_regulator, Configuration:Get({parameter_number = 25})
    ))
  end
)

test.register_coroutine_test(
  "Legacy PWER setting still writes parameter 25",
  function()
    test.socket.device_lifecycle():__queue_receive(mock_device_regulator:generate_info_changed({
      preferences = {regulatorLevel = 3}
    }))
    test.socket.zwave:__expect_send(zw_test_utilities.zwave_test_build_send_command(
      mock_device_regulator, Configuration:Set({parameter_number = 25, size = 1, configuration_value = 3})
    ))
    test.socket.zwave:__expect_send(zw_test_utilities.zwave_test_build_send_command(
      mock_device_regulator, Configuration:Get({parameter_number = 25})
    ))
  end
)

test.register_coroutine_test(
  "Entering PWER switches profile and requests current regulator level",
  function()
    test.socket.zwave:__queue_receive({
      mock_device.id, zw_test_utilities.zwave_test_build_receive_command(Configuration:Report({
        parameter_number = 2, size = 1, configuration_value = 5
      }))
    })
    mock_device:expect_metadata_update({profile = "heatit-ztrm6-thermostat-regulator"})
    test.socket.zwave:__expect_send(zw_test_utilities.zwave_test_build_send_command(
      mock_device, SensorMultilevel:Get({}, {dst_channels = {2}})
    ))
    test.socket.zwave:__expect_send(zw_test_utilities.zwave_test_build_send_command(
      mock_device, Configuration:Get({parameter_number = 25})
    ))
  end
)

test.register_coroutine_test(
  "PWER refresh requests current regulator level",
  function()
    test.socket.capability:__queue_receive({
      mock_device_regulator.id, {capability = "refresh", command = "refresh", component = "main", args = {}}
    })
    test.socket.zwave:__expect_send(zw_test_utilities.zwave_test_build_send_command(
      mock_device_regulator, ThermostatMode:Get({})
    ))
    test.socket.zwave:__expect_send(zw_test_utilities.zwave_test_build_send_command(
      mock_device_regulator, ThermostatOperatingState:Get({})
    ))
    test.socket.zwave:__expect_send(zw_test_utilities.zwave_test_build_send_command(
      mock_device_regulator, Configuration:Get({parameter_number = 25})
    ))
    for _, endpoint in ipairs({2, 3, 4}) do
      test.socket.zwave:__expect_send(zw_test_utilities.zwave_test_build_send_command(
        mock_device_regulator, SensorMultilevel:Get({}, {dst_channels = {endpoint}})
      ))
    end
    test.socket.zwave:__expect_send(zw_test_utilities.zwave_test_build_send_command(
      mock_device_regulator, Meter:Get({scale = Meter.scale.electric_meter.WATTS})
    ))
    test.socket.zwave:__expect_send(zw_test_utilities.zwave_test_build_send_command(
      mock_device_regulator, Meter:Get({scale = Meter.scale.electric_meter.KILOWATT_HOURS})
    ))
    test.socket.zwave:__expect_send(zw_test_utilities.zwave_test_build_send_command(
      mock_device_regulator, ThermostatSetpoint:Get({setpoint_type = ThermostatSetpoint.setpoint_type.HEATING_1})
    ))
  end
)

test.register_coroutine_test(
  "PWER level command rounds to supported ten-percent increments",
  function()
    mock_device_regulator:set_field(CURRENT_SENSOR_MODE, 5)
    test.socket.capability:__queue_receive({
      mock_device_regulator.id, {capability = "level", command = "setLevel", component = "main", args = {36}}
    })
    test.socket.zwave:__expect_send(zw_test_utilities.zwave_test_build_send_command(
      mock_device_regulator, Configuration:Set({parameter_number = 25, size = 1, configuration_value = 4})
    ))
    test.socket.zwave:__expect_send(zw_test_utilities.zwave_test_build_send_command(
      mock_device_regulator, Configuration:Get({parameter_number = 25})
    ))
  end
)

test.register_coroutine_test(
  "PWER level command rejects unsupported values and non-PWER modes",
  function()
    mock_device_regulator:set_field(CURRENT_SENSOR_MODE, 5)
    test.socket.capability:__queue_receive({
      mock_device_regulator.id, {capability = "level", command = "setLevel", component = "main", args = {0}}
    })
    test.socket.capability:__queue_receive({
      mock_device_regulator.id, {capability = "level", command = "setLevel", component = "main", args = {9}}
    })
    mock_device:set_field(CURRENT_SENSOR_MODE, 1)
    test.socket.capability:__queue_receive({
      mock_device.id, {capability = "level", command = "setLevel", component = "main", args = {30}}
    })
    test.wait_for_events()
  end
)

test.register_message_test(
  "PWER parameter 25 report tracks local power level changes",
  {
    {channel = "zwave", direction = "receive", message = {
      mock_device_regulator.id, zw_test_utilities.zwave_test_build_receive_command(Configuration:Report({
        parameter_number = 25, size = 1, configuration_value = 3
      }))
    }},
    {channel = "capability", direction = "send", message =
      mock_device_regulator:generate_test_message("main", capabilities.level.level(30))
    }
  }
)

test.register_message_test(
  "PWER parameter 25 report ignores invalid device values",
  {
    {channel = "zwave", direction = "receive", message = {
      mock_device_regulator.id, zw_test_utilities.zwave_test_build_receive_command(Configuration:Report({
        parameter_number = 25, size = 1, configuration_value = 0
      }))
    }}
  }
)

test.register_message_test(
  "Parameter 25 report does not emit level for normal thermostat profile",
  {
    {channel = "zwave", direction = "receive", message = {
      mock_device.id, zw_test_utilities.zwave_test_build_receive_command(Configuration:Report({
        parameter_number = 25, size = 1, configuration_value = 3
      }))
    }}
  }
)

test.run_registered_tests()
