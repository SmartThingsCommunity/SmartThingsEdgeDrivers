local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"
local data_types = require "st.zigbee.data_types"
local test = require "integration_test"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"


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
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "added lifecycle event",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.button.supportedButtonValues({ "pushed", "double", "held" }, { visibility = { displayed = false } })
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.button.numberOfButtons({ value = 1 }, { visibility = { displayed = false } })
      )
    )
  end
)

test.register_coroutine_test(
  "Reported button should be handled: pushed",
  function()
    local attr_report_data = {
      { 0x0055, data_types.Int16.ID, 0x0001}
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, 0x0012, attr_report_data, 0x110A)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.button.button.pushed({ state_change = true })))
  end
)

test.register_coroutine_test(
  "Reported button should be handled: double",
  function()
    local attr_report_data = {
      { 0x0055, data_types.Int16.ID, 0x0002}
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, 0x0012, attr_report_data, 0x110A)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.button.button.double({ state_change = true })))
  end
)

test.register_coroutine_test(
  "Reported button should be handled: held",
  function()
    local attr_report_data = {
      { 0x0055, data_types.Int16.ID, 0x0000}
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, 0x0012, attr_report_data, 0x110A)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.button.button.held({ state_change = true })))
  end
)

test.run_registered_tests()
