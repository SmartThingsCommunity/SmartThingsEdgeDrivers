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
test.add_package_capability("cubeAction.yml")
test.add_package_capability("cubeFace.yml")
local capabilities = require "st.capabilities"
local cubeAction = capabilities["stse.cubeAction"]
local cubeFace = capabilities["stse.cubeFace"]

local clusters = require "st.matter.clusters"
local dkjson = require "dkjson"
local t_utils = require "integration_test.utils"
local utils = require "st.utils"

--mock the actual device1
local mock_device = test.mock_device.build_test_matter_device(
  {
    profile = t_utils.get_profile_definition("cube-t1-pro.yml"),
    manufacturer_info = {vendor_id = 0x115f, product_id = 0x0000, product_name = "Aqara Cube T1 Pro"},
    label = "Aqara Cube",
    device_id = "00000000-1111-2222-3333-000000000001",
    endpoints =
    {
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
        endpoint_id = 2,
        clusters = {
          {cluster_id = clusters.Switch.ID, feature_map = clusters.Switch.types.Feature.MOMENTARY_SWITCH, cluster_type = "SERVER"},
          {cluster_id = clusters.PowerSource.ID, cluster_type = "SERVER", feature_map = clusters.PowerSource.types.PowerSourceFeature.BATTERY}
        },
        device_types = {
          {device_type_id = 0x000F, device_type_revision = 1}
        },
      },
      {
        endpoint_id = 3,
        clusters = {
          {cluster_id = clusters.Switch.ID, feature_map = clusters.Switch.types.Feature.MOMENTARY_SWITCH, cluster_type = "SERVER"},
        },
      },
      {
        endpoint_id = 4,
        clusters = {
          {cluster_id = clusters.Switch.ID, feature_map = clusters.Switch.types.Feature.MOMENTARY_SWITCH, cluster_type = "SERVER"},
        },
      },
      {
        endpoint_id = 5,
        clusters = {
          {cluster_id = clusters.Switch.ID, feature_map = clusters.Switch.types.Feature.MOMENTARY_SWITCH, cluster_type = "SERVER"},
        },
      },
      {
        endpoint_id = 6,
        clusters = {
          {cluster_id = clusters.Switch.ID, feature_map = clusters.Switch.types.Feature.MOMENTARY_SWITCH, cluster_type = "SERVER"},
        },
      },
      {
        endpoint_id = 7,
        clusters = {
          {cluster_id = clusters.Switch.ID, feature_map = clusters.Switch.types.Feature.MOMENTARY_SWITCH, cluster_type = "SERVER"},
        },
      },
    }
  }
)

--mock the actual device2
local mock_device_exhausted = test.mock_device.build_test_matter_device(
  {
    profile = t_utils.get_profile_definition("cube-t1-pro.yml"),
    manufacturer_info = {vendor_id = 0x115f, product_id = 0x0000, product_name = "Aqara Cube T1 Pro"},
    label = "Aqara Cube",
    device_id = "00000000-1111-2222-3333-000000000003",
    endpoints =
    {
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
        endpoint_id = 2,
        clusters = {
          {cluster_id = clusters.Switch.ID, feature_map = clusters.Switch.types.Feature.MOMENTARY_SWITCH, cluster_type = "SERVER"},
          {cluster_id = clusters.PowerSource.ID, cluster_type = "SERVER", feature_map = clusters.PowerSource.types.PowerSourceFeature.BATTERY}
        },
        device_types = {
          {device_type_id = 0x000F, device_type_revision = 1}
        },
      },
      {
        endpoint_id = 3,
        clusters = {
          {cluster_id = clusters.Switch.ID, feature_map = clusters.Switch.types.Feature.MOMENTARY_SWITCH, cluster_type = "SERVER"},
        },
      },
      {
        endpoint_id = 4,
        clusters = {
          {cluster_id = clusters.Switch.ID, feature_map = clusters.Switch.types.Feature.MOMENTARY_SWITCH, cluster_type = "SERVER"},
        },
      },
      {
        endpoint_id = 5,
        clusters = {
          {cluster_id = clusters.Switch.ID, feature_map = clusters.Switch.types.Feature.MOMENTARY_SWITCH, cluster_type = "SERVER"},
        },
      },
      {
        endpoint_id = 250,
        clusters = {
          {cluster_id = clusters.Switch.ID, feature_map = clusters.Switch.types.Feature.MOMENTARY_SWITCH, cluster_type = "SERVER"},
        },
      },
      {
        endpoint_id = 251,
        clusters = {
          {cluster_id = clusters.Switch.ID, feature_map = clusters.Switch.types.Feature.MOMENTARY_SWITCH, cluster_type = "SERVER"},
        },
      },
    }
  }
)

