-- Copyright 2025 SmartThings
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

local test = require "integration_test"
local t_utils = require "integration_test.utils"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local data_types = require "st.zigbee.data_types"
local cluster_base = require "st.zigbee.cluster_base"
local utils = require "st.utils"

-- Device endpoints with supported clusters
local inovelli_vzm32_sn_endpoints = {
  [1] = {
    id = 1,
    manufacturer = "Inovelli",
    model = "VZM32-SN",
    server_clusters = {0x0006, 0x0008} -- OnOff, Level
  }
}

local mock_inovelli_vzm32_sn = test.mock_device.build_test_zigbee_device({
  profile = t_utils.get_profile_definition("inovelli-vzm32-sn.yml"),
  zigbee_endpoints = inovelli_vzm32_sn_endpoints,
  fingerprinted_endpoint_id = 0x01,
  label = "Inovelli VZM32-SN"
})

zigbee_test_utils.prepare_zigbee_env_info()

local function test_init()
  test.mock_device.add_test_device(mock_inovelli_vzm32_sn)
end
test.set_test_init_function(test_init)

-- Test parameter1 preference change
test.register_coroutine_test(
  "parameter1 preference should send configuration command",
  function()
    local new_param_value = 50
    test.socket.device_lifecycle:__queue_receive(mock_inovelli_vzm32_sn:generate_info_changed({preferences = {parameter1 = new_param_value}}))

    test.socket.zigbee:__expect_send({
      mock_inovelli_vzm32_sn.id,
      cluster_base.write_manufacturer_specific_attribute(
        mock_inovelli_vzm32_sn,
        0xFC31, -- PRIVATE_CLUSTER_ID
        1,      -- parameter_number
        0x122F, -- MFG_CODE
        data_types.Uint8,
        new_param_value
      )
    })
  end
)

-- Test parameter9 preference change
test.register_coroutine_test(
  "parameter9 preference should send configuration command",
  function()
    local new_param_value = 10
    local expected_value = utils.round(new_param_value / 100 * 254)
    test.socket.device_lifecycle:__queue_receive(mock_inovelli_vzm32_sn:generate_info_changed({preferences = {parameter9 = new_param_value}}))

    test.socket.zigbee:__expect_send({
      mock_inovelli_vzm32_sn.id,
      cluster_base.write_manufacturer_specific_attribute(
        mock_inovelli_vzm32_sn,
        0xFC31, -- PRIVATE_CLUSTER_ID
        9,      -- parameter_number
        0x122F, -- MFG_CODE
        data_types.Uint8,
        expected_value
      )
    })
  end
)

-- Test parameter52 preference change
test.register_coroutine_test(
  "parameter52 preference should send configuration command",
  function()
    local new_param_value = true
    test.socket.device_lifecycle:__queue_receive(mock_inovelli_vzm32_sn:generate_info_changed({preferences = {parameter52 = new_param_value}}))

    test.socket.zigbee:__expect_send({
      mock_inovelli_vzm32_sn.id,
      cluster_base.write_manufacturer_specific_attribute(
        mock_inovelli_vzm32_sn,
        0xFC31, -- PRIVATE_CLUSTER_ID
        52,     -- parameter_number
        0x122F, -- MFG_CODE
        data_types.Boolean,
        new_param_value
      )
    })
  end
)

-- Test parameter258 preference change
test.register_coroutine_test(
  "parameter258 preference should send configuration command",
  function()
    local new_param_value = false
    test.socket.device_lifecycle:__queue_receive(mock_inovelli_vzm32_sn:generate_info_changed({preferences = {parameter258 = new_param_value}}))

    test.socket.zigbee:__expect_send({
      mock_inovelli_vzm32_sn.id,
      cluster_base.write_manufacturer_specific_attribute(
        mock_inovelli_vzm32_sn,
        0xFC31, -- PRIVATE_CLUSTER_ID
        258,    -- parameter_number
        0x122F, -- MFG_CODE
        data_types.Boolean,
        new_param_value
      )
    })
  end
)

-- Test notificationChild preference change
test.register_coroutine_test(
  "notificationChild preference should create child device when enabled",
  function()
    mock_inovelli_vzm32_sn:expect_device_create({
      type = "EDGE_CHILD",
      label = "Inovelli VZM32-SN Notification",
      profile = "rgbw-bulb-2700K-6500K",
      parent_device_id = mock_inovelli_vzm32_sn.id,
      parent_assigned_child_key = "notification"
    })

    test.socket.device_lifecycle:__queue_receive(mock_inovelli_vzm32_sn:generate_info_changed({preferences = {notificationChild = true}}))
  end
)

-- Test parameter101 preference change
test.register_coroutine_test(
  "parameter101 preference should send configuration command",
  function()
    local new_param_value = 200
    test.socket.device_lifecycle:__queue_receive(mock_inovelli_vzm32_sn:generate_info_changed({preferences = {parameter101 = new_param_value}}))

    local expected_command = cluster_base.write_manufacturer_specific_attribute(
      mock_inovelli_vzm32_sn,
      0xFC32, -- PRIVATE_CLUSTER_ID
      101,    -- parameter_number
      0x122F, -- MFG_CODE
      data_types.Int16,
      new_param_value
    )

    print("=== DEBUG: Expected command ===")
    print("Command type:", type(expected_command))
    print("Command:", expected_command)

    test.socket.zigbee:__expect_send({
      mock_inovelli_vzm32_sn.id,
      expected_command
    })
  end
)

test.run_registered_tests()