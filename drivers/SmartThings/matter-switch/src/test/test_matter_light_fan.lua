-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.matter.generated.zap_clusters"
local t_utils = require "integration_test.utils"
local test = require "integration_test"

local mock_device_ep1 = 1
local mock_device_ep2 = 2

local mock_device = test.mock_device.build_test_matter_device({
  label = "Matter Fan Light",
  profile = t_utils.get_profile_definition("fan-modular.yml",
    {enabled_optional_capabilities = {{"main", {"fanSpeedPercent", "fanMode"}}}}),
  manufacturer_info = {
    vendor_id = 0x0000,
    product_id = 0x0000,
  },
  matter_version = {
    software = 1,
    hardware = 1,
  },
  endpoints = {
    {
      endpoint_id = 0,
      clusters = {
        {cluster_id = clusters.Basic.ID, cluster_type = "SERVER"},
      },
      device_types = {
        {device_type_id = 0x0016, device_type_revision = 1} -- RootNode
      }
    },
    {
      endpoint_id = mock_device_ep1,
      clusters = {
        {cluster_id = clusters.OnOff.ID, cluster_type = "SERVER", feature_map = 0},
        {cluster_id = clusters.LevelControl.ID, cluster_type = "SERVER", feature_map = 2},
        {cluster_id = clusters.ColorControl.ID, cluster_type = "BOTH", feature_map = 30},
      },
      device_types = {
        {device_type_id = 0x010D, device_type_revision = 2} -- Extended Color Light
      }
    },
    {
      endpoint_id = mock_device_ep2,
      clusters = {
        {cluster_id = clusters.FanControl.ID, cluster_type = "SERVER", feature_map = 15},
      },
      device_types = {
        {device_type_id = 0x002B, device_type_revision = 1,} -- Fan
      }
    }
  }
})

local mock_device_capabilities_disabled = test.mock_device.build_test_matter_device({
  label = "Matter Fan Light",
  profile = t_utils.get_profile_definition("fan-modular.yml",
    {enabled_optional_capabilities = {{"main", {}}}}),
  manufacturer_info = {
    vendor_id = 0x0000,
    product_id = 0x0000,
  },
  matter_version = {
    software = 1,
    hardware = 1,
  },
  endpoints = {
    {
      endpoint_id = 0,
      clusters = {
        {cluster_id = clusters.Basic.ID, cluster_type = "SERVER"},
      },
      device_types = {
        {device_type_id = 0x0016, device_type_revision = 1} -- RootNode
      }
    },
    {
      endpoint_id = mock_device_ep2,
      clusters = {
        {cluster_id = clusters.FanControl.ID, cluster_type = "SERVER", feature_map = 15},
      },
      device_types = {
        {device_type_id = 0x002B, device_type_revision = 1,} -- Fan
      }
    }
  }
})

local CLUSTER_SUBSCRIBE_LIST ={
  clusters.OnOff.attributes.OnOff,
  clusters.LevelControl.attributes.CurrentLevel,
  clusters.LevelControl.attributes.MaxLevel,
  clusters.LevelControl.attributes.MinLevel,
  clusters.ColorControl.attributes.ColorTemperatureMireds,
  clusters.ColorControl.attributes.ColorTempPhysicalMaxMireds,
  clusters.ColorControl.attributes.ColorTempPhysicalMinMireds,
  clusters.ColorControl.attributes.CurrentHue,
  clusters.ColorControl.attributes.CurrentSaturation,
  clusters.ColorControl.attributes.CurrentX,
  clusters.ColorControl.attributes.CurrentY,
  clusters.ColorControl.attributes.ColorMode,
  clusters.FanControl.attributes.FanModeSequence,
  clusters.FanControl.attributes.FanMode,
  clusters.FanControl.attributes.PercentCurrent,
}

local mock_child = test.mock_device.build_test_child_device({
  profile = t_utils.get_profile_definition("light-color-level.yml"),
  device_network_id = string.format("%s:%d", mock_device.id, 4),
  parent_device_id = mock_device.id,
  parent_assigned_child_key = string.format("%d", mock_device_ep1)
})