-- add device for each mock device
local CLUSTER_SUBSCRIBE_LIST ={
  clusters.PowerSource.server.attributes.BatPercentRemaining,
  clusters.Switch.server.events.InitialPress,
  clusters.Switch.server.events.LongPress,
  clusters.Switch.server.events.ShortRelease,
  clusters.Switch.server.events.MultiPressComplete,
}

local function test_init()
  local subscribe_request = CLUSTER_SUBSCRIBE_LIST[1]:subscribe(mock_device)
  for i, clus in ipairs(CLUSTER_SUBSCRIBE_LIST) do
    if i > 1 then
      subscribe_request:merge(clus:subscribe(mock_device))
    end
  end
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
  mock_device:expect_metadata_update({ profile = "cube-t1-pro" })
  mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  local device_info_copy = utils.deep_copy(mock_device.raw_st_data)
  device_info_copy.profile.id = "matter-thing"
  local device_info_json = dkjson.encode(device_info_copy)
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "infoChanged", device_info_json })
  test.mock_device.add_test_device(mock_device)
  test.socket.capability:__expect_send(
    mock_device:generate_test_message("main", cubeAction.cubeAction({value = "flipToSide1"}))
  )
  test.socket.capability:__expect_send(
    mock_device:generate_test_message("main", cubeFace.cubeFace({value = "face1Up"}))
  )
end

test.set_test_init_function(test_init)

local function test_init_exhausted()
  local subscribe_request = CLUSTER_SUBSCRIBE_LIST[1]:subscribe(mock_device_exhausted)
  for i, clus in ipairs(CLUSTER_SUBSCRIBE_LIST) do
    if i > 1 then
      subscribe_request:merge(clus:subscribe(mock_device_exhausted))
    end
  end
  test.socket.matter:__expect_send({mock_device_exhausted.id, subscribe_request})
  test.socket.device_lifecycle:__queue_receive({ mock_device_exhausted.id, "added" })
  test.socket.matter:__expect_send({mock_device_exhausted.id, subscribe_request})
  test.socket.device_lifecycle:__queue_receive({ mock_device_exhausted.id, "doConfigure" })
  mock_device_exhausted:expect_metadata_update({ profile = "cube-t1-pro" })
  mock_device_exhausted:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  local device_info_copy = utils.deep_copy(mock_device_exhausted.raw_st_data)
  device_info_copy.profile.id = "matter-thing"
  local device_info_json = dkjson.encode(device_info_copy)
  test.socket.device_lifecycle:__queue_receive({ mock_device_exhausted.id, "infoChanged", device_info_json })
  test.mock_device.add_test_device(mock_device_exhausted)
  test.socket.capability:__expect_send(
    mock_device_exhausted:generate_test_message("main", cubeAction.cubeAction({value = "flipToSide1"}))
  )
  test.socket.capability:__expect_send(
    mock_device_exhausted:generate_test_message("main", cubeFace.cubeFace({value = "face1Up"}))
  )
end

test.register_coroutine_test(
  "Handle single press sequence",
    function()
      test.socket.matter:__queue_receive(
        {
          mock_device.id,
          clusters.Switch.events.InitialPress:build_test_event_report(
            mock_device, 2, {new_position = 1}
          )
        }
      )

      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", cubeAction.cubeAction({value = "flipToSide1"}))
      )

      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", cubeFace.cubeFace({value = "face1Up"}))
      )

      test.socket.matter:__queue_receive(
        {
          mock_device.id,
          clusters.PowerSource.attributes.BatPercentRemaining:build_test_report_data(
          mock_device, 2, 150
          )
        }
      )

      test.socket.capability:__expect_send(
        mock_device:generate_test_message(
          "main", capabilities.battery.battery(math.floor(150 / 2.0 + 0.5))
        )
      )
    end
)

test.register_coroutine_test(
  "Handle single press sequence in case of exhausted endpoint",
    function()
      test.socket.matter:__queue_receive(
        {
          mock_device_exhausted.id,
          clusters.Switch.events.InitialPress:build_test_event_report(
            mock_device_exhausted, 250, {new_position = 1}
          )
        }
      )

      test.socket.capability:__expect_send(
        mock_device_exhausted:generate_test_message("main", cubeAction.cubeAction({value = "flipToSide1"}))
      )

      test.socket.capability:__expect_send(
        mock_device_exhausted:generate_test_message("main", cubeFace.cubeFace({value = "face1Up"}))
      )
    end,
    { test_init = test_init_exhausted }
)

test.register_coroutine_test(
  "Test driver switched event",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "driverSwitched" })
    mock_device:expect_metadata_update({ profile = "cube-t1-pro" })
  end
)

-- run the tests
test.run_registered_tests()

