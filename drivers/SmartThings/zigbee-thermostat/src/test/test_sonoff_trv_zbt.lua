-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local data_types = require "st.zigbee.data_types"
local device_management = require "st.zigbee.device_management"
local generic_body = require "st.zigbee.generic_body"
local messages = require "st.zigbee.messages"
local zcl_messages = require "st.zigbee.zcl"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils = require "integration_test.utils"
local zb_const = require "st.zigbee.constants"

local PowerConfiguration = clusters.PowerConfiguration
local Thermostat = clusters.Thermostat

local SONOFF_CLUSTER = 0xFC11
local WORK_MODE_ATTR = 0x0018
local BUTTON_COMMAND = 0x10

local mock_device = test.mock_device.build_test_zigbee_device({
  profile = t_utils.get_profile_definition("thermostat-sonoff-trv-zbt.yml"),
  zigbee_endpoints = {
    [1] = {
      id = 1,
      manufacturer = "SONOFF",
      model = "TRV-ZBT",
      server_clusters = { 0x0001, 0x0201, 0x0402, SONOFF_CLUSTER },
    },
  },
})

zigbee_test_utils.prepare_zigbee_env_info()
test.set_test_init_function(function()
  test.mock_device.add_test_device(mock_device)
  test.socket.capability:__expect_send(
    mock_device:generate_test_message("main", capabilities.thermostatMode.supportedThermostatModes(
      { "off", "heat", "auto" }, { visibility = { displayed = false } }
    ))
  )
  test.socket.capability:__expect_send(
    mock_device:generate_test_message("main", capabilities.thermostatHeatingSetpoint.heatingSetpointRange({
      value = { minimum = 5, maximum = 30 },
      unit = "C",
    }, { visibility = { displayed = false } }))
  )
  for _, attribute in ipairs({
    Thermostat.attributes.LocalTemperature,
    Thermostat.attributes.OccupiedHeatingSetpoint,
    Thermostat.attributes.SystemMode,
    Thermostat.attributes.MinHeatSetpointLimit,
    Thermostat.attributes.MaxHeatSetpointLimit,
    PowerConfiguration.attributes.BatteryPercentageRemaining,
  }) do
    test.socket.zigbee:__expect_send({ mock_device.id, attribute:read(mock_device) })
  end
end)

local function bluetooth_pairing_command(device)
  local zcl_header = zcl_messages.ZclHeader({
    cmd = data_types.ZCLCommandId(BUTTON_COMMAND),
  })
  zcl_header.frame_ctrl:set_cluster_specific()

  return messages.ZigbeeMessageTx({
    address_header = messages.AddressHeader(
      zb_const.HUB.ADDR,
      zb_const.HUB.ENDPOINT,
      device:get_short_address(),
      1,
      zb_const.HA_PROFILE_ID,
      SONOFF_CLUSTER
    ),
    body = zcl_messages.ZclMessageBody({
      zcl_header = zcl_header,
      zcl_body = generic_body.GenericBody(string.char(0x03, 0x01, 0x01)),
    }),
  })
end

test.register_message_test(
  "SONOFF TRV-ZBT reports local temperature",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, Thermostat.attributes.LocalTemperature:build_test_attr_report(mock_device, 2150) },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.temperatureMeasurement.temperature({ value = 21.5, unit = "C" })),
    },
  },
  { min_api_version = 14 }
)

test.register_message_test(
  "SONOFF TRV-ZBT reports setpoint and battery percentage",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, Thermostat.attributes.OccupiedHeatingSetpoint:build_test_attr_report(mock_device, 2250) },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.thermostatHeatingSetpoint.heatingSetpoint({ value = 22.5, unit = "C" })),
    },
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, PowerConfiguration.attributes.BatteryPercentageRemaining:build_test_attr_report(mock_device, 146) },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.battery.battery(73)),
    },
  },
  { min_api_version = 14 }
)

test.register_message_test(
  "SONOFF TRV-ZBT maps standard and proprietary modes",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, Thermostat.attributes.SystemMode:build_test_attr_report(mock_device, Thermostat.attributes.SystemMode.HEAT) },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.thermostatMode.thermostatMode.heat()),
    },
    {
      channel = "zigbee",
      direction = "receive",
      message = {
        mock_device.id,
        zigbee_test_utils.build_attribute_report(mock_device, SONOFF_CLUSTER, {
          { WORK_MODE_ATTR, data_types.Uint8.ID, 0x04 },
        }),
      },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.thermostatMode.thermostatMode.auto()),
    },
  },
  { min_api_version = 14 }
)

