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

local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local dkjson = require "dkjson"
local t_utils = require "integration_test.utils"
local test = require "integration_test"
local utils = require "st.utils"

local mock_device = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("12-button-keyboard.yml"),
  manufacturer_info = {vendor_id = 0x1407, product_id = 0x1388},
  endpoints = {
    {
      endpoint_id = 0,
      clusters = {
        { cluster_id = clusters.Basic.ID, cluster_type = "SERVER" },
      },
      device_types = {
        { device_type_id = 0x0016, device_type_revision = 1 } -- RootNode
      }
    },
    {
      endpoint_id = 1,
      clusters = {
        {
          cluster_id = clusters.Switch.ID,
          feature_map = clusters.Switch.types.Feature.MOMENTARY_SWITCH,
          cluster_type = "SERVER"
        }
      },
      device_types = {
        {device_type_id = 0x000F, device_type_revision = 1} -- Generic Switch
      }
    },
    {
      endpoint_id = 2,
      clusters = {
        {
          cluster_id = clusters.Switch.ID,
          feature_map = clusters.Switch.types.Feature.MOMENTARY_SWITCH,
          cluster_type = "SERVER"
        }
      },
      device_types = {
        {device_type_id = 0x000F, device_type_revision = 1} -- Generic Switch
      }
    },
    {
      endpoint_id = 3,
      clusters = {
        {
          cluster_id = clusters.Switch.ID,
          feature_map = clusters.Switch.types.Feature.MOMENTARY_SWITCH,
          cluster_type = "SERVER"
        }
      },
      device_types = {
        {device_type_id = 0x000F, device_type_revision = 1} -- Generic Switch
      }
    },
    {
      endpoint_id = 4,
      clusters = {
        {
          cluster_id = clusters.Switch.ID,
          feature_map = clusters.Switch.types.Feature.MOMENTARY_SWITCH,
          cluster_type = "SERVER"
        }
      },
      device_types = {
        {device_type_id = 0x000F, device_type_revision = 1} -- Generic Switch
      }
    },
    {
      endpoint_id = 5,
      clusters = {
        {
          cluster_id = clusters.Switch.ID,
          feature_map = clusters.Switch.types.Feature.MOMENTARY_SWITCH,
          cluster_type = "SERVER"
        }
      },
      device_types = {
        {device_type_id = 0x000F, device_type_revision = 1} -- Generic Switch
      }
    },
    {
      endpoint_id = 6,
      clusters = {
        {
          cluster_id = clusters.Switch.ID,
          feature_map = clusters.Switch.types.Feature.MOMENTARY_SWITCH,
          cluster_type = "SERVER"
        }
      },
      device_types = {
        {device_type_id = 0x000F, device_type_revision = 1} -- Generic Switch
      }
    },
    {
      endpoint_id = 7,
      clusters = {
        {
          cluster_id = clusters.Switch.ID,
          feature_map = clusters.Switch.types.Feature.MOMENTARY_SWITCH,
          cluster_type = "SERVER"
        }
      },
      device_types = {
        {device_type_id = 0x000F, device_type_revision = 1} -- Generic Switch
      }
    },
    {
      endpoint_id = 8,
      clusters = {
        {
          cluster_id = clusters.Switch.ID,
          feature_map = clusters.Switch.types.Feature.MOMENTARY_SWITCH,
          cluster_type = "SERVER"
        }
      },
      device_types = {
        {device_type_id = 0x000F, device_type_revision = 1} -- Generic Switch
      }
    },
    {
      endpoint_id = 9,
      clusters = {
        {
          cluster_id = clusters.Switch.ID,
          feature_map = clusters.Switch.types.Feature.MOMENTARY_SWITCH,
          cluster_type = "SERVER"
        }
      },
      device_types = {
        {device_type_id = 0x000F, device_type_revision = 1} -- Generic Switch
      }
    },
    {
      endpoint_id = 10,
      clusters = {
        {
          cluster_id = clusters.Switch.ID,
          feature_map = clusters.Switch.types.Feature.MOMENTARY_SWITCH,
          cluster_type = "SERVER"
        }
      },
      device_types = {
        {device_type_id = 0x000F, device_type_revision = 1} -- Generic Switch
      }
    },
    {
      endpoint_id = 11,
      clusters = {
        {
          cluster_id = clusters.Switch.ID,
          feature_map = clusters.Switch.types.Feature.MOMENTARY_SWITCH,
          cluster_type = "SERVER"
        }
      },
      device_types = {
        {device_type_id = 0x000F, device_type_revision = 1} -- Generic Switch
      }
    },
    {
      endpoint_id = 12,
      clusters = {
        {
          cluster_id = clusters.Switch.ID,
          feature_map = clusters.Switch.types.Feature.MOMENTARY_SWITCH,
          cluster_type = "SERVER"
        }
      },
      device_types = {
        {device_type_id = 0x000F, device_type_revision = 1} -- Generic Switch
      }
    }
  }
})

local function configure_buttons()
  for key = 1, 12 do
    local component = "F" .. key
    if key == 1 then component = "main" end
    test.socket.capability:__expect_send(mock_device:generate_test_message(component, capabilities.button.supportedButtonValues({"pushed"}, {visibility = {displayed = false}})))
    test.socket.capability:__expect_send(mock_device:generate_test_message(component, capabilities.button.button.pushed({state_change = false})))
  end
end

local function test_init()
  test.disable_startup_messages()
  test.mock_device.add_test_device(mock_device)
  local cluster_subscribe_list = {
    clusters.Switch.events.InitialPress
  }
  local subscribe_request = cluster_subscribe_list[1]:subscribe(mock_device)
  for i, clus in ipairs(cluster_subscribe_list) do
    if i > 1 then subscribe_request:merge(clus:subscribe(mock_device)) end
  end

  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })

  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "init" })
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})

  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
  mock_device:expect_metadata_update({ profile = "12-button-keyboard" })
  mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  configure_buttons()

  local device_info_copy = utils.deep_copy(mock_device.raw_st_data)
  device_info_copy.profile.id = "12-buttons-keyboard"
  local device_info_json = dkjson.encode(device_info_copy)
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "infoChanged", device_info_json })
  configure_buttons()
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Handle single press sequence",
  function()
    for key = 1, 12 do
      test.socket.matter:__queue_receive({
        mock_device.id,
        clusters.Switch.events.InitialPress:build_test_event_report(mock_device, key, {new_position = 1})
      })
      test.socket.capability:__expect_send(
        mock_device:generate_test_message(key == 1 and "main" or "F" .. key, capabilities.button.button.pushed({state_change = true}))
      )
    end
  end
)

-- run the tests
test.run_registered_tests()
