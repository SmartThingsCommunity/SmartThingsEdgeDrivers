-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

-- Mock out globals
local test = require "integration_test"
local t_utils = require "integration_test.utils"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local tuya_utils = require "tuya_utils"

local Basic = clusters.Basic

local mock_simple_device = test.mock_device.build_test_zigbee_device(
    {
      profile = t_utils.get_profile_definition("thermostat.yml"),
      zigbee_endpoints = {
        [1] = {
          id = 1,
          manufacturer = "_TZE284_fziifcxj",
          model = "TS0601",
          server_clusters = { 0xEF00 }
        }
      }
    }
)

zigbee_test_utils.prepare_zigbee_env_info()

local function test_init()
  test.mock_device.add_test_device(mock_simple_device)
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Handle doConfigure lifecycle event",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({ mock_simple_device.id, "doConfigure" })
    test.socket.zigbee:__expect_send({ mock_simple_device.id, tuya_utils.build_tuya_magic_spell_message(mock_simple_device) })
    test.socket.zigbee:__expect_send({ mock_simple_device.id, Basic.attributes.ApplicationVersion:configure_reporting(mock_simple_device, 30, 300, 1) })
    test.socket.zigbee:__expect_send({ mock_simple_device.id, zigbee_test_utils.build_bind_request(mock_simple_device, zigbee_test_utils.mock_hub_eui, Basic.ID) })
    mock_simple_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end,
  {}
)

test.register_coroutine_test(
  "Handle added lifecycle event",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_simple_device.id, "added" })

    test.socket.capability:__expect_send(
      mock_simple_device:generate_test_message(
        "main",
        capabilities.thermostatMode.supportedThermostatModes(
          {
            capabilities.thermostatMode.thermostatMode.antifreezing.NAME,
            capabilities.thermostatMode.thermostatMode.auto.NAME,
            capabilities.thermostatMode.thermostatMode.comfort.NAME,
            capabilities.thermostatMode.thermostatMode.eco.NAME,
            capabilities.thermostatMode.thermostatMode.off.NAME,
            capabilities.thermostatMode.thermostatMode.on.NAME,
          },
          {
            visibility = { displayed = false }
          }
        )
      )
    )

    test.socket.capability:__expect_send(
      mock_simple_device:generate_test_message(
        "main",
        capabilities.thermostatHeatingSetpoint.heatingSetpoint({value = 15.0, unit = "C"})
      )
    )

    test.socket.capability:__expect_send(
      mock_simple_device:generate_test_message(
        "main",
        capabilities.temperatureMeasurement.temperature({value = 20.0, unit = "C"})
      )
    )

    test.socket.capability:__expect_send(
      mock_simple_device:generate_test_message(
        "main",
        capabilities.thermostatMode.thermostatMode.auto()
      )
    )

    test.socket.capability:__expect_send(
      mock_simple_device:generate_test_message(
        "main",
        capabilities.battery.battery(100)
      )
    )
  end,
  {}
)

