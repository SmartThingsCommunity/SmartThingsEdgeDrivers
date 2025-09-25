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
local clusters = require "st.matter.generated.zap_clusters"
local t_utils = require "integration_test.utils"
local test = require "integration_test"
local version = require "version"

local TRANSITION_TIME = 0
local OPTIONS_MASK = 0x01
local OPTIONS_OVERRIDE = 0x01

local mock_device_ep1 = 1
local mock_device_ep2 = 2

local mock_device = test.mock_device.build_test_matter_device({
  label = "Matter Switch",
  profile = t_utils.get_profile_definition("light-color-level-fan.yml"),
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
        {device_type_id = 0x0016, device_type_revision = 1} -- RootNode
      }
    },
    {
      endpoint_id = mock_device_ep1,
      clusters = {
        {cluster_id = clusters.OnOff.ID, cluster_type = "SERVER"},
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

local function test_init()
  test.disable_startup_messages()
  test.mock_device.add_test_device(mock_device)
  local subscribe_request = CLUSTER_SUBSCRIBE_LIST[1]:subscribe(mock_device)
  for i, clus in ipairs(CLUSTER_SUBSCRIBE_LIST) do
    if i > 1 then subscribe_request:merge(clus:subscribe(mock_device)) end
  end

  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})

  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "init" })
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})

  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
  mock_device:expect_metadata_update({ profile = "light-color-level-fan" })
  mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Switch capability should send the appropriate commands", function()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        { capability = "switch", component = "main", command = "on", args = { } }
      }
    )
    if version.api >= 11 then
      test.socket.devices:__expect_send(
        {
          "register_native_capability_cmd_handler",
          { device_uuid = mock_device.id, capability_id = "switch", capability_cmd_id = "on" }
        }
      )
    end
    test.socket.matter:__expect_send(
      {
        mock_device.id,
        clusters.OnOff.server.commands.On(mock_device, 1)
      }
    )
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        clusters.OnOff.attributes.OnOff:build_test_report_data(mock_device, mock_device_ep1, true)
      }
    )
    test.socket.devices:__expect_send(
      {
        "register_native_capability_attr_handler",
        { device_uuid = mock_device.id, capability_id = "switch", capability_attr_id = "switch" }
      }
    )

    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.switch.switch.on()
      )
    )
  end
)

test.register_message_test(
  "Set color temperature should send the appropriate commands",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "colorTemperature", component = "main", command = "setColorTemperature", args = {1800} }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.ColorControl.server.commands.MoveToColorTemperature(mock_device, mock_device_ep1, 556, TRANSITION_TIME, OPTIONS_MASK, OPTIONS_OVERRIDE)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.ColorControl.server.commands.MoveToColorTemperature:build_test_command_response(mock_device, mock_device_ep1)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.ColorControl.attributes.ColorTemperatureMireds:build_test_report_data(mock_device, mock_device_ep1, 556)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.colorTemperature.colorTemperature(1800))
    },
  }
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
  }
)

-- run the tests
test.run_registered_tests()
