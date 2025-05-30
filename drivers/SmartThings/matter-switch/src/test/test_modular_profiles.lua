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
local utils = require "st.utils"
local version = require "version"

local mock_device = test.mock_device.build_test_matter_device({
  label = "Matter Switch",
  profile = t_utils.get_profile_definition("water-valve-modular.yml"),
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
        {cluster_id = clusters.ValveConfigurationAndControl.ID, cluster_type = "SERVER", feature_map = 2},
        {cluster_id = clusters.OnOff.ID, cluster_type = "SERVER", cluster_revision = 1, feature_map = 0},
        {cluster_id = clusters.ColorControl.ID, cluster_type = "BOTH", feature_map = 31},
        {cluster_id = clusters.LevelControl.ID, cluster_type = "SERVER", feature_map = 2}
      },
      device_types = {
        {device_type_id = 0x0042, device_type_revision = 1}, -- Water Valve
        {device_type_id = 0x0100, device_type_revision = 1}  -- On/Off Light
      }
    }
  }
})

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

local function test_init()
  local subscribe_request = tc1_cluster_subscribe_list[1]:subscribe(mock_device)
  for i, cluster in ipairs(tc1_cluster_subscribe_list) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(mock_device))
    end
  end
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})
  test.mock_device.add_test_device(mock_device)
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
  local optional_component_capabilities = {
    { "main", { "valve", "level", "switch", "switchLevel", "colorControl", "colorTemperature" } }
  }
  if version.api >= 14 then
    mock_device:expect_metadata_update({ profile = "water-valve-modular", optional_component_capabilities = optional_component_capabilities })
  else
    mock_device:expect_metadata_update({ profile = "water-valve-level" })
  end
  mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  local device_info_copy = utils.deep_copy(mock_device.raw_st_data)
  device_info_copy.profile.id = "switch-color-level"
  local device_info_json = dkjson.encode(device_info_copy)
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "infoChanged", device_info_json })
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})
end
test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Test water valve modular profiling",
  function()
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
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        { capability = "colorControl", component = "main", command = "setColor", args = { { hue = 50, saturation = 50 } }},
      }
    )
    local TRANSITION_TIME = 0
    local OPTIONS_MASK = 0x01
    local OPTIONS_OVERRIDE = 0x01
    local hue = math.floor((50 * 0xFE) / 100.0 + 0.5)
    local sat = math.floor((50 * 0xFE) / 100.0 + 0.5)
    test.socket.matter:__expect_send(
      {
        mock_device.id,
        clusters.ColorControl.server.commands.MoveToHueAndSaturation(mock_device, 1, hue, sat, TRANSITION_TIME, OPTIONS_MASK, OPTIONS_OVERRIDE)
      }
    )
  end
)

test.run_registered_tests()
