-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


-- Mock out globals
local test = require "integration_test"
local clusters = require "st.zigbee.zcl.clusters"
local Basic = clusters.Basic
local OnOff = clusters.OnOff
local PowerConfiguration = clusters.PowerConfiguration
local capabilities = require "st.capabilities"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils = require "integration_test.utils"

local mock_device = test.mock_device.build_test_zigbee_device(
  { profile = t_utils.get_profile_definition("valve-battery-powerSource.yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "WAXMAN",
        model = "leakSMART Water Valve v2.10",
        server_clusters = {0x0000, 0x0001, 0x0006}
      }
    }
  }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device)end

test.set_test_init_function(test_init)

test.register_message_test(
    "OnOff(on) reporting should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, OnOff.attributes.OnOff:build_test_attr_report(mock_device,
                                                                                                true) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.valve.valve.open())
      }
    },
    {
       min_api_version = 19
    }
)


test.register_message_test(
    "OnOff(off) reporting should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, OnOff.attributes.OnOff:build_test_attr_report(mock_device,
                                                                                                false) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.valve.valve.closed())
      }
    },
    {
       min_api_version = 19
    }
)

test.register_message_test(
    "Battery percentage report should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, PowerConfiguration.attributes.BatteryPercentageRemaining:build_test_attr_report(mock_device, 55) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.battery.battery(28))
      }
    },
    {
       min_api_version = 19
    }
)

test.register_message_test(
    "PowerSource(unknown) reporting should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, Basic.attributes.PowerSource:build_test_attr_report(mock_device,
                                                                                                0x00) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.powerSource.powerSource.unknown())
      }
    },
    {
       min_api_version = 19
    }
)

test.register_message_test(
    "PowerSource(mains) reporting should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, Basic.attributes.PowerSource:build_test_attr_report(mock_device,
                                                                                                0x01) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.powerSource.powerSource.mains())
      }
    },
    {
       min_api_version = 19
    }
)

test.register_message_test(
    "PowerSource(battery) reporting should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, Basic.attributes.PowerSource:build_test_attr_report(mock_device,
                                                                                                0x03) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.powerSource.powerSource.battery())
      }
    },
    {
       min_api_version = 19
    }
)

test.register_message_test(
    "PowerSource(dc) reporting should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, Basic.attributes.PowerSource:build_test_attr_report(mock_device,
                                                                                                0x04) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.powerSource.powerSource.dc())
      }
    },
    {
       min_api_version = 19
    }
)

test.register_message_test(
    "Capability(valve) command(open) on should be handled",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_device.id, { capability = "valve", component = "main", command = "open", args = { } } }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_device.id, OnOff.server.commands.On(mock_device) }
      }
    },
    {
       min_api_version = 19
    }
)

test.register_message_test(
    "Capability(valve) command(off) on should be handled",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_device.id, { capability = "valve", component = "main", command = "close", args = { } } }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_device.id, OnOff.server.commands.Off(mock_device) }
      }
    },
    {
       min_api_version = 19
    }
)

test.register_coroutine_test(
    "doConfigure lifecycle should configure device",
    function ()
      test.socket.zigbee:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device)
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        OnOff.attributes.OnOff:read(mock_device)
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        Basic.attributes.PowerSource:read(mock_device)
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, PowerConfiguration.ID)
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        PowerConfiguration.attributes.BatteryPercentageRemaining:configure_reporting(mock_device, 30, 21600, 1)
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, OnOff.ID)
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        OnOff.attributes.OnOff:configure_reporting(mock_device, 0, 600, 0)
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, Basic.ID)
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        Basic.attributes.PowerSource:configure_reporting(mock_device, 5, 600)
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
        channel = "capability",
        direction = "receive",
        message = {
          mock_device.id,
          { capability = "refresh", component = "main", command = "refresh", args = {} }
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = {
          mock_device.id,
          Basic.attributes.PowerSource:read(mock_device)
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = {
          mock_device.id,
          OnOff.attributes.OnOff:read(mock_device)
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = {
          mock_device.id,
          PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device)
        }
      }
    },
    {
      inner_block_ordering = "relaxed"
    },
    {
       min_api_version = 19
    }
)

test.register_message_test(
    "Device added event should refresh device states",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_device.id, "added" },
      },
      {
        channel = "zigbee",
        direction = "send",
        message = {
          mock_device.id,
          Basic.attributes.PowerSource:read(mock_device)
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = {
          mock_device.id,
          OnOff.attributes.OnOff:read(mock_device)
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = {
          mock_device.id,
          PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device)
        }
      }
    },
    {
      inner_block_ordering = "relaxed"
    },
    {
       min_api_version = 19
    }
)

test.run_registered_tests()
