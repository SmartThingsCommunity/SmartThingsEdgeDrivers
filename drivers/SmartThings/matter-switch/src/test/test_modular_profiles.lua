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
test.set_rpc_version(8)
local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local dkjson = require "dkjson"
local t_utils = require "integration_test.utils"
local uint32 = require "st.matter.data_types.Uint32"
local utils = require "st.utils"
local version = require "version"

local mock_device_tbl = {
  label = "Matter Switch",
  profile = t_utils.get_profile_definition("switch-color-level.yml"),
  manufacturer_info = {
    vendor_id = 0x0000,
    product_id = 0x0000,
  },
  endpoints = {
    {
      endpoint_id = 0,
      clusters = {
        {cluster_id = clusters.Basic.ID, cluster_type = "SERVER"}
      },
      device_types = {
        {device_type_id = 0x0016, device_type_revision = 1} -- RootNode
      }
    },
    {
      endpoint_id = 1,
      clusters = {
        {
          cluster_id = clusters.OnOff.ID,
          cluster_type = "SERVER",
          cluster_revision = 1,
          feature_map = 0 -- u32 bitmap
        },
        {cluster_id = clusters.ColorControl.ID, cluster_type = "BOTH", feature_map = 31},
        {cluster_id = clusters.LevelControl.ID, cluster_type = "SERVER", feature_map = 2}
      },
      device_types = {
        {device_type_id = 0x0100, device_type_revision = 1} -- On/Off Light
      }
    }
  }
}

local mock_device = test.mock_device.build_test_matter_device(mock_device_tbl)

local default_component_capabilities = {{"main", {"colorControl", "colorTemperature", "switchLevel"}}}
local optional_supported_component_capabilities = default_component_capabilities
local SUPPORTED_COMPONENT_CAPABILITIES = "__supported_component_capabilities"

local default_cluster_subscribe_list = {
  clusters.OnOff.attributes.OnOff,
  clusters.LevelControl.attributes.CurrentLevel,
  clusters.LevelControl.attributes.MaxLevel,
  clusters.LevelControl.attributes.MinLevel,
  clusters.ColorControl.attributes.CurrentHue,
  clusters.ColorControl.attributes.CurrentSaturation,
  clusters.ColorControl.attributes.CurrentX,
  clusters.ColorControl.attributes.CurrentY,
  clusters.ColorControl.attributes.ColorMode,
  clusters.ColorControl.attributes.ColorTemperatureMireds,
  clusters.ColorControl.attributes.ColorTempPhysicalMaxMireds,
  clusters.ColorControl.attributes.ColorTempPhysicalMinMireds
}

local cluster_subscribe_list = default_cluster_subscribe_list

local function subscribe(device, cluster_list)
  local subscribe_request = cluster_list[1]:subscribe(device)
  for i, cluster in ipairs(cluster_list) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(device))
    end
  end
  test.socket.matter:__expect_send({device.id, subscribe_request})
end

local function test_init()
  cluster_subscribe_list = utils.deep_copy(default_cluster_subscribe_list)
  optional_supported_component_capabilities = utils.deep_copy(default_component_capabilities)
  subscribe(mock_device, cluster_subscribe_list)
  test.mock_device.add_test_device(mock_device)
  mock_device:set_field(SUPPORTED_COMPONENT_CAPABILITIES, nil, {persist = true})
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
  if version.api >= 14 then
    mock_device:expect_metadata_update({ profile = "light-modular", optional_component_capabilities = optional_supported_component_capabilities })
    subscribe(mock_device, cluster_subscribe_list)
  end
  mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
end
test.set_test_init_function(test_init)

local function add_endpoint(endpoint, component, new_capabilities)
  table.insert(mock_device_tbl.endpoints, endpoint)
  mock_device = test.mock_device.build_test_matter_device(mock_device_tbl)
  local new_caps = {}
  for idx, comp in ipairs(optional_supported_component_capabilities) do
    if comp[1] == component then
      new_caps = comp[2]
      table.remove(optional_supported_component_capabilities, idx)
      break
    end
  end
  for _, cap in ipairs(new_capabilities) do
    table.insert(new_caps, cap)
  end
  local new_comp_caps = {component, new_caps}
  table.insert(optional_supported_component_capabilities, new_comp_caps)
  test.mock_device.add_test_device(mock_device)
end

local function remove_endpoint(endpoint_id)
  cluster_subscribe_list = utils.deep_copy(default_cluster_subscribe_list)
  optional_supported_component_capabilities = utils.deep_copy(default_component_capabilities)
  for idx, endpoint in ipairs(mock_device_tbl.endpoints) do
    if endpoint.endpoint_id == endpoint_id then
      table.remove(mock_device_tbl.endpoints, idx)
    end
  end
  mock_device = test.mock_device.build_test_matter_device(mock_device_tbl)
  test.mock_device.add_test_device(mock_device)
end

local tc1_cluster_subscribe_list = {
  clusters.OnOff.attributes.OnOff,
  clusters.LevelControl.attributes.CurrentLevel,
  clusters.LevelControl.attributes.MaxLevel,
  clusters.LevelControl.attributes.MinLevel,
  clusters.ColorControl.attributes.CurrentHue,
  clusters.ColorControl.attributes.CurrentSaturation,
  clusters.ColorControl.attributes.CurrentX,
  clusters.ColorControl.attributes.CurrentY,
  clusters.ColorControl.attributes.ColorMode,
  clusters.ColorControl.attributes.ColorTemperatureMireds,
  clusters.ColorControl.attributes.ColorTempPhysicalMaxMireds,
  clusters.ColorControl.attributes.ColorTempPhysicalMinMireds,
  clusters.ValveConfigurationAndControl.attributes.CurrentState,
  clusters.ValveConfigurationAndControl.attributes.CurrentLevel
}

