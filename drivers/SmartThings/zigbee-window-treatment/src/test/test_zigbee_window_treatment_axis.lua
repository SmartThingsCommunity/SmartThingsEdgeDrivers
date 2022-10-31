-- Copyright 2022 SmartThings
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

-- Mock out globals
local base64 = require "st.base64"
local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local test = require "integration_test"
local t_utils = require "integration_test.utils"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"

local Basic = clusters.Basic
local Level = clusters.Level
local PowerConfiguration = clusters.PowerConfiguration
local WindowCovering = clusters.WindowCovering

local swbuild_payload_newer = "102-5.3.5.1125"

local mock_device = test.mock_device.build_test_zigbee_device(
    { profile = t_utils.get_profile_definition("window-treatment-battery.yml"),
      fingerprinted_endpoint_id = 0x01,
      zigbee_endpoints = {
        [1] = {
          id = 1,
          manufacturer = "AXIS",
          model = "Gear",
          server_clusters = {0x0000, 0x0003, 0x0006, 0x0008, 0x0102, 0x0020, 0x0001}
        }
      }
    }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device)
  zigbee_test_utils.init_noop_health_check_timer()
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
    "Level Cluster Attribute handling",
    function()
      test.socket.zigbee:__queue_receive(
        {
          mock_device.id,
          Level.attributes.CurrentLevel:build_test_attr_report(mock_device, 0)
        }
      )
      test.socket.capability:__set_channel_ordering("relaxed")
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(0))
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.windowShade.windowShade.closed())
      )
      test.socket.zigbee:__queue_receive({
          mock_device.id,
          Level.attributes.CurrentLevel:build_test_attr_report(mock_device, 254)
      })
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(100))
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.windowShade.windowShade.open())
      )
      test.socket.zigbee:__queue_receive({
          mock_device.id,
          Level.attributes.CurrentLevel:build_test_attr_report(mock_device, math.floor(25 / 100 * 254))
      })
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(25))
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.windowShade.windowShade.partially_open())
      )
    end
)

test.register_coroutine_test(
    "Level Cluster Attribute handling with software build version",
    function()
      test.socket.zigbee:__queue_receive(
        {
          mock_device.id,
          Basic.attributes.SWBuildID:build_test_attr_report(mock_device, swbuild_payload_newer)
        }
      )
      test.wait_for_events()
      test.socket.capability:__set_channel_ordering("relaxed")
      test.socket.zigbee:__queue_receive(
        {
          mock_device.id,
          Level.attributes.CurrentLevel:build_test_attr_report(mock_device, 83)
        }
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(33))
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.windowShade.windowShade.opening())
      )
      test.socket.zigbee:__queue_receive(
        {
          mock_device.id,
          Level.attributes.CurrentLevel:build_test_attr_report(mock_device, 60)
        }
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(24))
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.windowShade.windowShade.closing())
      )
    end
)

test.register_coroutine_test(
    "WindowCovering cluster handling",
    function()
      test.socket.zigbee:__queue_receive(
        {
          mock_device.id,
          Basic.attributes.SWBuildID:build_test_attr_report(mock_device, swbuild_payload_newer)
        }
      )
      test.wait_for_events()
      test.socket.zigbee:__queue_receive(
        {
          mock_device.id,
          WindowCovering.attributes.CurrentPositionLiftPercentage:build_test_attr_report(mock_device, 100)
        }
      )
      test.socket.capability:__set_channel_ordering("relaxed")
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(0))
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.windowShade.windowShade.closed())
      )
      test.socket.zigbee:__queue_receive(
        {
          mock_device.id,
          WindowCovering.attributes.CurrentPositionLiftPercentage:build_test_attr_report(mock_device, 0)
        }
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(100))
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.windowShade.windowShade.open())
      )
      test.socket.zigbee:__queue_receive(
        {
          mock_device.id,
          WindowCovering.attributes.CurrentPositionLiftPercentage:build_test_attr_report(mock_device, 83)
        }
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(17))
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.windowShade.windowShade.partially_open())
      )
    end
)