test.register_message_test(
    "Handle thermostatHeatingSetpoint setHeatingSetpoint",
    {
      {
        channel = "capability",
        direction = "receive",
        message = {
          mock_simple_device.id,
          {
            capability = "thermostatHeatingSetpoint",
            component = "main",
            command = "setHeatingSetpoint",
            args = {12.5}
          }
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = {
          mock_simple_device.id,
          tuya_utils.build_send_tuya_command(
            mock_simple_device,
            "\x04",
            tuya_utils.DP_TYPE_VALUE,
            "\x00\x00\x00\x7D",
            0x00
          )
        }
      }
    },
    {}
)

test.register_message_test(
    "Handle thermostatMode setThermostatMode (auto)",
    {
      {
        channel = "capability",
        direction = "receive",
        message = {
          mock_simple_device.id,
          {
            capability = "thermostatMode",
            component = "main",
            command = "setThermostatMode",
            args = {"auto"}
          }
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = {
          mock_simple_device.id,
          tuya_utils.build_send_tuya_command(
            mock_simple_device,
            "\x02",
            tuya_utils.DP_TYPE_ENUM,
            "\x00",
            0x00
          )
        }
      }
    },
    {}
)

test.register_message_test(
    "Handle thermostatMode setThermostatMode (off)",
    {
      {
        channel = "capability",
        direction = "receive",
        message = {
          mock_simple_device.id,
          {
            capability = "thermostatMode",
            component = "main",
            command = "setThermostatMode",
            args = {"off"}
          }
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = {
          mock_simple_device.id,
          tuya_utils.build_send_tuya_command(
            mock_simple_device,
            "\x02",
            tuya_utils.DP_TYPE_ENUM,
            "\x01",
            0x00
          )
        }
      }
    },
    {}
)

test.register_message_test(
    "Handle thermostatMode setThermostatMode (on)",
    {
      {
        channel = "capability",
        direction = "receive",
        message = {
          mock_simple_device.id,
          {
            capability = "thermostatMode",
            component = "main",
            command = "setThermostatMode",
            args = {"on"}
          }
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = {
          mock_simple_device.id,
          tuya_utils.build_send_tuya_command(
            mock_simple_device,
            "\x02",
            tuya_utils.DP_TYPE_ENUM,
            "\x02",
            0x00
          )
        }
      }
    },
    {}
)

test.register_message_test(
    "Handle thermostatMode setThermostatMode (comfort)",
    {
      {
        channel = "capability",
        direction = "receive",
        message = {
          mock_simple_device.id,
          {
            capability = "thermostatMode",
            component = "main",
            command = "setThermostatMode",
            args = {"comfort"}
          }
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = {
          mock_simple_device.id,
          tuya_utils.build_send_tuya_command(
            mock_simple_device,
            "\x02",
            tuya_utils.DP_TYPE_ENUM,
            "\x03",
            0x00
          )
        }
      }
    },
    {}
)

test.register_message_test(
    "Handle thermostatMode setThermostatMode (eco)",
    {
      {
        channel = "capability",
        direction = "receive",
        message = {
          mock_simple_device.id,
          {
            capability = "thermostatMode",
            component = "main",
            command = "setThermostatMode",
            args = {"eco"}
          }
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = {
          mock_simple_device.id,
          tuya_utils.build_send_tuya_command(
            mock_simple_device,
            "\x02",
            tuya_utils.DP_TYPE_ENUM,
            "\x04",
            0x00
          )
        }
      }
    },
    {}
)

test.register_message_test(
    "Handle thermostatMode setThermostatMode (antifreezing)",
    {
      {
        channel = "capability",
        direction = "receive",
        message = {
          mock_simple_device.id,
          {
            capability = "thermostatMode",
            component = "main",
            command = "setThermostatMode",
            args = {"antifreezing"}
          }
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = {
          mock_simple_device.id,
          tuya_utils.build_send_tuya_command(
            mock_simple_device,
            "\x02",
            tuya_utils.DP_TYPE_ENUM,
            "\x05",
            0x00
          )
        }
      }
    },
    {}
)

test.register_message_test(
    "Handle tuya cluster message report (heatingSetpoint)",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = {
          mock_simple_device.id,
          tuya_utils.build_test_attr_report(
            mock_simple_device,
            "\x04",
            tuya_utils.DP_TYPE_VALUE,
            "\x00\x00\x00\x7D",
            0x01
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_simple_device:generate_test_message(
          "main",
          capabilities.thermostatHeatingSetpoint.heatingSetpoint({value = 12.5, unit = "C"})
        )
      }
    },
    {}
)

test.register_message_test(
    "Handle tuya cluster message report (setThermostatMode, auto)",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = {
          mock_simple_device.id,
          tuya_utils.build_test_attr_report(
            mock_simple_device,
            "\x02",
            tuya_utils.DP_TYPE_ENUM,
            "\x00",
            0x01
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_simple_device:generate_test_message(
          "main",
          capabilities.thermostatMode.thermostatMode.auto()
        )
      }
    },
    {}
)

test.register_message_test(
    "Handle tuya cluster message report (setThermostatMode, off)",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = {
          mock_simple_device.id,
          tuya_utils.build_test_attr_report(
            mock_simple_device,
            "\x02",
            tuya_utils.DP_TYPE_ENUM,
            "\x01",
            0x01
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_simple_device:generate_test_message(
          "main",
          capabilities.thermostatMode.thermostatMode.off()
        )
      }
    },
    {}
)

test.register_message_test(
    "Handle tuya cluster message report (setThermostatMode, on)",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = {
          mock_simple_device.id,
          tuya_utils.build_test_attr_report(
            mock_simple_device,
            "\x02",
            tuya_utils.DP_TYPE_ENUM,
            "\x02",
            0x01
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_simple_device:generate_test_message(
          "main",
          capabilities.thermostatMode.thermostatMode.on()
        )
      }
    },
    {}
)

test.register_message_test(
    "Handle tuya cluster message report (setThermostatMode, comfort)",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = {
          mock_simple_device.id,
          tuya_utils.build_test_attr_report(
            mock_simple_device,
            "\x02",
            tuya_utils.DP_TYPE_ENUM,
            "\x03",
            0x01
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_simple_device:generate_test_message(
          "main",
          capabilities.thermostatMode.thermostatMode.comfort()
        )
      }
    },
    {}
)

test.register_message_test(
    "Handle tuya cluster message report (setThermostatMode, eco)",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = {
          mock_simple_device.id,
          tuya_utils.build_test_attr_report(
            mock_simple_device,
            "\x02",
            tuya_utils.DP_TYPE_ENUM,
            "\x04",
            0x01
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_simple_device:generate_test_message(
          "main",
          capabilities.thermostatMode.thermostatMode.eco()
        )
      }
    },
    {}
)

test.register_message_test(
    "Handle tuya cluster message report (setThermostatMode, antifreezing)",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = {
          mock_simple_device.id,
          tuya_utils.build_test_attr_report(
            mock_simple_device,
            "\x02",
            tuya_utils.DP_TYPE_ENUM,
            "\x05",
            0x01
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_simple_device:generate_test_message(
          "main",
          capabilities.thermostatMode.thermostatMode.antifreezing()
        )
      }
    },
    {}
)

test.run_registered_tests()