test.register_coroutine_test(
  "Test driver switched event following valve endpoint being added to the device",
  function()
    local new_endpoint = {
      endpoint_id = 2,
      clusters = {
        {cluster_id = clusters.ValveConfigurationAndControl.ID, cluster_type = "SERVER", feature_map = 2}
      },
      device_types = {
        {device_type_id = 0x0042, device_type_revision = 1}
      }
    }
    add_endpoint(new_endpoint, "main", {"valve", "level"})
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "driverSwitched" })
    if version.api >= 14 then
      -- This functionality would only be expected to work with modular profiles. On lower FW versions,
      -- adding new functionality to the device would require re-onboarding in order to make it work.
      mock_device:expect_metadata_update({ profile = "light-modular", optional_component_capabilities = optional_supported_component_capabilities })
      subscribe(mock_device, tc1_cluster_subscribe_list)
      -- The new attributes won't be subscribed to until infoChanged occurs
      local device_info_copy = utils.deep_copy(mock_device.raw_st_data)
      device_info_copy.profile.id = "matter-thing"
      local device_info_json = dkjson.encode(device_info_copy)
      test.socket.device_lifecycle:__queue_receive({ mock_device.id, "infoChanged", device_info_json })
      subscribe(mock_device, tc1_cluster_subscribe_list)
      test.wait_for_events()
      test.socket.matter:__queue_receive(
        {
          mock_device.id,
          clusters.ValveConfigurationAndControl.server.attributes.CurrentState:build_test_report_data(mock_device, 1, 1)
        }
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message(
          "main", capabilities.valve.valve.open()
        )
      )
    else
      mock_device:expect_metadata_update({ profile = "water-valve-level" })
    end
    remove_endpoint(2)
  end
)

local tc2_cluster_subscribe_list = {
  clusters.OnOff.attributes.OnOff,
  clusters.LevelControl.attributes.CurrentLevel,
  clusters.LevelControl.attributes.MaxLevel,
  clusters.LevelControl.attributes.MinLevel,
  clusters.ColorControl.attributes.CurrentHue,
  clusters.ColorControl.attributes.CurrentSaturation,
  clusters.ColorControl.attributes.CurrentX,
  clusters.ColorControl.attributes.CurrentY,
  clusters.ColorControl.attributes.ColorMode,
  clusters.ColorControl.attributes.ColorTemperatureMireds,
  clusters.ColorControl.attributes.ColorTempPhysicalMaxMireds,
  clusters.ColorControl.attributes.ColorTempPhysicalMinMireds,
  clusters.PowerSource.server.attributes.BatPercentRemaining,
  clusters.Switch.events.InitialPress,
  clusters.Switch.events.LongPress,
  clusters.Switch.events.ShortRelease,
  clusters.Switch.events.MultiPressComplete
}

test.register_coroutine_test(
  "Test driver switched event following button endpoint being added to the device",
  function()
    local new_endpoint = {
      endpoint_id = 2,
      clusters = {
        {
          cluster_id = clusters.Switch.ID,
          feature_map = clusters.Switch.types.Feature.MOMENTARY_SWITCH,
          cluster_type = "SERVER"
        },
        {
          cluster_id = clusters.PowerSource.ID,
          cluster_type = "SERVER",
          feature_map = clusters.PowerSource.types.Feature.BATTERY
        }
      },
      device_types = {
        {device_type_id = 0x000F, device_type_revision = 1}
      }
    }
    local new_endpoint2 = {
      endpoint_id = 3,
      clusters = {
        {
          cluster_id = clusters.Switch.ID,
          feature_map = clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH |
            clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_MULTI_PRESS |
            clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_LONG_PRESS,
          cluster_type = "SERVER"
        }
      },
      device_types = {
        {device_type_id = 0x000F, device_type_revision = 1}
      }
    }
    add_endpoint(new_endpoint, "button1", {"button", "battery"})
    add_endpoint(new_endpoint2, "button2", {"button"})
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "driverSwitched" })
    local read_attribute_list = clusters.PowerSource.attributes.AttributeList:read()
    test.socket.matter:__expect_send({mock_device.id, read_attribute_list})
    if version.api >= 14 then test.wait_for_events() end
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        clusters.PowerSource.attributes.AttributeList:build_test_report_data(mock_device, 1, {uint32(12)})
      }
    )
    if version.api >= 14 then
      -- This functionality would only be expected to work with modular profiles. On lower FW versions,
      -- adding new functionality to the device would require re-onboarding in order to make it work.
      mock_device:expect_metadata_update({ profile = "light-modular", optional_component_capabilities = optional_supported_component_capabilities })
      subscribe(mock_device, tc2_cluster_subscribe_list)
      -- The new attributes won't be subscribed to until infoChanged occurs
      local device_info_copy = utils.deep_copy(mock_device.raw_st_data)
      device_info_copy.profile.id = "switch-modular"
      local device_info_json = dkjson.encode(device_info_copy)
      test.wait_for_events()
      test.socket.device_lifecycle:__queue_receive({ mock_device.id, "infoChanged", device_info_json })
      cluster_subscribe_list = utils.deep_copy(default_cluster_subscribe_list)
      subscribe(mock_device, tc2_cluster_subscribe_list)
    else
      mock_device:expect_metadata_update({ profile = "2-button-battery" })
      mock_device:expect_device_create({
        type = "EDGE_CHILD",
        label = "Matter Switch 1",
        profile = "light-binary",
        parent_device_id = mock_device.id,
        parent_assigned_child_key = string.format("%d", 1)
      })
    end
    remove_endpoint(2)
    remove_endpoint(3)
  end
)

test.run_registered_tests()
