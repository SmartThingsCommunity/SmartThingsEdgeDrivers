-- Copyright 2022 SmartThings
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

-- Mock out globals
local base64 = require "st.base64"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local dkjson = require 'dkjson'
local test = require "integration_test"
local t_utils = require "integration_test.utils"
local utils = require "st.utils"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"

local SINOPE_SWITCH_CLUSTER = 0xFF01
local SINOPE_MAX_INTENSITY_ON_ATTRIBUTE = 0x0052
local SINOPE_MAX_INTENSITY_OFF_ATTRIBUTE = 0x0053

local mock_device = test.mock_device.build_test_zigbee_device(
    { profile = t_utils.get_profile_definition("switch-led-intensity.yml"),
      fingerprinted_endpoint_id = 0x01,
      zigbee_endpoints = {
        [1] = {
          id = 1,
          manufacturer = "Sinope Technologies",
          model = "SW2500ZB",
          server_clusters = {}
        }
      }
    }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device)end

test.set_test_init_function(test_init)

test.register_coroutine_test(
    "infochanged to check for necessary preferences settings or updated when ledIntensity preference setting in non-zero",
    function()
      test.socket.environment_update:__queue_receive({ "zigbee", { hub_zigbee_id = base64.encode(zigbee_test_utils.mock_hub_eui) } })

      local device_info_copy = utils.deep_copy(mock_device.raw_st_data)
      device_info_copy.preferences.ledIntensity = 10
      local device_info_json = dkjson.encode(device_info_copy)
      test.wait_for_events()
      test.socket.device_lifecycle:__queue_receive({ mock_device.id, "infoChanged", device_info_json })
      test.socket.zigbee:__expect_send({mock_device.id, cluster_base.write_attribute(mock_device,
                data_types.ClusterId(SINOPE_SWITCH_CLUSTER),
                data_types.AttributeId(SINOPE_MAX_INTENSITY_ON_ATTRIBUTE),
                data_types.validate_or_build_type(device_info_copy.preferences.ledIntensity, data_types.Uint8, "payload"))})
      test.socket.zigbee:__expect_send({mock_device.id, cluster_base.write_attribute(mock_device,
                data_types.ClusterId(SINOPE_SWITCH_CLUSTER),
                data_types.AttributeId(SINOPE_MAX_INTENSITY_OFF_ATTRIBUTE),
                data_types.validate_or_build_type(device_info_copy.preferences.ledIntensity, data_types.Uint8, "payload"))})
      test.socket.zigbee:__set_channel_ordering("relaxed")

   end
  )

test.register_coroutine_test(
    "infochanged to check for necessary preferences settings or updated when ledIntensity preference setting is zero",
    function()
      test.socket.environment_update:__queue_receive({ "zigbee", { hub_zigbee_id = base64.encode(zigbee_test_utils.mock_hub_eui) } })

      local device_info_copy = utils.deep_copy(mock_device.raw_st_data)
      device_info_copy.preferences.ledIntensity = 0
      local device_info_json = dkjson.encode(device_info_copy)
      test.wait_for_events()
      test.socket.device_lifecycle:__queue_receive({ mock_device.id, "infoChanged", device_info_json })
      test.socket.zigbee:__expect_send({mock_device.id, cluster_base.write_attribute(mock_device,
                data_types.ClusterId(SINOPE_SWITCH_CLUSTER),
                data_types.AttributeId(SINOPE_MAX_INTENSITY_ON_ATTRIBUTE),
                data_types.validate_or_build_type(device_info_copy.preferences.ledIntensity, data_types.Uint8, "payload"))})
      test.socket.zigbee:__expect_send({mock_device.id, cluster_base.write_attribute(mock_device,
                data_types.ClusterId(SINOPE_SWITCH_CLUSTER),
                data_types.AttributeId(SINOPE_MAX_INTENSITY_OFF_ATTRIBUTE),
                data_types.validate_or_build_type(device_info_copy.preferences.ledIntensity, data_types.Uint8, "payload"))})
      test.socket.zigbee:__set_channel_ordering("relaxed")

   end
  )

test.register_coroutine_test(
    "infochanged to check for necessary preferences settings or updated when ledIntensity preference setting is > 50",
    function()
      test.socket.environment_update:__queue_receive({ "zigbee", { hub_zigbee_id = base64.encode(zigbee_test_utils.mock_hub_eui) } })

      local device_info_copy = utils.deep_copy(mock_device.raw_st_data)
      device_info_copy.preferences.ledIntensity = 70
      local device_info_json = dkjson.encode(device_info_copy)
      test.wait_for_events()
      test.socket.device_lifecycle:__queue_receive({ mock_device.id, "infoChanged", device_info_json })
      test.socket.zigbee:__expect_send({mock_device.id, cluster_base.write_attribute(mock_device,
                data_types.ClusterId(SINOPE_SWITCH_CLUSTER),
                data_types.AttributeId(SINOPE_MAX_INTENSITY_ON_ATTRIBUTE),
                data_types.validate_or_build_type(device_info_copy.preferences.ledIntensity, data_types.Uint8, "payload"))})
      test.socket.zigbee:__expect_send({mock_device.id, cluster_base.write_attribute(mock_device,
                data_types.ClusterId(SINOPE_SWITCH_CLUSTER),
                data_types.AttributeId(SINOPE_MAX_INTENSITY_OFF_ATTRIBUTE),
                data_types.validate_or_build_type(device_info_copy.preferences.ledIntensity, data_types.Uint8, "payload"))})
      test.socket.zigbee:__set_channel_ordering("relaxed")

   end
  )

test.run_registered_tests()
