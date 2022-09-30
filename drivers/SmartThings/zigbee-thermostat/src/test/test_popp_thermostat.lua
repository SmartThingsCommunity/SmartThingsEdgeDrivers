require "integration_test"
-- Mock out globals
local test = require "integration_test"
local utils = require "st.utils"
local test_utils = require "integration_test.utils"

-- clusters
local clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local PowerConfiguration = clusters.PowerConfiguration
local Thermostat = clusters.Thermostat

local ThermostatUIConfig = clusters.ThermostatUserInterfaceConfiguration

-- caps
local capabilities = require "st.capabilities"

-- MFR specific
local MFG_CODE = 0x1246
local VIEWING_DIRECTION_ATTR_ID = 0x4000
--[[ local ETRV_ORIENTATION_ATTR_ID = 0x4014
local REGULATION_SETPOINT_OFFSET_ATTR_ID = 0x404B
local WINDOW_OPEN_FEATURE_ATTR_ID = 0x4051
local ETRV_WINDOW_OPEN_DETECTION_ATTR_ID = 0x4000 ]]

local HeatingMode = capabilities["preparestream40760.heatMode"]
--local WindowOpenDetectionCap = capabilities["preparestream40760.windowOpenDetection"]

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
        server_clusters = { 0x0000, 0x0001, 0x0201, 0x0204 }
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

test.register_message_test(
  "Supported modes reports are handled",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id,
        Thermostat.attributes.ControlSequenceOfOperation:build_test_attr_report(mock_device, 0x02) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",
        capabilities.thermostatMode.supportedThermostatModes({ "heat" }))
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
        { capability = "thermostatHeatingSetpoint", component = "main", command = "setHeatingSetpoint", args = { 27 } }
      }
    )
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        Thermostat.attributes.OccupiedHeatingSetpoint:write(mock_device, 2700)
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
  "Configure should configure all necessary attributes",
  function()
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })

    test.socket.zigbee:__expect_send({ mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, Thermostat.ID) })
    test.socket.zigbee:__expect_send({ mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, PowerConfiguration.ID) })

    test.socket.zigbee:__expect_send({ mock_device.id,
      Thermostat.attributes.LocalTemperature:configure_reporting(mock_device, 5, 300, 10) })
    test.socket.zigbee:__expect_send({ mock_device.id,
      Thermostat.attributes.OccupiedHeatingSetpoint:configure_reporting(mock_device, 5, 300, 50) })
    test.socket.zigbee:__expect_send({ mock_device.id,
      PowerConfiguration.attributes.BatteryVoltage:configure_reporting(mock_device, 30, 21600, 1) })

    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)

test.register_coroutine_test(
  "Configure should configure all necessary attributes",
  function()
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })

    test.socket.zigbee:__expect_send({ mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, Thermostat.ID) })
    test.socket.zigbee:__expect_send({ mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, PowerConfiguration.ID) })

    test.socket.zigbee:__expect_send({ mock_device.id,
      Thermostat.attributes.LocalTemperature:configure_reporting(mock_device, 5, 300, 10) })
    test.socket.zigbee:__expect_send({ mock_device.id,
      Thermostat.attributes.OccupiedHeatingSetpoint:configure_reporting(mock_device, 5, 300, 50) })
    test.socket.zigbee:__expect_send({ mock_device.id,
      PowerConfiguration.attributes.BatteryVoltage:configure_reporting(mock_device, 30, 21600, 1) })

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
        Thermostat.attributes.ControlSequenceOfOperation:read(mock_device)
      }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = {
        mock_device.id,
        Thermostat.attributes.ThermostatRunningState:read(mock_device)
      }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = {
        mock_device.id,
        Thermostat.attributes.ThermostatRunningMode:read(mock_device)
      }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = {
        mock_device.id,
        Thermostat.attributes.SystemMode:read(mock_device)
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
        PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device)
      }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = {
        mock_device.id,
        cluster_base.read_manufacturer_specific_attribute(mock_device, Thermostat.ID, VIEWING_DIRECTION_ATTR_ID, MFG_CODE)
      }
    }
  }
)