test.register_coroutine_test(
    "Close Command Handler",
    function()
      test.socket.capability:__queue_receive(
        {
          mock_device.id,
          { capability = "windowShade", component = "main", command = "close", args = {} }
        }
      )
      test.socket.capability:__set_channel_ordering("relaxed")
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.windowShade.windowShade.closing())
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(0))
      )
      test.socket.zigbee:__expect_send(
        {
          mock_device.id,
          Level.server.commands.MoveToLevelWithOnOff(mock_device)
        }
      )
    end
)

test.register_coroutine_test(
    "Close Command Handler with software build handler",
    function()
      test.socket.zigbee:__queue_receive(
        {
          mock_device.id,
          Basic.attributes.SWBuildID:build_test_attr_report(mock_device, swbuild_payload_newer)
        }
      )
      test.wait_for_events()
      test.socket.capability:__queue_receive(
        {
          mock_device.id,
          { capability = "windowShade", component = "main", command = "close", args = {} }
        }
      )
      test.socket.capability:__set_channel_ordering("relaxed")
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.windowShade.windowShade.closing())
      )
      test.socket.zigbee:__expect_send(
        {
          mock_device.id,
          WindowCovering.server.commands.DownOrClose(mock_device)
        }
      )
    end
)

test.register_coroutine_test(
    "Open Command Handler",
    function()
      test.socket.capability:__queue_receive(
        {
          mock_device.id,
          { capability = "windowShade", component = "main", command = "open", args = {} }
        }
      )
      test.socket.capability:__set_channel_ordering("relaxed")
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(100))
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.windowShade.windowShade.opening())
      )
      test.socket.zigbee:__expect_send(
        {
          mock_device.id,
          Level.server.commands.MoveToLevelWithOnOff(mock_device, 0xFE)
        }
      )
    end
)

test.register_coroutine_test(
    "Open Command Handler with software build handler",
    function()
      test.socket.zigbee:__queue_receive(
        {
          mock_device.id,
          Basic.attributes.SWBuildID:build_test_attr_report(mock_device, swbuild_payload_newer)
        }
      )
      test.wait_for_events()
      test.socket.capability:__queue_receive(
        {
          mock_device.id,
          { capability = "windowShade", component = "main", command = "open", args = {} }
        }
      )
      test.socket.capability:__set_channel_ordering("relaxed")
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.windowShade.windowShade.opening())
      )
      test.socket.zigbee:__expect_send(
        {
          mock_device.id,
          WindowCovering.server.commands.UpOrOpen(mock_device, 0x64)
        }
      )
    end
)

test.register_coroutine_test(
    "Pause Command Handler",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(5, "oneshot")
      test.socket.capability:__queue_receive(
        {
          mock_device.id,
          { capability = "windowShade", component = "main", command = "open", args = {} }
        }
      )
      test.socket.capability:__set_channel_ordering("relaxed")
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(100))
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.windowShade.windowShade.opening())
      )
      test.socket.zigbee:__expect_send(
        {
          mock_device.id,
          Level.server.commands.MoveToLevelWithOnOff(mock_device, 254)
        }
      )
      test.socket.capability:__queue_receive(
        {
          mock_device.id,
          { capability = "windowShade", component = "main", command = "pause", args = {} }
        }
      )
      test.mock_time.advance_time(5)
      test.socket.zigbee:__expect_send({
        mock_device.id,
        Level.attributes.CurrentLevel:read(mock_device)
      })
    end
)

