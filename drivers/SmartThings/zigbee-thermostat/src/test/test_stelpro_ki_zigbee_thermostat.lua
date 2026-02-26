-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

-- Mock out globals
local test = require "integration_test"
local clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils = require "integration_test.utils"

local Thermostat = clusters.Thermostat
local ThermostatSystemMode = Thermostat.attributes.SystemMode
local ThermostatUserInterfaceConfiguration = clusters.ThermostatUserInterfaceConfiguration

local capabilities = require "st.capabilities"
local ThermostatMode = capabilities.thermostatMode
local ThermostatOperatingState  = capabilities.thermostatOperatingState

local RAW_TEMP = "raw_temp"
local STORED_SYSTEM_MODE = "stored_system_mode"

local MFR_SETPOINT_MODE_ATTTRIBUTE = 0x401C
local MFG_CODE = 0x1185

local mock_device = test.mock_device.build_test_zigbee_device(
    {
      profile = t_utils.get_profile_definition("thermostat-temperature-temperaturealarm.yml"),
      zigbee_endpoints = {
        [1] = {
          id = 1,
          manufacturer = "Stelpro",
          model = "STZB402+",
          server_clusters = {0x0000, 0x0003, 0x0004, 0x0201, 0x0204},
          client_clusters = {0x0402}
        }
      }
    }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device)end

test.set_test_init_function(test_init)

test.register_message_test(
  "LocalTemperature atttribute reports using the thermostat cluster should be handled",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, Thermostat.attributes.LocalTemperature:build_test_attr_report(mock_device, 0x7ffd) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.temperatureAlarm.temperatureAlarm.freeze())
    }
  },
  {
     min_api_version = 19
  }
)

test.register_message_test(
  "LocalTemperature atttribute reports using the thermostat cluster should be handled",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, Thermostat.attributes.LocalTemperature:build_test_attr_report(mock_device, 0x7fff) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.temperatureAlarm.temperatureAlarm.heat())
    }
  },
  {
     min_api_version = 19
  }
)

test.register_message_test(
  "LocalTemperature atttribute reports using the thermostat cluster should be handled",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, Thermostat.attributes.LocalTemperature:build_test_attr_report(mock_device, 5500) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.temperatureAlarm.temperatureAlarm.heat())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.temperatureMeasurement.temperature({value = 55.0, unit = "C"}))
    }
  },
  {
     min_api_version = 19
  }
)

test.register_message_test(
  "LocalTemperature atttribute reports using the thermostat cluster should be handled",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, Thermostat.attributes.LocalTemperature:build_test_attr_report(mock_device, -100) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.temperatureAlarm.temperatureAlarm.freeze())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.temperatureMeasurement.temperature({value = -1.0, unit = "C"}))
    }
  },
  {
     min_api_version = 19
  }
)

test.register_message_test(
  "LocalTemperature atttribute reports using the thermostat cluster should be handled",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, Thermostat.attributes.LocalTemperature:build_test_attr_report(mock_device, 1500) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.temperatureAlarm.temperatureAlarm.cleared())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.temperatureMeasurement.temperature({value = 15.0, unit = "C"}))
    }
  },
  {
     min_api_version = 19
  }
)

test.register_message_test(
  "OccupiedHeatingSetpoint atttribute reports using the thermostat cluster should be handled",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, Thermostat.attributes.OccupiedHeatingSetpoint:build_test_attr_report(mock_device, 2500) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.thermostatHeatingSetpoint.heatingSetpoint({value = 25.0, unit = "C"}))
    }
  },
  {
     min_api_version = 19
  }
)

test.register_message_test(
  "SystemMode atttribute reports using the thermostat cluster should be handled",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, Thermostat.attributes.SystemMode:build_test_attr_report(mock_device, ThermostatSystemMode.OFF) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", ThermostatMode.thermostatMode.off())
    }
  },
  {
     min_api_version = 19
  }
)

