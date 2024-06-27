require "integration_test"
-- Mock out globals
local test = require "integration_test"

-- clusters
local clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local PowerConfiguration = clusters.PowerConfiguration
local Thermostat = clusters.Thermostat

local ThermostatUIConfig = clusters.ThermostatUserInterfaceConfiguration

-- caps
local capabilities = require "st.capabilities"
local ThermostatMode = capabilities.thermostatMode

-- MFR specific
local MFG_CODE = 0x1246
local ETRV_WINDOW_OPEN_DETECTION_ATTR_ID = 0x4000
local EXTERNAL_WINDOW_OPEN_DETECTION = 0x4003
local THERMOSTAT_SETPOINT_CMD_ID = 0x40

-- utils
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local base64 = require "st.base64"
local t_utils = require "integration_test.utils"
local data_types = require "st.zigbee.data_types"

local mock_device = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("thermostat-popp.yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "D5X84YU",
        model = "eT093WRO",
        server_clusters = { 0x0000, 0x0001, 0x0003, 0x0020, 0x0201, 0x0204, 0x0B05 },
        client_clusters = { 0x000A, 0x0019 }
      }
    }
  }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device)
  zigbee_test_utils.init_noop_health_check_timer()
end

test.set_test_init_function(test_init)

-- TEST MODEL eT093WRO --

test.register_message_test(
  "Heating setpoint reports are handled.",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id,
        Thermostat.attributes.OccupiedHeatingSetpoint:build_test_attr_report(mock_device, 2500) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",
        capabilities.thermostatHeatingSetpoint.heatingSetpoint({ value = 25.0, unit = "C" }))
    }
  }
)

test.register_coroutine_test(
  "Setting thermostat heating setpoint should generate correct zigbee messages",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        { capability = "thermostatHeatingSetpoint", component = "main", command = "setHeatingSetpoint", args = { 27.5 } }
      }
    )
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        cluster_base.build_manufacturer_specific_command(mock_device, Thermostat.ID, THERMOSTAT_SETPOINT_CMD_ID, MFG_CODE, string.char(0x00, (math.floor(27.5 * 100) & 0xFF), (math.floor(27.5 * 100) >> 8)))
      }
    )
    test.wait_for_events()

    test.mock_time.advance_time(2)
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        Thermostat.attributes.OccupiedHeatingSetpoint:read(mock_device)
      }
    )
  end
)

test.register_coroutine_test(
  "External window open detection window open",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        { capability = "switch", component = "main", command = "on", args = {} }
      }
    )
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        cluster_base.write_manufacturer_specific_attribute(mock_device, Thermostat.ID, EXTERNAL_WINDOW_OPEN_DETECTION, MFG_CODE, data_types.Boolean, false)
      }
    )
  end
)

test.register_coroutine_test(
  "External window open detection window closed",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        { capability = "switch", component = "main", command = "off", args = {} }
      }
    )
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        cluster_base.write_manufacturer_specific_attribute(mock_device, Thermostat.ID, EXTERNAL_WINDOW_OPEN_DETECTION, MFG_CODE, data_types.Boolean, true)
      }
    )
  end
)

test.register_coroutine_test(
  "Configure should configure all necessary attributes",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
    test.socket.zigbee:__expect_send({ mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, PowerConfiguration.ID) })
    test.socket.zigbee:__expect_send({ mock_device.id,
      PowerConfiguration.attributes.BatteryVoltage:configure_reporting(mock_device, 30, 21600, 1) })

    test.socket.zigbee:__expect_send({ mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, Thermostat.ID) })
    test.socket.zigbee:__expect_send({ mock_device.id,
      Thermostat.attributes.LocalTemperature:configure_reporting(mock_device, 5, 300, 10) })
    test.socket.zigbee:__expect_send({ mock_device.id,
      Thermostat.attributes.OccupiedHeatingSetpoint:configure_reporting(mock_device, 5, 300, 50) })

    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)

test.register_message_test(
  "Driver should poll device at the inclusion",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_device.id, "added" }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",
        capabilities.thermostatMode.supportedThermostatModes(
          { ThermostatMode.thermostatMode.heat.NAME, ThermostatMode.thermostatMode.eco.NAME },
          { visibility = { displayed = false } }))
    }
  }
)

