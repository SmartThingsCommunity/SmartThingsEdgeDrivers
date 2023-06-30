local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"
local data_types = require "st.zigbee.data_types"
local test = require "integration_test"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"

local MULTISTATE_INPUT_CLUSTER = 0x0012
local ATTR_ID = 0x0055
local TR_HELD = 0
local TR_PUSHED = 1
local TR_DOUBLE = 2
local MFG_CODE = 0x110A

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

test.register_coroutine_test(
  "Reported button should be handled: pushed",
  function()
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, MULTISTATE_INPUT_CLUSTER, {
        { ATTR_ID, data_types.Uint16.ID, TR_PUSHED }
      }, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.button.button.pushed({ state_change = true })))
  end
)

test.register_coroutine_test(
  "Reported button should be handled: double",
  function()
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, MULTISTATE_INPUT_CLUSTER, {
        { ATTR_ID, data_types.Uint16.ID, TR_DOUBLE }
      }, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.button.button.double({ state_change = true })))
  end
)

test.register_coroutine_test(
  "Reported button should be handled: held",
  function()
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, MULTISTATE_INPUT_CLUSTER, {
        { ATTR_ID, data_types.Uint16.ID, TR_HELD }
      }, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.button.button.held({ state_change = true })))
  end
)

test.run_registered_tests()
