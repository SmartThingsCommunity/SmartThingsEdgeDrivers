-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local clusters = require "st.zigbee.zcl.clusters"
local Thermostat = clusters.Thermostat
local FanControl = clusters.FanControl
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils = require "integration_test.utils"
local capabilities = require "st.capabilities"

local mock_device = test.mock_device.build_test_zigbee_device(
  { profile = t_utils.get_profile_definition("base-thermostat.yml"),
    zigbee_endpoints = {
      [10] = {
        id = 10,
        manufacturer = "HAI",
        model = "65A01-1",
        server_clusters = {0x0201, 0x0204, 0x0202, 0x0003}
      }
    }
  }
)

local ENDPOINT = 10

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device)end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Configure should configure all necessary attributes",
  function ()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({mock_device.id, "doConfigure"})
    test.socket.zigbee:__expect_send({
      mock_device.id,
      Thermostat.attributes.SystemMode:configure_reporting(mock_device, 5, 1800, nil):to_endpoint(ENDPOINT)})
    test.socket.zigbee:__expect_send({
      mock_device.id,
      Thermostat.attributes.OccupiedCoolingSetpoint:configure_reporting(mock_device, 5, 1800, 100):to_endpoint(ENDPOINT)})
    test.socket.zigbee:__expect_send({
      mock_device.id,
      Thermostat.attributes.OccupiedHeatingSetpoint:configure_reporting(mock_device, 5, 1800, 100):to_endpoint(ENDPOINT)})
    test.socket.zigbee:__expect_send({
      mock_device.id,
      Thermostat.attributes.LocalTemperature:configure_reporting(mock_device, 5, 1800, 100):to_endpoint(ENDPOINT)})
    test.socket.zigbee:__expect_send({
      mock_device.id,
      FanControl.attributes.FanMode:configure_reporting(mock_device, 5, 1800, nil):to_endpoint(ENDPOINT)})
    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Refresh should read all necessary attributes",
  function ()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.capability:__queue_receive( {mock_device.id, { capability = "refresh", component = "main", command = "refresh", args = {} }} )
    test.socket.zigbee:__expect_send( { mock_device.id, FanControl.attributes.FanMode:read(mock_device):to_endpoint(ENDPOINT) })
    test.socket.zigbee:__expect_send( { mock_device.id, Thermostat.attributes.SystemMode:read(mock_device):to_endpoint(ENDPOINT) })
    test.socket.zigbee:__expect_send( { mock_device.id, Thermostat.attributes.ControlSequenceOfOperation:read(mock_device):to_endpoint(ENDPOINT) })
    test.socket.zigbee:__expect_send( { mock_device.id, Thermostat.attributes.OccupiedCoolingSetpoint:read(mock_device):to_endpoint(ENDPOINT) })
    test.socket.zigbee:__expect_send( { mock_device.id, Thermostat.attributes.OccupiedHeatingSetpoint:read(mock_device):to_endpoint(ENDPOINT) })
    test.socket.zigbee:__expect_send( { mock_device.id, Thermostat.attributes.LocalTemperature:read(mock_device):to_endpoint(ENDPOINT) })
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Temperature reporting should create the appropriate events",
  function ()
    test.socket.zigbee:__queue_receive({ mock_device.id, Thermostat.attributes.LocalTemperature:build_test_attr_report(mock_device, 2100) })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.temperatureMeasurement.temperature({value = 21.0, unit = "C"})))
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Thermostat mode reporting should create the appropriate events",
  function ()
    test.socket.zigbee:__queue_receive({ mock_device.id, Thermostat.attributes.SystemMode:build_test_attr_report(mock_device, Thermostat.attributes.SystemMode.OFF) })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.thermostatMode.thermostatMode.off()))
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  -- This thermostat uses a non-standard supported mode mapping
  "ControlSequenceOfOperation reporting should create the appropriate events",
  function ()
    test.socket.zigbee:__queue_receive({ mock_device.id, Thermostat.attributes.ControlSequenceOfOperation:build_test_attr_report(mock_device, 0x02)})
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.thermostatMode.supportedThermostatModes({"auto", "cool", "heat", "emergency heat"},{visibility = {displayed = false }})))
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Thermostat fan mode reporting should create the appropriate events",
  function ()
    test.socket.zigbee:__queue_receive({ mock_device.id, FanControl.attributes.FanMode:build_test_attr_report(mock_device, FanControl.attributes.FanMode.AUTO) })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.thermostatFanMode.thermostatFanMode.auto()))
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Thermostat cooling setpoint reporting should create the appropriate events if the mode is supported",
  function ()
    test.socket.zigbee:__queue_receive({ mock_device.id, Thermostat.attributes.ControlSequenceOfOperation:build_test_attr_report(mock_device, 0x00)})
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.thermostatMode.supportedThermostatModes({"auto", "cool", "heat", "emergency heat"},{visibility = {displayed = false }})))
    test.socket.zigbee:__queue_receive({ mock_device.id, Thermostat.attributes.SystemMode:build_test_attr_report(mock_device, Thermostat.attributes.SystemMode.COOL)})
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.thermostatMode.thermostatMode.cool()))
    test.socket.zigbee:__queue_receive({ mock_device.id, Thermostat.attributes.OccupiedCoolingSetpoint:build_test_attr_report(mock_device, 2100) })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.thermostatCoolingSetpoint.coolingSetpoint({value = 21.0, unit = "C"})))
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Thermostat heating setpoint reporting should create the appropriate events if the mode is supported",
  function ()
    test.socket.zigbee:__queue_receive({ mock_device.id, Thermostat.attributes.ControlSequenceOfOperation:build_test_attr_report(mock_device, 0x02)})
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.thermostatMode.supportedThermostatModes({"auto", "cool", "heat", "emergency heat"},{visibility = {displayed = false }})))
    test.socket.zigbee:__queue_receive({ mock_device.id, Thermostat.attributes.SystemMode:build_test_attr_report(mock_device, Thermostat.attributes.SystemMode.EMERGENCY_HEATING)})
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.thermostatMode.thermostatMode.emergency_heat()))
    test.socket.zigbee:__queue_receive({ mock_device.id, Thermostat.attributes.OccupiedHeatingSetpoint:build_test_attr_report(mock_device, 2100) })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.thermostatHeatingSetpoint.heatingSetpoint({value = 21.0, unit = "C"})))
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Thermostat heating setpoint reporting should not create setpoint events if the mode is not currently active",
  function ()
    test.socket.zigbee:__queue_receive({ mock_device.id, Thermostat.attributes.ControlSequenceOfOperation:build_test_attr_report(mock_device, 0x00)})
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.thermostatMode.supportedThermostatModes({"auto", "cool", "heat", "emergency heat"},{visibility = {displayed = false }})))
    test.socket.zigbee:__queue_receive({ mock_device.id, Thermostat.attributes.SystemMode:build_test_attr_report(mock_device, Thermostat.attributes.SystemMode.COOL)})
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.thermostatMode.thermostatMode.cool()))
    test.socket.zigbee:__queue_receive({ mock_device.id, Thermostat.attributes.OccupiedHeatingSetpoint:build_test_attr_report(mock_device, 2100) })
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Thermostat cooling setpoint reporting should not create setpoint events if the mode is not currently active",
  function ()
    test.socket.zigbee:__queue_receive({ mock_device.id, Thermostat.attributes.ControlSequenceOfOperation:build_test_attr_report(mock_device, 0x02)})
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.thermostatMode.supportedThermostatModes({"auto", "cool", "heat", "emergency heat"},{visibility = {displayed = false }})))
    test.socket.zigbee:__queue_receive({ mock_device.id, Thermostat.attributes.SystemMode:build_test_attr_report(mock_device, Thermostat.attributes.SystemMode.EMERGENCY_HEATING)})
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.thermostatMode.thermostatMode.emergency_heat()))
    test.socket.zigbee:__queue_receive({ mock_device.id, Thermostat.attributes.OccupiedCoolingSetpoint:build_test_attr_report(mock_device, 2100) })
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Setting the heating setpoint should generate the appropriate messages",
  function ()
    test.socket.capability:__queue_receive({ mock_device.id, { component = "main", capability = capabilities.thermostatHeatingSetpoint.ID, command = "setHeatingSetpoint", args = {21} } })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.thermostatHeatingSetpoint.heatingSetpoint({value = 21.0, unit = "C"})))
    test.socket.zigbee:__expect_send( { mock_device.id, Thermostat.attributes.OccupiedHeatingSetpoint:write(mock_device, 2100):to_endpoint(ENDPOINT) })
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Setting the cooling setpoint should generate the appropriate messages",
  function ()
    test.socket.capability:__queue_receive({ mock_device.id, { component = "main", capability = capabilities.thermostatCoolingSetpoint.ID, command = "setCoolingSetpoint", args = {21} } })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.thermostatCoolingSetpoint.coolingSetpoint({value = 21.0, unit = "C"})))
    test.socket.zigbee:__expect_send( { mock_device.id, Thermostat.attributes.OccupiedCoolingSetpoint:write(mock_device, 2100):to_endpoint(ENDPOINT) })
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Setting the thermostat mode should generate the appropriate messages",
  function ()
    test.socket.capability:__queue_receive({ mock_device.id, { component = "main", capability = capabilities.thermostatMode.ID, command = "setThermostatMode", args = {"cool"} } })
    test.socket.zigbee:__expect_send( { mock_device.id, Thermostat.attributes.SystemMode:write(mock_device, 3):to_endpoint(ENDPOINT) })
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Setting the thermostat fan mode should generate the appropriate messages",
  function ()
    test.socket.capability:__queue_receive({ mock_device.id, { component = "main", capability = capabilities.thermostatFanMode.ID, command = "setThermostatFanMode", args = {"auto"} } })
    test.socket.zigbee:__expect_send( { mock_device.id, FanControl.attributes.FanMode:write(mock_device, 5):to_endpoint(ENDPOINT) })
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Handle added lifecycle",
  function()
    -- The initial valve and lock event should be send during the device's first time onboarding
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
      capabilities.thermostatMode.supportedThermostatModes({
        capabilities.thermostatMode.thermostatMode.auto.NAME,
        capabilities.thermostatMode.thermostatMode.cool.NAME,
        capabilities.thermostatMode.thermostatMode.heat.NAME,
        capabilities.thermostatMode.thermostatMode.emergency_heat.NAME
      }, { visibility = { displayed = false } }))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
      capabilities.thermostatFanMode.supportedThermostatFanModes({
        capabilities.thermostatFanMode.thermostatFanMode.auto.NAME,
        capabilities.thermostatFanMode.thermostatFanMode.on.NAME,
        capabilities.thermostatFanMode.thermostatFanMode.circulate.NAME
      }, { visibility = { displayed = false } }))
    )
    test.socket.zigbee:__expect_send( { mock_device.id, FanControl.attributes.FanMode:read(mock_device):to_endpoint(ENDPOINT) })
    test.socket.zigbee:__expect_send( { mock_device.id, Thermostat.attributes.SystemMode:read(mock_device):to_endpoint(ENDPOINT) })
    test.socket.zigbee:__expect_send( { mock_device.id, Thermostat.attributes.ControlSequenceOfOperation:read(mock_device):to_endpoint(ENDPOINT) })
    test.socket.zigbee:__expect_send( { mock_device.id, Thermostat.attributes.OccupiedCoolingSetpoint:read(mock_device):to_endpoint(ENDPOINT) })
    test.socket.zigbee:__expect_send( { mock_device.id, Thermostat.attributes.OccupiedHeatingSetpoint:read(mock_device):to_endpoint(ENDPOINT) })
    test.socket.zigbee:__expect_send( { mock_device.id, Thermostat.attributes.LocalTemperature:read(mock_device):to_endpoint(ENDPOINT) })
  end,
  {
     min_api_version = 19
  }
)


test.run_registered_tests()
