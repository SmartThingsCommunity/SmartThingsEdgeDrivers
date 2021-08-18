-- Mock out globals
local test = require "integration_test"
local clusters = require "st.zigbee.zcl.clusters"
local OnOff = clusters.OnOff
local Level = clusters.Level
local capabilities = require "st.capabilities"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local base64 = require "st.base64"
local zigbee_constants = require "st.zigbee.constants"
local fancySwitch = capabilities["your_namespace.fancySwitch"]
local fancy_switch_profile = {
  components = {
    main = {
      capabilities = {
        [fancySwitch.ID] = { id = fancySwitch.ID },
      },
      id = "main"
    }
  }
}

local mock_simple_device = test.mock_device.build_test_zigbee_device({ profile = fancy_switch_profile })

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_simple_device)
  zigbee_test_utils.init_noop_health_check_timer()
end

test.set_test_init_function(test_init)

test.register_message_test(
    "Fancy on should be generated",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_simple_device.id, OnOff.attributes.OnOff:build_test_attr_report(mock_simple_device,
                                                                                                true) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_simple_device:generate_test_message("main", fancySwitch.fancySwitch.On())
      }
    }
)

test.register_message_test(
    "Fancy off should be generated",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_simple_device.id, OnOff.attributes.OnOff:build_test_attr_report(mock_simple_device,
                                                                                                false) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_simple_device:generate_test_message("main", fancySwitch.fancySwitch.Off())
      }
    }
)

test.register_message_test(
    "fancyOn should be handled",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_simple_device.id, { capability = "your_namespace.fancySwitch", component = "main", command = "fancyOn", args = { } } }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_simple_device.id, OnOff.server.commands.On(mock_simple_device) }
      }
    }
)

test.register_message_test(
    "fancyOff should be handled",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_simple_device.id, { capability = "your_namespace.fancySwitch", component = "main", command = "fancyOff", args = { } } }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_simple_device.id, OnOff.server.commands.Off(mock_simple_device) }
      }
    }
)

test.register_message_test(
    "fancySet true should be handled",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_simple_device.id, { capability = "your_namespace.fancySwitch", component = "main", command = "fancySet", args = { "On" } } }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_simple_device.id, OnOff.server.commands.On(mock_simple_device) }
      }
    }
)

test.register_message_test(
    "fancySet false should be handled",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_simple_device.id, { capability = "your_namespace.fancySwitch", component = "main", command = "fancySet", args = { "Off" } } }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_simple_device.id, OnOff.server.commands.Off(mock_simple_device) }
      }
    }
)

test.run_registered_tests()