local function test_init()
  test.disable_startup_messages()
  test.mock_device.add_test_device(mock_device)
  test.mock_device.add_test_device(mock_child)
  local subscribe_request = CLUSTER_SUBSCRIBE_LIST[1]:subscribe(mock_device)
  for i, clus in ipairs(CLUSTER_SUBSCRIBE_LIST) do
    if i > 1 then subscribe_request:merge(clus:subscribe(mock_device)) end
  end

  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "init" })
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})

  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
  test.socket.matter:__expect_send({mock_device.id, clusters.LevelControl.attributes.Options:write(mock_device, mock_device_ep1, clusters.LevelControl.types.OptionsBitmap.EXECUTE_IF_OFF)})
  test.socket.matter:__expect_send({mock_device.id, clusters.ColorControl.attributes.Options:write(mock_device, mock_device_ep1, clusters.ColorControl.types.OptionsBitmap.EXECUTE_IF_OFF)})
  mock_device:expect_device_create({
    type = "EDGE_CHILD",
    label = "Matter Fan Light 1",
    profile = "light-color-level",
    parent_device_id = mock_device.id,
    parent_assigned_child_key = string.format("%d", mock_device_ep1)
  })
  mock_device:expect_metadata_update({ profile = "fan-modular", optional_component_capabilities = {{"main", {"fanSpeedPercent", "fanMode"}}} })
  mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Component-capability update without profile ID update should cause re-subscribe in infoChanged handler", function()
    local cluster_subscribe_list ={
      clusters.FanControl.attributes.FanModeSequence,
      clusters.FanControl.attributes.FanMode,
      clusters.FanControl.attributes.PercentCurrent,
    }
    local subscribe_request = cluster_subscribe_list[1]:subscribe(mock_device_capabilities_disabled)
    for i, clus in ipairs(cluster_subscribe_list) do
      if i > 1 then subscribe_request:merge(clus:subscribe(mock_device_capabilities_disabled)) end
    end
    test.socket.device_lifecycle:__queue_receive(mock_device_capabilities_disabled:generate_info_changed(
      {profile = {id = "00000000-1111-2222-3333-000000000004", components = { main = {capabilities={["fanSpeedPercent"] = {id="fanSpeedPercent", version=1}, ["fanMode"] = {id="fanMode", version=1}, ["firmwareUpdate"] = {id="firmwareUpdate", version=1}, ["refresh"] = {id="refresh", version=1}}}}}})
    )
    test.socket.matter:__expect_send({mock_device_capabilities_disabled.id, subscribe_request})
  end,
  { test_init = function() test.mock_device.add_test_device(mock_device_capabilities_disabled) end }
)

test.register_coroutine_test(
  "No component-capability update and no profile ID update should not cause a re-subscribe in infoChanged handler", function()
    -- simulate no actual change
    test.socket.device_lifecycle:__queue_receive(mock_device_capabilities_disabled:generate_info_changed({}))
  end,
  { test_init = function() test.mock_device.add_test_device(mock_device_capabilities_disabled) end }
)

local FanMode = clusters.FanControl.attributes.FanMode
test.register_message_test(
  "Fan mode reports should generate correct messages",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        FanMode:build_test_report_data(mock_device, mock_device_ep2, FanMode.SMART)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.fanMode.fanMode.auto())
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        FanMode:build_test_report_data(mock_device, mock_device_ep2, FanMode.AUTO)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.fanMode.fanMode.auto())
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        FanMode:build_test_report_data(mock_device, mock_device_ep2, FanMode.MEDIUM)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.fanMode.fanMode("medium"))
    }
  },
  {
     min_api_version = 17
  }
)

local FanModeSequence = clusters.FanControl.attributes.FanModeSequence
test.register_message_test(
  "Fan mode sequence reports should generate the appropriate supported modes",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        FanModeSequence:build_test_report_data(mock_device, mock_device_ep2, FanModeSequence.OFF_ON)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.fanMode.supportedFanModes({"off", "high"}, {visibility={displayed=false}}))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        FanModeSequence:build_test_report_data(mock_device, mock_device_ep2, FanModeSequence.OFF_LOW_MED_HIGH_AUTO)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.fanMode.supportedFanModes({"off", "low", "medium", "high", "auto"}, {visibility={displayed=false}}))
    },
  },
  {
     min_api_version = 17
  }
)

test.register_message_test(
  "Capability command setFanMode should be handled",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "fanMode", component = "main", command = "setFanMode", args = { "low" } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.FanControl.attributes.FanMode:write(mock_device, mock_device_ep2, FanMode.LOW)
      }
    }
  },
  {
     min_api_version = 17
  }
)

test.register_message_test(
  "Capability command setPercent should be handled",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "fanSpeedPercent", component = "main", command = "setPercent", args = { 64 } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.FanControl.attributes.PercentSetting:write(mock_device, mock_device_ep2, 64)
      }
    }
  },
  {
     min_api_version = 17
  }
)

-- run the tests
test.run_registered_tests()
