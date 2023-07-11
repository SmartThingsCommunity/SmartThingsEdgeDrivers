local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"
local test = require "integration_test"
local data_types = require "st.zigbee.data_types"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"

local mock_device = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("on-off-level-rgbw-motion-illuminance-sensor"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "Third Reality, Inc",
        model = "3RSNL02043Z",
        server_clusters = { 0x0000, 0xFC00 }
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
  "Reported motion should be handled: active",
  function()
    local attr_report_data = {
      { 0x0002, data_types.Int16.ID, 0x0001}
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, 0xFC00, attr_report_data, 0x110A)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.motionSensor.motion.active()))
  end
)

test.register_coroutine_test(
  "Reported motion should be handled: inactive",
  function()
    local attr_report_data = {
      { 0x0002, data_types.Int16.ID, 0x0000}
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, 0xFC00, attr_report_data, 0x110A)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.motionSensor.motion.inactive()))
  end
)

test.run_registered_tests()
