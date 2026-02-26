-- Copyright © 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local t_utils = require "integration_test.utils"

local clusters = require "st.matter.clusters"

-- This is to make sure that any device with the "Aggregator" device type
-- is not profile switched from a bridge, even if there are other endpoints
-- present. This is due to an issue on the hub where sometimes the endpoints
-- are not filtered out properly.
local mock_bridge = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("matter-bridge.yml"),
  manufacturer_info = {
    vendor_id = 0x0000,
    product_id = 0x0000,
  },
  endpoints = {
    {
      endpoint_id = 0,
      clusters = {
        {cluster_id = clusters.Basic.ID, cluster_type = "SERVER"},
      },
      device_types = {
        {device_type_id = 0x000E, device_type_revision = 1} -- Aggregator
      }
    },
    {
      endpoint_id = 1,
      clusters = {
        {
          cluster_id = clusters.OnOff.ID,
          cluster_type = "SERVER",
          cluster_revision = 1,
          feature_map = 0, --u32 bitmap
        },
        {cluster_id = clusters.LevelControl.ID, cluster_type = "SERVER"}
      },
      device_types = {
        {device_type_id = 0x0100, device_type_revision = 1} -- On/Off Light
      }
    },
    {
      endpoint_id = 2,
      clusters = {
        {
          cluster_id = clusters.OnOff.ID,
          cluster_type = "SERVER",
          cluster_revision = 1,
          feature_map = 0, --u32 bitmap
        },
        {cluster_id = clusters.LevelControl.ID, cluster_type = "SERVER"}
      },
      device_types = {
        {device_type_id = 0x0100, device_type_revision = 1} -- On/Off Light
      }
    }
  }
})

local function test_init_mock_bridge()
  test.mock_device.add_test_device(mock_bridge)
  test.socket.device_lifecycle:__queue_receive({ mock_bridge.id, "added" })
  test.socket.device_lifecycle:__queue_receive({ mock_bridge.id, "init" })
  test.socket.device_lifecycle:__queue_receive({ mock_bridge.id, "doConfigure" })
  mock_bridge:expect_metadata_update({ provisioning_state = "PROVISIONED" })
end

test.register_coroutine_test(
  "Profile should not change for devices with aggregator device type (bridges)",
  function()
  end,
  { test_init = test_init_mock_bridge },
  {
     min_api_version = 19
  }
)

test.run_registered_tests()