test.register_message_test(
  "Refresh should read all necessary attributes",
  {
    {
      channel = "capability",
      direction = "receive",
      message = { mock_device.id, { capability = "refresh", component = "main", command = "refresh", args = {} } }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = {
        mock_device.id,
        Thermostat.attributes.OccupiedHeatingSetpoint:read(mock_device)
      }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = {
        mock_device.id,
        Thermostat.attributes.LocalTemperature:read(mock_device)
      }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = {
        mock_device.id,
        ThermostatUIConfig.attributes.KeypadLockout:read(mock_device)
      }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = {
        mock_device.id,
        PowerConfiguration.attributes.BatteryVoltage:read(mock_device)
      }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = {
        mock_device.id,
        cluster_base.read_manufacturer_specific_attribute(mock_device, Thermostat.ID, ETRV_WINDOW_OPEN_DETECTION_ATTR_ID,
          MFG_CODE)
      }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = {
        mock_device.id,
        cluster_base.read_manufacturer_specific_attribute(mock_device, Thermostat.ID, EXTERNAL_WINDOW_OPEN_DETECTION,
          MFG_CODE)
      }
    }
  }
)

test.register_coroutine_test(
  "Check all preferences via infoChanged",
  function()
    local updates = {
      preferences = {
        tempOffset = -5, -- temparature offset of -5
        keypadLock = 1   --Lock
      }
    }
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.environment_update:__queue_receive({ "zigbee",
      { hub_zigbee_id = base64.encode(zigbee_test_utils.mock_hub_eui) } })
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed(updates))
    test.socket.zigbee:__expect_send({
      mock_device.id,
      cluster_base.write_attribute(mock_device,
        data_types.ClusterId(ThermostatUIConfig.ID),
        data_types.AttributeId(ThermostatUIConfig.attributes.KeypadLockout.ID),
        data_types.validate_or_build_type(0x0001, data_types.Enum8, "payload")
      )
    })
    test.wait_for_events()
    test.socket.zigbee:__queue_receive(
      {
        mock_device.id,
        Thermostat.attributes.LocalTemperature:build_test_attr_report(mock_device, 2500)
      }
    )
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.temperatureMeasurement.temperature({ value = 25.0, unit = "C" })))
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "Battery reports test cases",
  function()
    local battery_test_map = {
      ["D5X84YU"] = {
        [34] = 100,
        [32] = 100,
        [30] = 75,
        [28] = 50,
        [26] = 25,
        [24] = 0,
        [15] = 0
      }
    }

    for voltage, batt_perc in pairs(battery_test_map[mock_device:get_manufacturer()]) do
      test.socket.zigbee:__queue_receive({ mock_device.id,
        PowerConfiguration.attributes.BatteryVoltage:build_test_attr_report(mock_device, voltage) })
      test.socket.capability:__expect_send(mock_device:generate_test_message("main",
        capabilities.battery.battery(batt_perc)))
      test.wait_for_events()
    end
  end
)

test.register_coroutine_test(
  "Setting the thermostat mode to heat should generate the correct zigbee messages",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {
          component = "main",
          capability = capabilities.thermostatMode.ID,
          command = "heat",
          args = {}
        }
      }
    )
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        Thermostat.attributes.SystemMode:write(mock_device,
        Thermostat.attributes.SystemMode.HEAT)
      }
    )

    test.wait_for_events()
    test.mock_time.advance_time(2)
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        Thermostat.attributes.SystemMode:read(mock_device)
      }
    )
  end
)

test.register_coroutine_test(
  "Setting the thermostat mode to off should generate the correct zigbee messages",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {
          component = "main",
          capability = capabilities.thermostatMode.ID,
          command = "off",
          args = {}
        }
      }
    )
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        Thermostat.attributes.SystemMode:write(mock_device,
        Thermostat.attributes.SystemMode.OFF)
      }
    )

    test.wait_for_events()
    test.mock_time.advance_time(2)
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        Thermostat.attributes.SystemMode:read(mock_device)
      }
    )
  end
)


test.run_registered_tests()