test.register_coroutine_test(
    "Pause Command Handler with software build handler",
    function()
      test.socket.zigbee:__queue_receive(
        {
          mock_device.id,
          Basic.attributes.SWBuildID:build_test_attr_report(mock_device, swbuild_payload_newer)
        }
      )
      test.wait_for_events()
      test.socket.capability:__queue_receive(
        {
          mock_device.id,
          { capability = "windowShade", component = "main", command = "open", args = {} }
        }
      )
      test.socket.capability:__set_channel_ordering("relaxed")
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.windowShade.windowShade.opening())
      )
      test.socket.zigbee:__expect_send(
        {
          mock_device.id,
          WindowCovering.server.commands.UpOrOpen(mock_device, 0x64)
        }
      )
      test.socket.capability:__queue_receive(
        {
          mock_device.id,
          { capability = "windowShade", component = "main", command = "pause", args = {} }
        }
      )
      test.socket.zigbee:__expect_send({
        mock_device.id,
        WindowCovering.server.commands.Stop(mock_device)
      })
    end
)

test.register_coroutine_test(
    "Set Shade Level Command Handler",
    function()
      test.socket.capability:__queue_receive(
        {
          mock_device.id,
          { capability = "windowShadeLevel", component = "main", command = "setShadeLevel", args = { 33 } }
        }
      )
      test.socket.capability:__set_channel_ordering("relaxed")
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(33))
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.windowShade.windowShade.opening())
      )
      test.socket.zigbee:__expect_send(
        {
          mock_device.id,
          Level.server.commands.MoveToLevelWithOnOff(mock_device, 84)
        }
      )
    end
)

test.register_coroutine_test(
    "Set Shade Level Command Handler with software version handler",
    function()
      test.socket.zigbee:__queue_receive(
        {
          mock_device.id,
          Basic.attributes.SWBuildID:build_test_attr_report(mock_device, swbuild_payload_newer)
        }
      )
      test.wait_for_events()
      test.socket.capability:__queue_receive(
        {
          mock_device.id,
          { capability = "windowShadeLevel", component = "main", command = "setShadeLevel", args = { 33 } }
        }
      )
      test.socket.capability:__set_channel_ordering("relaxed")
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(33))
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.windowShade.windowShade.opening())
      )
      test.socket.zigbee:__expect_send(
        {
          mock_device.id,
          WindowCovering.server.commands.GoToLiftPercentage(mock_device, 100 - 33)
        }
      )
    end
)

test.register_coroutine_test(
    "Set Preset Shade Level Command Handler",
    function()
      test.socket.capability:__queue_receive(
        {
          mock_device.id,
          { capability = "windowShadePreset", component = "main", command = "presetPosition", args = {} }
        }
      )
      test.socket.capability:__set_channel_ordering("relaxed")
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(50))
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.windowShade.windowShade.opening())
      )
      test.socket.zigbee:__expect_send(
        {
          mock_device.id,
          Level.server.commands.MoveToLevelWithOnOff(mock_device, 127)
        }
      )
    end
)

test.register_coroutine_test(
    "Set Preset Shade Level Command Handler with software version handler with infoChanged",
    function()
      test.socket.device_lifecycle():__queue_receive(mock_device:generate_info_changed({preferences = {presetPosition = 30}}))
      test.socket.zigbee:__queue_receive(
        {
          mock_device.id,
          Basic.attributes.SWBuildID:build_test_attr_report(mock_device, swbuild_payload_newer)
        }
      )
      test.wait_for_events()
      test.socket.capability:__queue_receive(
        {
          mock_device.id,
          { capability = "windowShadePreset", component = "main", command = "presetPosition", args = {} }
        }
      )
      test.socket.capability:__set_channel_ordering("relaxed")
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(30))
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.windowShade.windowShade.opening())
      )
      test.socket.zigbee:__expect_send(
        {
          mock_device.id,
          WindowCovering.server.commands.GoToLiftPercentage(mock_device, 100 - 30)
        }
      )
    end
)

