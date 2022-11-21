local test = require "integration_test"
local capabilities = require "st.capabilities"
local zw = require "st.zwave"
local zw_test_utils = require "integration_test.zwave_test_utils"
local Basic = (require "st.zwave.CommandClass.Basic")({ version = 1 })
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({ version = 2 })
local SwitchAll = (require "st.zwave.CommandClass.SwitchAll")({ version = 1 })
local t_utils = require "integration_test.utils"

-- supported comand classes
local sensor_endpoints = {
  {
    command_classes = {
      {value = zw.BASIC},
      {value = zw.SWITCH_ALL},
      {value = zw.SWITCH_BINARY},
    },
  },
  {
    command_classes = {
      {value = zw.BASIC},
      {value = zw.SWITCH_ALL},
      {value = zw.SWITCH_BINARY},
    }
  }
}

local mock_device = test.mock_device.build_test_zwave_device({
    profile = t_utils.get_profile_definition("switch-binary.yml"),
    zwave_endpoints = sensor_endpoints,
    zwave_manufacturer_id = 0x0312,
    zwave_product_type = 0x0221,
    zwave_product_id = 0x251C,
    label = "Inovelli Switch"
})

local function  test_init()
  test.mock_device.add_test_device(mock_device)
end
test.set_test_init_function(test_init)

local function prepare_metadata(device, endpoint, profile)
  local name = string.format("%s %d", device.label, endpoint)
  return {
    type = "EDGE_CHILD",
    label = name,
    profile = profile,
    parent_device_id = device.id,
    parent_assigned_child_key = string.format("%02X", endpoint),
  }
end

-- test.register_coroutine_test(
--   "added lifecycle event",
--   function()
--     local metadata_1 = prepare_metadata(mock_device, 1, "switch-binary")
--     local metadata_2 = prepare_metadata(mock_device, 2, "switch-binary")
--     mock_device:expect_device_create(metadata_1)
--     mock_device:expect_device_create(metadata_2)
--     test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
--           mock_device,
--           SwitchBinary:Get({},
--           {
--             encap = zw.ENCAP.AUTO,
--             src_channel = 0,
--             dst_channels = { }
--           })
--         ))

--     test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
--     end
-- )

test.register_coroutine_test(
  "driverSwitch lifecycle event",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "driverSwitched" })
    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })

    end
)

test.run_registered_tests()


