local test = require "integration_test"
test.add_package_capability("cubeAction.yml")
test.add_package_capability("cubeFace.yml")
local capabilities = require "st.capabilities"
local cubeAction = capabilities["stse.cubeAction"]
local cubeFace = capabilities["stse.cubeFace"]

local t_utils = require "integration_test.utils"
local clusters = require "st.matter.clusters"

local DOING_CONFIGURE = "__DOING_CONFIGURE"

--mock the actual device
local mock_device = test.mock_device.build_test_matter_device(
  {
    profile = t_utils.get_profile_definition("cube-t1-pro.yml"),
    manufacturer_info = {vendor_id = 0x115f, product_id = 0x0000},
    label = "Aqara Cube T1 Pro",
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

local mock_exhausted_endpoint_device = test.mock_device.build_test_matter_device(
  {
    profile = t_utils.get_profile_definition("cube-t1-pro.yml"),
    manufacturer_info = {vendor_id = 0x115f, product_id = 0x0000},
    label = "Aqara Cube T1 Pro",
    device_id = "00000000-1111-2222-3333-000000000003",
    endpoints =
    {
      {
        endpoint_id = 2,
        clusters = {
          {cluster_id = clusters.Switch.ID, feature_map = clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH, cluster_type = "SERVER"},
          {cluster_id = clusters.PowerSource.ID, cluster_type = "SERVER", feature_map = clusters.PowerSource.types.PowerSourceFeature.BATTERY}
        },
        device_types = {
          {device_type_id = 0x000F, device_type_revision = 1}
        },
      },
      {
        endpoint_id = 3,
        clusters = {
          {cluster_id = clusters.Switch.ID, feature_map = clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH, cluster_type = "SERVER"},
        },
      },
      {
        endpoint_id = 4,
        clusters = {
          {cluster_id = clusters.Switch.ID, feature_map = clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH, cluster_type = "SERVER"},
        },
      },
      {
        endpoint_id = 5,
        clusters = {
          {cluster_id = clusters.Switch.ID, feature_map = clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH, cluster_type = "SERVER"},
        },
      },
      {
        endpoint_id = 250,
        clusters = {
          {cluster_id = clusters.Switch.ID, feature_map = clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH, cluster_type = "SERVER"},
        },
      },
      {
        endpoint_id = 251,
        clusters = {
          {cluster_id = clusters.Switch.ID, feature_map = clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH, cluster_type = "SERVER"},
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
  test.socket.matter:__set_channel_ordering("relaxed")
  test.socket.capability:__set_channel_ordering("relaxed")
  local subscribe_request = CLUSTER_SUBSCRIBE_LIST[1]:subscribe(mock_device)
  for i, clus in ipairs(CLUSTER_SUBSCRIBE_LIST) do
    if i > 1 then
      subscribe_request:merge(clus:subscribe(mock_device))
    end
  end
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})
  test.mock_device.add_test_device(mock_device)

  subscribe_request = CLUSTER_SUBSCRIBE_LIST[1]:subscribe(mock_exhausted_endpoint_device)
  for i, cluster in ipairs(CLUSTER_SUBSCRIBE_LIST) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(mock_exhausted_endpoint_device))
    end
  end
  test.socket.matter:__expect_send({mock_exhausted_endpoint_device.id, subscribe_request})
  test.mock_device.add_test_device(mock_exhausted_endpoint_device)
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Handle single press sequence when changing the device_lifecycle",
    function()
      test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
      test.mock_devices_api._expected_device_updates[mock_device.device_id] = "00000000-1111-2222-3333-000000000001"
      test.mock_devices_api._expected_device_updates[1] = {device_id = "00000000-1111-2222-3333-000000000001"}
      test.mock_devices_api._expected_device_updates[1].metadata = {deviceId="00000000-1111-2222-3333-000000000001", profileReference="cube-t1-pro"}

      mock_device:set_field(DOING_CONFIGURE, true)
      test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({value = "face1Up"}))
      -- let the driver run
      test.wait_for_events()

      test.socket.matter:__queue_receive(
        {
          mock_device.id,
          clusters.Switch.events.InitialPress:build_test_event_report(
            mock_device, 2, {new_position = 1}  --move to position 1?
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
      test.socket.device_lifecycle:__queue_receive({ mock_exhausted_endpoint_device.id, "added" })
      test.mock_devices_api._expected_device_updates[mock_exhausted_endpoint_device.device_id] = "00000000-1111-2222-3333-000000000003"
      test.mock_devices_api._expected_device_updates[1] = {device_id = "00000000-1111-2222-3333-000000000003"}
      test.mock_devices_api._expected_device_updates[1].metadata = {deviceId="00000000-1111-2222-3333-000000000003", profileReference="cube-t1-pro"}

      test.socket.matter:__queue_receive(
        {
          mock_exhausted_endpoint_device.id,
          clusters.Switch.events.InitialPress:build_test_event_report(
            mock_exhausted_endpoint_device, 2, {new_position = 1}  --move to position 1?
          )
        }
      )

      test.socket.matter:__queue_receive(
        {
          mock_exhausted_endpoint_device.id,
          clusters.PowerSource.attributes.BatPercentRemaining:build_test_report_data(
          mock_exhausted_endpoint_device, 2, 150
          )
        }
      )

      test.socket.capability:__expect_send(
        mock_exhausted_endpoint_device:generate_test_message(
          "main", capabilities.battery.battery(math.floor(150 / 2.0 + 0.5))
        )
      )
    end
)

-- run the tests
test.run_registered_tests()