test.register_coroutine_test(
  "Driver should poll device at the inclusion",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      Thermostat.attributes.OccupiedHeatingSetpoint:read(mock_device)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      Thermostat.attributes.LocalTemperature:read(mock_device)
    })

    test.socket.zigbee:__expect_send({
      mock_device.id,
      Thermostat.attributes.ControlSequenceOfOperation:read(mock_device)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      Thermostat.attributes.ThermostatRunningState:read(mock_device)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      Thermostat.attributes.ThermostatRunningMode:read(mock_device)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      Thermostat.attributes.SystemMode:read(mock_device)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      ThermostatUIConfig.attributes.KeypadLockout:read(mock_device)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      PowerConfiguration.attributes.BatteryVoltage:read(mock_device)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device)
    })
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.read_manufacturer_specific_attribute(mock_device, Thermostat.ID, VIEWING_DIRECTION_ATTR_ID, MFG_CODE)
    })


    test.wait_for_events()

    test.socket.zigbee:__set_channel_ordering("relaxed")
  end
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
        Thermostat.attributes.ControlSequenceOfOperation:read(mock_device)
      }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = {
        mock_device.id,
        Thermostat.attributes.ThermostatRunningState:read(mock_device)
      }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = {
        mock_device.id,
        Thermostat.attributes.ThermostatRunningMode:read(mock_device)
      }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = {
        mock_device.id,
        Thermostat.attributes.SystemMode:read(mock_device)
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
        PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device)
      }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = {
        mock_device.id,
        cluster_base.read_manufacturer_specific_attribute(mock_device, Thermostat.ID, VIEWING_DIRECTION_ATTR_ID, MFG_CODE)
      }
    }
  }
)

test.register_coroutine_test(
  "Handle tempOffset preference infochanged",
  function()
    test.socket.environment_update:__queue_receive({ "zigbee",
      { hub_zigbee_id = base64.encode(zigbee_test_utils.mock_hub_eui) } })
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({ preferences = { tempOffset = -5 } }))
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

--[[ test.register_coroutine_test(
  "Check all preferences via infoChanged",
  function()
    local updates = {
      preferences = {
        keypadLock = 1, --Lock
        viewingDirection = 1, -- 180°
        eTRVOrientation = true, -- vertical
        regulationSetPointOffset = 1.5, -- offset = -1.5
        windowOpenFeature = false -- disabled
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
        data_types.validate_or_build_type(0x01, data_types.Enum8, "payload")
      )
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device,
        ThermostatUIConfig.ID,
        VIEWING_DIRECTION_ATTR_ID,
        MFG_CODE,
        data_types.Enum8,
        0x01)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device,
        Thermostat.ID,
        ETRV_ORIENTATION_ATTR_ID,
        MFG_CODE,
        data_types.Boolean,
        true)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device,
        Thermostat.ID,
        REGULATION_SETPOINT_OFFSET_ATTR_ID,
        MFG_CODE,
        data_types.Int8,
        15)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device,
        Thermostat.ID,
        WINDOW_OPEN_FEATURE_ATTR_ID,
        MFG_CODE,
        data_types.Boolean,
        false)
    })
  end
) ]]

--[[ test.register_message_test(
  "HeatingMode 'fast' should be handled",
  {
    {
      channel = "capability",
      direction = "receive",
      message = { mock_device.id,
        { capability = "preparestream40760.heatMode", component = "main", command = "setSetpointMode", args = { "fast" } } }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = { mock_device.id, HeatingMode.setpointMode.fast(mock_device) }
    }
  }
)

test.register_message_test(
  "HeatingMode 'eco' should be handled",
  {
    {
      channel = "capability",
      direction = "receive",
      message = { mock_device.id,
        { capability = "preparestream40760.heatMode", component = "main", command = "setSetpointMode", args = { "eco" } } }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = { mock_device.id, HeatingMode.setpointMode.eco(mock_device) }
    }
  }
) ]]

test.run_registered_tests()
