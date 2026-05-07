-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local t_utils = require "integration_test.utils"
local clusters = require "st.matter.clusters"

test.disable_startup_messages()


local generic_manufacturer_info = { vendor_id = 0x0000, product_id = 0x0000 }
local generic_matter_version = { hardware = 1, software = 1 }
local root_endpoint = {
  endpoint_id = 0,
  clusters = {
    {cluster_id = clusters.Basic.ID, cluster_type = "SERVER"},
  },
  device_types = {
    {device_type_id = 0x0016, device_type_revision = 1} -- RootNode
  }
}


local mock_device_onoff_switch_as_server = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("matter-thing.yml"),
  manufacturer_info = generic_manufacturer_info,
  matter_version = generic_matter_version,
  endpoints = {
    root_endpoint,
    {
      endpoint_id = 1,
      clusters = {
        {cluster_id = clusters.OnOff.ID, cluster_type = "SERVER", cluster_revision = 1, feature_map = 0},
      },
      device_types = {
        {device_type_id = 0x0103, device_type_revision = 1} -- On/Off Light Switch
      }
    }
  }
})

test.register_coroutine_test(
  "Test profile change on init for onoff parent cluster as server",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device_onoff_switch_as_server.id, "added" })
    test.socket.device_lifecycle:__queue_receive({ mock_device_onoff_switch_as_server.id, "init" })
    test.socket.device_lifecycle:__queue_receive({ mock_device_onoff_switch_as_server.id, "doConfigure" })
    mock_device_onoff_switch_as_server:expect_metadata_update({ profile = "switch-binary" })
    mock_device_onoff_switch_as_server:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end,
  {
    test_init = function() test.mock_device.add_test_device(mock_device_onoff_switch_as_server) end,
    min_api_version = 17
  }
)


local mock_device_onoff_switch_as_client = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("matter-thing.yml"),
  manufacturer_info = generic_manufacturer_info,
  matter_version = generic_matter_version,
  endpoints = {
    root_endpoint,
    {
      endpoint_id = 1,
      clusters = {
        {cluster_id = clusters.OnOff.ID, cluster_type = "CLIENT", cluster_revision = 1, feature_map = 0},
      },
      device_types = {
        {device_type_id = 0x0103, device_type_revision = 1} -- On/Off Light Switch
      }
    }
  }
})

test.register_coroutine_test(
  "Test init for onoff parent cluster as client",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device_onoff_switch_as_client.id, "added" })
    test.socket.device_lifecycle:__queue_receive({ mock_device_onoff_switch_as_client.id, "init" })
    test.socket.device_lifecycle:__queue_receive({ mock_device_onoff_switch_as_client.id, "doConfigure" })
    mock_device_onoff_switch_as_client:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end,
  {
    test_init = function() test.mock_device.add_test_device(mock_device_onoff_switch_as_client) end,
    min_api_version = 17
  }
)


local mock_device_dimmer_switch_as_server = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("matter-thing.yml"),
  manufacturer_info = generic_manufacturer_info,
  matter_version = generic_matter_version,
  endpoints = {
    root_endpoint,
    {
      endpoint_id = 1,
      clusters = {
        {cluster_id = clusters.OnOff.ID, cluster_type = "SERVER", cluster_revision = 1, feature_map = 0},
        {cluster_id = clusters.LevelControl.ID, cluster_type = "SERVER", feature_map = 2}
      },
      device_types = {
        {device_type_id = 0x0104, device_type_revision = 1} -- Dimmer Switch
      }
    }
  }
})