test.register_message_test(
  "SystemMode atttribute reports using the thermostat cluster should be handled",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, Thermostat.attributes.SystemMode:build_test_attr_report(mock_device, ThermostatSystemMode.HEAT) }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = {
        mock_device.id,
        zigbee_test_utils.build_attribute_read(mock_device, Thermostat.ID, {MFR_SETPOINT_MODE_ATTTRIBUTE}, MFG_CODE)
      }
    }
  },
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "PIHeatingDemand atttribute reports using the thermostat cluster should be handled",
  function()
    mock_device:set_field(STORED_SYSTEM_MODE, ThermostatSystemMode.OFF, {persist = true})
    mock_device:set_field(RAW_TEMP, 2500, {persist = true})
    mock_device.datastore:save()

    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.zigbee:__queue_receive({
        mock_device.id,
        Thermostat.attributes.OccupiedHeatingSetpoint:build_test_attr_report(mock_device, 1500)
      })
    test.socket.zigbee:__expect_send({
        mock_device.id,
        Thermostat.attributes.PIHeatingDemand:read(mock_device)
      })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.thermostatHeatingSetpoint.heatingSetpoint({ value = 15.0, unit = "C" })))

    test.wait_for_events()
    test.mock_time.advance_time(2)

    test.socket.zigbee:__queue_receive({
        mock_device.id,
        Thermostat.attributes.PIHeatingDemand:build_test_attr_report(mock_device, 0)
      })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", ThermostatOperatingState.thermostatOperatingState("idle")))
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Mfr-specific setpoint reports should be handled",
  function()
    test.socket.zigbee:__queue_receive({
        mock_device.id,
        Thermostat.attributes.SystemMode:build_test_attr_report(mock_device, ThermostatSystemMode.HEAT)
      })
    test.socket.zigbee:__expect_send({
        mock_device.id,
        zigbee_test_utils.build_attribute_read(mock_device, Thermostat.ID, {MFR_SETPOINT_MODE_ATTTRIBUTE}, MFG_CODE)
      })
    test.socket.zigbee:__queue_receive({
        mock_device.id,
        zigbee_test_utils.build_attribute_report(mock_device, Thermostat.ID,
            {{ MFR_SETPOINT_MODE_ATTTRIBUTE, data_types.Uint16.ID, 0x04}}, MFG_CODE)
      })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", ThermostatMode.thermostatMode.heat()))
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Setting thermostat mode to off should generate correct zigbee messages",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.socket.capability:__queue_receive({
        mock_device.id,
        { capability = "thermostatMode", command = "off", args = {} }
      })
    test.socket.zigbee:__expect_send({
        mock_device.id,
        Thermostat.attributes.SystemMode:write(mock_device, ThermostatSystemMode.OFF)
      })
    test.socket.zigbee:__expect_send({
        mock_device.id,
        cluster_base.write_manufacturer_specific_attribute(mock_device, Thermostat.ID, MFR_SETPOINT_MODE_ATTTRIBUTE, MFG_CODE, data_types.Enum8, 0x00)
      })
    test.wait_for_events()

    test.mock_time.advance_time(2)
    test.socket.zigbee:__expect_send({
        mock_device.id,
        Thermostat.attributes.SystemMode:read(mock_device)
      })
    test.socket.zigbee:__expect_send({
        mock_device.id,
        cluster_base.read_manufacturer_specific_attribute(mock_device, Thermostat.ID, MFR_SETPOINT_MODE_ATTTRIBUTE, MFG_CODE)
      })
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Setting thermostat mode to heat should generate correct zigbee messages",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.socket.capability:__queue_receive({
        mock_device.id,
        { capability = "thermostatMode", command = "heat", args = {} }
      })
    test.socket.zigbee:__expect_send({
        mock_device.id,
        Thermostat.attributes.SystemMode:write(mock_device, ThermostatSystemMode.HEAT)
      })
    test.socket.zigbee:__expect_send({
        mock_device.id,
        cluster_base.write_manufacturer_specific_attribute(mock_device, Thermostat.ID, MFR_SETPOINT_MODE_ATTTRIBUTE, MFG_CODE, data_types.Enum8, 0x04)
      })
    test.wait_for_events()

    test.mock_time.advance_time(2)
    test.socket.zigbee:__expect_send({
        mock_device.id,
        Thermostat.attributes.SystemMode:read(mock_device)
      })
    test.socket.zigbee:__expect_send({
        mock_device.id,
        cluster_base.read_manufacturer_specific_attribute(mock_device, Thermostat.ID, MFR_SETPOINT_MODE_ATTTRIBUTE, MFG_CODE)
      })
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
    "Configure should configure all necessary attributes",
    function ()
      test.socket.zigbee:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle:__queue_receive({mock_device.id, "doConfigure"})
      test.socket.zigbee:__expect_send({
          mock_device.id,
          zigbee_test_utils.build_bind_request(
              mock_device, zigbee_test_utils.mock_hub_eui, Thermostat.ID
            )
        })
      test.socket.zigbee:__expect_send({
          mock_device.id,
          Thermostat.attributes.LocalTemperature:configure_reporting(
              mock_device, 10, 60, 50
            )
        })
      test.socket.zigbee:__expect_send({
          mock_device.id,
          Thermostat.attributes.OccupiedHeatingSetpoint:configure_reporting(
              mock_device, 1, 600, 50
            )
        })
      test.socket.zigbee:__expect_send({
          mock_device.id,
          Thermostat.attributes.SystemMode:configure_reporting(
              mock_device, 1, 0, 1
            )
        })
      test.socket.zigbee:__expect_send({
          mock_device.id,
          Thermostat.attributes.PIHeatingDemand:configure_reporting(
              mock_device, 1, 3600, 1
            )
        })
      test.socket.zigbee:__expect_send({
          mock_device.id,
          cluster_base.configure_reporting(
              mock_device,
              data_types.ClusterId(Thermostat.ID), MFR_SETPOINT_MODE_ATTTRIBUTE, data_types.Enum8.ID, 1, 0, 1
            )
        })
      test.socket.zigbee:__expect_send({
          mock_device.id,
          ThermostatUserInterfaceConfiguration.attributes.TemperatureDisplayMode:configure_reporting(
              mock_device, 1, 0, 1
            )
        })
      test.socket.zigbee:__expect_send({
          mock_device.id,
          ThermostatUserInterfaceConfiguration.attributes.KeypadLockout:configure_reporting(
              mock_device, 1, 0, 1
            )
        })

      -- Now for the do_refresh call from do_configure
      test.socket.zigbee:__expect_send({
          mock_device.id,
          Thermostat.attributes.LocalTemperature:read(mock_device)
        })
      test.socket.zigbee:__expect_send({
          mock_device.id,
          Thermostat.attributes.OccupiedHeatingSetpoint:read(mock_device)
        })
      test.socket.zigbee:__expect_send({
          mock_device.id,
          Thermostat.attributes.PIHeatingDemand:read(mock_device)
        })
      test.socket.zigbee:__expect_send({
          mock_device.id,
          Thermostat.attributes.SystemMode:read(mock_device)
        })
      test.socket.zigbee:__expect_send({
          mock_device.id,
          ThermostatUserInterfaceConfiguration.attributes.TemperatureDisplayMode:read(mock_device)
        })
      test.socket.zigbee:__expect_send({
          mock_device.id,
          ThermostatUserInterfaceConfiguration.attributes.KeypadLockout:read(mock_device)
        })
      test.socket.zigbee:__expect_send({
          mock_device.id,
          cluster_base.read_manufacturer_specific_attribute(mock_device, Thermostat.ID, MFR_SETPOINT_MODE_ATTTRIBUTE, MFG_CODE)
        })

      mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    end,
    {
       min_api_version = 19
    }
)