test.register_coroutine_test(
  "SONOFF TRV-ZBT writes setpoints in Celsius and Fahrenheit",
  function()
    test.socket.capability:__queue_receive({
      mock_device.id,
      {
        capability = "thermostatHeatingSetpoint",
        component = "main",
        command = "setHeatingSetpoint",
        args = {},
        named_args = { setpoint = 21.5 },
      },
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      Thermostat.attributes.OccupiedHeatingSetpoint:write(mock_device, 2150),
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.thermostatHeatingSetpoint.heatingSetpoint({ value = 21.5, unit = "C" }))
    )
    test.wait_for_events()

    test.socket.capability:__queue_receive({
      mock_device.id,
      {
        capability = "thermostatHeatingSetpoint",
        component = "main",
        command = "setHeatingSetpoint",
        args = {},
        named_args = { setpoint = 68 },
      },
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      Thermostat.attributes.OccupiedHeatingSetpoint:write(mock_device, 2000),
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.thermostatHeatingSetpoint.heatingSetpoint({ value = 20.0, unit = "C" }))
    )
    test.wait_for_events()
  end,
  { min_api_version = 14 }
)

test.register_coroutine_test(
  "SONOFF TRV-ZBT starts Bluetooth pairing from the momentary component",
  function()
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "momentary", component = "bluetooth", command = "push", args = {} },
    })
    test.socket.zigbee:__expect_send({ mock_device.id, bluetooth_pairing_command(mock_device) })
    test.wait_for_events()
  end,
  { min_api_version = 14 }
)

test.register_coroutine_test(
  "SONOFF TRV-ZBT writes thermostat mode and refreshes required attributes",
  function()
    test.socket.capability:__queue_receive({
      mock_device.id,
      {
        capability = "thermostatMode",
        component = "main",
        command = "setThermostatMode",
        args = {},
        named_args = { mode = "auto" },
      },
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      Thermostat.attributes.SystemMode:write(mock_device, Thermostat.attributes.SystemMode.AUTO),
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.thermostatMode.thermostatMode.auto())
    )
    test.wait_for_events()

    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "refresh", component = "main", command = "refresh", args = {} },
    })
    for _, attribute in ipairs({
      Thermostat.attributes.LocalTemperature,
      Thermostat.attributes.OccupiedHeatingSetpoint,
      Thermostat.attributes.SystemMode,
      Thermostat.attributes.MinHeatSetpointLimit,
      Thermostat.attributes.MaxHeatSetpointLimit,
      PowerConfiguration.attributes.BatteryPercentageRemaining,
    }) do
      test.socket.zigbee:__expect_send({ mock_device.id, attribute:read(mock_device) })
    end
    test.wait_for_events()
  end,
  { min_api_version = 14 }
)

test.register_coroutine_test(
  "SONOFF TRV-ZBT configures reporting and cluster bindings",
  function()
    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      device_management.build_bind_request(mock_device, Thermostat.ID, zigbee_test_utils.mock_hub_eui),
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      device_management.build_bind_request(mock_device, PowerConfiguration.ID, zigbee_test_utils.mock_hub_eui),
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      device_management.build_bind_request(mock_device, SONOFF_CLUSTER, zigbee_test_utils.mock_hub_eui),
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      Thermostat.attributes.LocalTemperature:configure_reporting(mock_device, 10, 300, 50),
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      Thermostat.attributes.OccupiedHeatingSetpoint:configure_reporting(mock_device, 1, 600, 50),
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      Thermostat.attributes.SystemMode:configure_reporting(mock_device, 1, 600, 1),
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      PowerConfiguration.attributes.BatteryPercentageRemaining:configure_reporting(mock_device, 30, 21600, 5),
    })
    for _, attribute in ipairs({
      Thermostat.attributes.LocalTemperature,
      Thermostat.attributes.OccupiedHeatingSetpoint,
      Thermostat.attributes.SystemMode,
      Thermostat.attributes.MinHeatSetpointLimit,
      Thermostat.attributes.MaxHeatSetpointLimit,
      PowerConfiguration.attributes.BatteryPercentageRemaining,
    }) do
      test.socket.zigbee:__expect_send({ mock_device.id, attribute:read(mock_device) })
    end
    test.wait_for_events()
  end,
  { min_api_version = 14 }
)

test.run_registered_tests()