test.register_coroutine_test(
    "Set Preset Shade Level Command Handler with software version handler",
    function()
      test.socket.zigbee:__queue_receive(
        {
          mock_device.id,
          Basic.attributes.SWBuildID:build_test_attr_report(mock_device, swbuild_payload_newer)
        }
      )
      test.wait_for_events()
      test.socket.capability:__queue_receive(
        {
          mock_device.id,
          { capability = "windowShadePreset", component = "main", command = "presetPosition", args = {} }
        }
      )
      test.socket.capability:__set_channel_ordering("relaxed")
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(50))
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.windowShade.windowShade.opening())
      )
      test.socket.zigbee:__expect_send(
        {
          mock_device.id,
          WindowCovering.server.commands.GoToLiftPercentage(mock_device, 100 - 50)
        }
      )
    end
)

test.register_coroutine_test(
    "Refresh should read all necessary attributes with software build handler",
    function()
      test.socket.environment_update:__queue_receive({ "zigbee", { hub_zigbee_id = base64.encode(zigbee_test_utils.mock_hub_eui) } })
      test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added"})
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.windowShade.supportedWindowShadeCommands({ "open", "close", "pause" },{ visibility = { displayed = false }}))
      )
      test.socket.zigbee:__expect_send({
        mock_device.id,
        Basic.attributes.SWBuildID:read(mock_device)
      })
      test.wait_for_events()
      test.socket.zigbee:__queue_receive(
        {
          mock_device.id,
          Basic.attributes.SWBuildID:build_test_attr_report(mock_device, swbuild_payload_newer)
        }
      )
      test.wait_for_events()
      test.socket.zigbee:__set_channel_ordering("relaxed")
      test.socket.capability:__queue_receive({
        mock_device.id,
        {
          capability = "refresh", component = "main", command = "refresh", args = {}
        }
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device)
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercentage:read(mock_device)
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        Basic.attributes.SWBuildID:read(mock_device)
      })
    end
)

test.register_coroutine_test(
    "Refresh should read all necessary attributes",
    function()
      test.socket.environment_update:__queue_receive({ "zigbee", { hub_zigbee_id = base64.encode(zigbee_test_utils.mock_hub_eui) } })
      test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added"})
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.windowShade.supportedWindowShadeCommands({ "open", "close", "pause" },{ visibility = { displayed = false }}))
      )
      test.socket.zigbee:__expect_send({
        mock_device.id,
        Basic.attributes.SWBuildID:read(mock_device)
      })
      test.wait_for_events()
      test.socket.zigbee:__set_channel_ordering("relaxed")
      test.socket.capability:__queue_receive({
        mock_device.id,
        {
          capability = "refresh", component = "main", command = "refresh", args = {}
        }
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        Level.attributes.CurrentLevel:read(mock_device)
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device)
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        Basic.attributes.SWBuildID:read(mock_device)
      })
    end
)

test.register_coroutine_test(
    "Configure should configure all necessary attributes",
    function()
      test.socket.environment_update:__queue_receive({ "zigbee", { hub_zigbee_id = base64.encode(zigbee_test_utils.mock_hub_eui) } })
      test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added"})
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.windowShade.supportedWindowShadeCommands({ "open", "close", "pause" },{ visibility = { displayed = false }}))
      )
      test.socket.zigbee:__expect_send({
        mock_device.id,
        Basic.attributes.SWBuildID:read(mock_device)
      })
      test.wait_for_events()

      test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
      test.socket.zigbee:__set_channel_ordering("relaxed")
      mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercentage:configure_reporting(mock_device, 1, 3600, 1)
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        zigbee_test_utils.build_bind_request(mock_device,
                                              zigbee_test_utils.mock_hub_eui,
                                              WindowCovering.ID)
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        Level.attributes.CurrentLevel:configure_reporting(mock_device, 1, 3600, 1)
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        zigbee_test_utils.build_bind_request(mock_device,
                                              zigbee_test_utils.mock_hub_eui,
                                              Level.ID)
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        PowerConfiguration.attributes.BatteryPercentageRemaining:configure_reporting(mock_device, 1, 3600, 1)
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        zigbee_test_utils.build_bind_request(mock_device,
                                              zigbee_test_utils.mock_hub_eui,
                                              PowerConfiguration.ID)
      })
    end
)

test.run_registered_tests()
