local test = require "integration_test"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"

local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"

local mock_device = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("thirdreality-multi-sensor.yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "Third Reality, Inc",
        model = "3RVS01031Z",
        server_clusters = { 0x0000, 0x0001, 0xFFF1 }
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
  "Acceleration report should be correctly handled",
  function()
    local acceleration_report_active = {
      { 0x0000, data_types.Bitmap8.ID, 1}
    }
    local acceleration_report_inactive = {
      { 0x0000, data_types.Bitmap8.ID, 0}
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, 0xFFF1, acceleration_report_active, 0x110A)
    })
    test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.accelerationSensor.acceleration.active()) )
    test.wait_for_events()
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, 0xFFF1, acceleration_report_inactive, 0x110A)
    })
    test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.accelerationSensor.acceleration.inactive()) )
  end
)

test.register_coroutine_test(
  "Acceleration report should be correctly handled",
  function()
    local attribute_def = {ID = 0x0000,base_type = {ID = data_types.Bitmap8.ID}, _cluster = {ID = 0xFFF1}}
    local utils = require "st.utils"
    print(utils.stringify_table(attribute_def))
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      cluster_base.build_test_read_attr_response(attribute_def, mock_device, 1)
    })
    test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.accelerationSensor.acceleration.active()) )
  end
)

test.register_coroutine_test(
  "Three Axis report should be correctly handled",
  function()
    local attr_report_data = {
      { 0x0001, data_types.Int16.ID, 200},
      { 0x0002, data_types.Int16.ID, 100},
      { 0x0003, data_types.Int16.ID, 300},
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, 0xFFF1, attr_report_data, 0x110A)
    })
    test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.threeAxis.threeAxis({200, 100, 300})) )
  end
)

test.run_registered_tests()
