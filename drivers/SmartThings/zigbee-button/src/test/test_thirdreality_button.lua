local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local t_utils = require "integration_test.utils"
local test = require "integration_test"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"

local button = capabilities.button

local mock_device = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("one-button-battery.yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "Third Reality, Inc",
        model = "3RSB22BZ",
        server_clusters = { 0x0000, 0x0001, 0x0012 }
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
    "Reported button should be handled: pushed",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, 0x0001:build_test_attr_report(mock_device, true) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", button_attr.pushed({ state_change = true }))
      }
    }
)

test.register_message_test(
    "Reported button should be handled: double",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, 0x0002:build_test_attr_report(mock_device, true) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", button_attr.double({ state_change = true }))
      }
    }
)

test.register_message_test(
    "Reported button should be handled: held",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, 0x0000:build_test_attr_report(mock_device, true) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", button_attr.held({ state_change = true }))
      }
    }
)

test.run_registered_tests()
