local test = require "integration_test"
local capabilities = require "st.capabilities"
test.add_package_capability("cubeAction.yaml")
test.add_package_capability("cubeFace.yaml")
local t_utils = require "integration_test.utils"

local clusters = require "st.matter.generated.zap_clusters"

local cubeAction = capabilities["stse.cubeAction"]
local cubeFace = capabilities["stse.cubeFace"]

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
}

local function test_init()
  test.mock_devices_api._expected_device_updates[mock_device.device_id] = "00000000-1111-2222-3333-000000000001"
  test.mock_devices_api._expected_device_updates[1] = {device_id = "00000000-1111-2222-3333-000000000001"}
  test.mock_devices_api._expected_device_updates[1].metadata = {deviceId="00000000-1111-2222-3333-000000000001", profileReference="cube-t1-pro"}
  local subscribe_request = CLUSTER_SUBSCRIBE_LIST[1]:subscribe(mock_device)
  for i, clus in ipairs(CLUSTER_SUBSCRIBE_LIST) do
    if i > 1 then subscribe_request:merge(clus:subscribe(mock_device)) end
  end
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})
  test.mock_device.add_test_device(mock_device)
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
end

test.set_test_init_function(test_init)

test.register_message_test(
  "Handle single press sequence for cubeAction and cubeFace", {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.Switch.events.InitialPress:build_test_event_report(
          mock_device, 250, {new_position = 1}  --move to position 1?
        ),
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", cubeAction.cubeAction({value = "flipToSide1"}))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", cubeFace.cubeFace({value = "face1Up"}))
    },
  }
)

-- run the tests
test.run_registered_tests()