test.register_coroutine_test(
  "Test profile change on init for dimmer parent cluster as server",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device_dimmer_switch_as_server.id, "added" })
    test.socket.device_lifecycle:__queue_receive({ mock_device_dimmer_switch_as_server.id, "init" })
    test.socket.device_lifecycle:__queue_receive({ mock_device_dimmer_switch_as_server.id, "doConfigure" })
    test.socket.matter:__expect_send({
      mock_device_dimmer_switch_as_server.id,
      clusters.LevelControl.attributes.Options:write(mock_device_dimmer_switch_as_server, 1, clusters.LevelControl.types.OptionsBitmap.EXECUTE_IF_OFF)
    })
    mock_device_dimmer_switch_as_server:expect_metadata_update({ profile = "switch-level" })
    mock_device_dimmer_switch_as_server:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end,
  {
    test_init = function() test.mock_device.add_test_device(mock_device_dimmer_switch_as_server) end,
    min_api_version = 17
  }
)


local mock_device_plug_with_switch_profile_vendor_override = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("switch-binary.yml"),
  manufacturer_info = { vendor_id = 0x142B, product_id = 0x1003}, -- this device has a vendor override to join as a switch instead of a plug
  matter_version = generic_matter_version,
  endpoints = {
    root_endpoint,
    {
      endpoint_id = 1,
      clusters = {
        {cluster_id = clusters.OnOff.ID, cluster_type = "SERVER", cluster_revision = 1, feature_map = 0},
      },
      device_types = {
        {device_type_id = 0x010A, device_type_revision = 1} -- OnOff PlugIn Unit
      }
    }
  }
})

test.register_coroutine_test(
  "Test init for device with requiring the switch category as a vendor override",
  function()
    local mock_device = mock_device_plug_with_switch_profile_vendor_override
    local subscribe_request = clusters.OnOff.attributes.OnOff:subscribe(mock_device)
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
    test.socket.matter:__expect_send({mock_device.id, subscribe_request})
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "init" })
    test.socket.matter:__expect_send({mock_device.id, subscribe_request})
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
    mock_device:expect_metadata_update({ profile = "switch-binary" })
    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end,
  {
    test_init = function() test.mock_device.add_test_device(mock_device_plug_with_switch_profile_vendor_override) end,
    min_api_version = 17
  }
)


local mock_device_color_dimmer = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("matter-thing.yml"),
  manufacturer_info = generic_manufacturer_info,
  matter_version = generic_matter_version,
  endpoints = {
    root_endpoint,
    {
      endpoint_id = 7,
      clusters = {
        {cluster_id = clusters.OnOff.ID, cluster_type = "SERVER", cluster_revision = 1, feature_map = 0},
        {cluster_id = clusters.LevelControl.ID, cluster_type = "CLIENT", feature_map = 2},
        {cluster_id = clusters.ColorControl.ID, cluster_type = "CLIENT", feature_map = 31},

      },
      device_types = {
        {device_type_id = 0x0105, device_type_revision = 1} -- Color Dimmer Switch
      }
    }
  }
})

test.register_coroutine_test(
  "Test profile change on init for color dimmer device type as server",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device_color_dimmer.id, "added" })
    test.socket.device_lifecycle:__queue_receive({ mock_device_color_dimmer.id, "init" })
    test.socket.device_lifecycle:__queue_receive({ mock_device_color_dimmer.id, "doConfigure" })
    mock_device_color_dimmer:expect_metadata_update({ profile = "switch-color-level" })
    mock_device_color_dimmer:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end,
  {
    test_init = function() test.mock_device.add_test_device(mock_device_color_dimmer) end,
    min_api_version = 17
  }
)


local mock_device_mounted_on_off_control = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("switch-binary.yml"),
  manufacturer_info = generic_manufacturer_info,
  matter_version = generic_matter_version,
  endpoints = {
    root_endpoint,
    {
      endpoint_id = 7,
      clusters = {
        {cluster_id = clusters.OnOff.ID, cluster_type = "SERVER", cluster_revision = 1, feature_map = 0},
        {cluster_id = clusters.LevelControl.ID, cluster_type = "SERVER", feature_map = 2},

      },
      device_types = {
        {device_type_id = 0x010F, device_type_revision = 1} -- Mounted On/Off Control
      }
    }
  }
})