test.register_message_test(
  "Refresh should read all necessary attributes",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = {mock_device.id, "added"}
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.thermostatMode.supportedThermostatModes({ "off", "heat", "eco" }, { visibility = { displayed = false } }))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.temperatureAlarm.temperatureAlarm.cleared())
    },
    {
      channel = "capability",
      direction = "receive",
      message = {mock_device.id, {capability = "refresh", component = "main", command = "refresh", args = {}}}
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
        Thermostat.attributes.OccupiedHeatingSetpoint:read(mock_device)
      }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = {
        mock_device.id,
        Thermostat.attributes.PIHeatingDemand:read(mock_device)
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
        ThermostatUserInterfaceConfiguration.attributes.TemperatureDisplayMode:read(mock_device)
      }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = {
        mock_device.id,
        ThermostatUserInterfaceConfiguration.attributes.KeypadLockout:read(mock_device)
      }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = {
        mock_device.id,
        cluster_base.read_manufacturer_specific_attribute(mock_device, Thermostat.ID, MFR_SETPOINT_MODE_ATTTRIBUTE, MFG_CODE)
      }
    },
  },
  {
     min_api_version = 19
  }
)

test.register_coroutine_test("Setting the heating setpoint should generate the appropriate messages", function()
  test.socket.capability:__queue_receive({mock_device.id, {
    component = "main",
    capability = capabilities.thermostatHeatingSetpoint.ID,
    command = "setHeatingSetpoint",
    args = {21}
  }})
  test.socket.zigbee:__expect_send({mock_device.id,
                                    Thermostat.attributes.OccupiedHeatingSetpoint:write(mock_device, 2100)})
  test.socket.zigbee:__expect_send({
      mock_device.id,
      Thermostat.attributes.OccupiedHeatingSetpoint:read(mock_device)
    })
  test.socket.zigbee:__expect_send({
      mock_device.id,
      Thermostat.attributes.PIHeatingDemand:read(mock_device)
    })
end,
{
   min_api_version = 19
}
)

test.register_coroutine_test(
  "Setting thermostat mode to eco should generate correct zigbee messages",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.socket.capability:__queue_receive({ mock_device.id,
      { capability = "thermostatMode", component = "main", command = "setThermostatMode", args = {"eco"}}
    })
    test.socket.zigbee:__expect_send({
        mock_device.id,
        Thermostat.attributes.SystemMode:write(mock_device, ThermostatSystemMode.HEAT)
      })
    test.socket.zigbee:__expect_send({
        mock_device.id,
        cluster_base.write_manufacturer_specific_attribute(mock_device, Thermostat.ID, MFR_SETPOINT_MODE_ATTTRIBUTE, MFG_CODE, data_types.Enum8, 0x05)
      })
    test.wait_for_events()

    test.mock_time.advance_time(2)
    test.socket.zigbee:__expect_send({
        mock_device.id,
        Thermostat.attributes.SystemMode:read(mock_device)
      })
    test.socket.zigbee:__expect_send({
        mock_device.id,
        cluster_base.read_manufacturer_specific_attribute(mock_device, Thermostat.ID, MFR_SETPOINT_MODE_ATTTRIBUTE, MFG_CODE)
      })
  end,
  {
     min_api_version = 19
  }
)

test.run_registered_tests()