test.register_coroutine_test(
  "Test init for mounted onoff control",
  function()
    local subscribe_request = clusters.OnOff.attributes.OnOff:subscribe(mock_device_mounted_on_off_control)

    test.socket.device_lifecycle:__queue_receive({ mock_device_mounted_on_off_control.id, "added" })
    test.socket.matter:__expect_send({mock_device_mounted_on_off_control.id, subscribe_request})

    test.socket.device_lifecycle:__queue_receive({ mock_device_mounted_on_off_control.id, "init" })
    test.socket.matter:__expect_send({mock_device_mounted_on_off_control.id, subscribe_request})

    test.socket.device_lifecycle:__queue_receive({ mock_device_mounted_on_off_control.id, "doConfigure" })
    test.socket.matter:__expect_send({
      mock_device_mounted_on_off_control.id,
      clusters.LevelControl.attributes.Options:write(mock_device_mounted_on_off_control, 7, clusters.LevelControl.types.OptionsBitmap.EXECUTE_IF_OFF)
    })
    mock_device_mounted_on_off_control:expect_metadata_update({ profile = "switch-binary" })
    mock_device_mounted_on_off_control:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end,
  {
    test_init = function() test.mock_device.add_test_device(mock_device_mounted_on_off_control) end,
    min_api_version = 17
  }
)


local mock_device_mounted_dimmable_load_control = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("switch-level.yml"),
  manufacturer_info = generic_manufacturer_info,
  matter_version = generic_matter_version,
  endpoints = {
    root_endpoint,
    {
      endpoint_id = 7,
      clusters = {
        {cluster_id = clusters.OnOff.ID, cluster_type = "SERVER", cluster_revision = 1, feature_map = 0},
        {cluster_id = clusters.LevelControl.ID, cluster_type = "SERVER", feature_map = 2},

      },
      device_types = {
        {device_type_id = 0x0110, device_type_revision = 1} -- Mounted Dimmable Load Control
      }
    }
  }
})

test.register_coroutine_test(
  "Test init for mounted dimmable load control",
  function()
    local cluster_subscribe_list = {
      clusters.OnOff.attributes.OnOff,
      clusters.LevelControl.attributes.CurrentLevel,
      clusters.LevelControl.attributes.MinLevel,
      clusters.LevelControl.attributes.MaxLevel,
    }
    local subscribe_request = cluster_subscribe_list[1]:subscribe(mock_device_mounted_dimmable_load_control)
    for i, cluster in ipairs(cluster_subscribe_list) do
      if i > 1 then
        subscribe_request:merge(cluster:subscribe(mock_device_mounted_dimmable_load_control))
      end
    end
    test.socket.device_lifecycle:__queue_receive({ mock_device_mounted_dimmable_load_control.id, "added" })
    test.socket.matter:__expect_send({mock_device_mounted_dimmable_load_control.id, subscribe_request})

    test.socket.device_lifecycle:__queue_receive({ mock_device_mounted_dimmable_load_control.id, "init" })
    test.socket.matter:__expect_send({mock_device_mounted_dimmable_load_control.id, subscribe_request})

    test.socket.device_lifecycle:__queue_receive({ mock_device_mounted_dimmable_load_control.id, "doConfigure" })
    test.socket.matter:__expect_send({
      mock_device_mounted_dimmable_load_control.id,
      clusters.LevelControl.attributes.Options:write(mock_device_mounted_dimmable_load_control, 7, clusters.LevelControl.types.OptionsBitmap.EXECUTE_IF_OFF)
    })
    mock_device_mounted_dimmable_load_control:expect_metadata_update({ profile = "switch-level" })
    mock_device_mounted_dimmable_load_control:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end,
  {
    test_init = function() test.mock_device.add_test_device(mock_device_mounted_dimmable_load_control) end,
    min_api_version = 17
  }
)

test.run_registered_tests()
