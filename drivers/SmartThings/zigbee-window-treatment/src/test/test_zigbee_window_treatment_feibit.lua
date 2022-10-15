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
local test = require "integration_test"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"

local Level = clusters.Level

local mock_device = test.mock_device.build_test_zigbee_device(
    { profile = t_utils.get_profile_definition("window-treatment-profile.yml"),
      fingerprinted_endpoint_id = 0x01,
      zigbee_endpoints = {
        [1] = {
          id = 1,
          manufacturer = "Feibit Co.Ltd",
          model = "FTB56-ZT218AK1.6",
          server_clusters = {0x0000, 0x0003, 0x0004, 0x0005, 0x0006, 0x0008, 0x0102}
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
    "State transition from opening to partially open",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.zigbee:__queue_receive(
        {
          mock_device.id,
          Level.attributes.CurrentLevel:build_test_attr_report(mock_device, 1)
        }
      )
      test.socket.capability:__expect_send(
          {
            mock_device.id,
            {
              capability_id = "windowShadeLevel", component_id = "main",
              attribute_id = "shadeLevel", state = { value = 2 }
            }
          }
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.windowShade.windowShade.opening())
      )
      test.mock_time.advance_time(2)
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.windowShade.windowShade.partially_open())
      )
      test.wait_for_events()
    end
)

test.register_coroutine_test(
    "State transition from opening to closing",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.zigbee:__queue_receive(
        {
          mock_device.id,
          Level.attributes.CurrentLevel:build_test_attr_report(mock_device, 10)
        }
      )
      test.socket.capability:__expect_send(
          {
            mock_device.id,
            {
              capability_id = "windowShadeLevel", component_id = "main",
              attribute_id = "shadeLevel", state = { value = 25 }
            }
          }
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.windowShade.windowShade.opening())
      )
      test.mock_time.advance_time(2)
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.windowShade.windowShade.partially_open())
      )
      test.wait_for_events()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.zigbee:__queue_receive({
        mock_device.id,
        Level.attributes.CurrentLevel:build_test_attr_report(mock_device, 5)
      })
      test.socket.capability:__expect_send({
        mock_device.id,
        {
          capability_id = "windowShadeLevel", component_id = "main",
          attribute_id = "shadeLevel", state = { value = 12 }
        }
      })
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.windowShade.windowShade.closing())
      )
      test.mock_time.advance_time(3)
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.windowShade.windowShade.partially_open())
      )
      test.wait_for_events()
    end
)

test.register_message_test(
    "Handle Window shade open command",
    {
      {
        channel = "capability",
        direction = "receive",
        message = {
          mock_device.id,
          {
            capability = "windowShade", component = "main", command = "open", args = {}
          }
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_device.id, clusters.WindowCovering.server.commands.UpOrOpen(mock_device) }
      }
    }
)

test.register_message_test(
    "Handle Window shade close command",
    {
      {
        channel = "capability",
        direction = "receive",
        message = {
          mock_device.id,
          {
            capability = "windowShade", component = "main", command = "close", args = {}
          }
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = {
          mock_device.id,
          clusters.WindowCovering.server.commands.DownOrClose(mock_device)
        }
      }
    }
)

test.register_message_test(
    "Handle Window shade pause command",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_device.id, { capability = "windowShade", component = "main", command = "pause", args = {} } }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = {
          mock_device.id,
          clusters.WindowCovering.server.commands.Stop(mock_device)
        }
      }
    }
)

test.register_message_test(
    "Handle Window Shade level command",
    {
      {
        channel = "capability",
        direction = "receive",
        message = {
          mock_device.id,
          {
            capability = "windowShadeLevel", component = "main",
            command = "setShadeLevel", args = { 33 }
          }
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = {
          mock_device.id,
          Level.server.commands.MoveToLevelWithOnOff(mock_device,math.floor(33/100 * 254))
        }
      }
    }
)

test.register_coroutine_test(
  "windowShadePreset capability should be handled with preset value of 30",
  function()
    test.socket.device_lifecycle():__queue_receive(mock_device:generate_info_changed({preferences = {presetPosition = 30}}))
    test.wait_for_events()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        { capability = "windowShadePreset", component = "main", command = "presetPosition", args = {} }
      }
    )
    test.socket.zigbee:__expect_send({
      mock_device.id,
      Level.server.commands.MoveToLevelWithOnOff(mock_device,math.floor(30/100 * 254))
    })
  end
)

test.register_coroutine_test(
  "windowShadePreset capability should be handled without any preset value ",
  function()
    test.socket.device_lifecycle():__queue_receive(mock_device:generate_info_changed({preferences = {}}))
    test.wait_for_events()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        { capability = "windowShadePreset", component = "main", command = "presetPosition", args = {} }
      }
    )
    test.socket.zigbee:__expect_send({
      mock_device.id,
      Level.server.commands.MoveToLevelWithOnOff(mock_device,math.floor(50/100 * 254))
    })
  end
)

test.register_coroutine_test(
  "windowShadePreset capability should be handled with preset value = 100 ",
  function()
    test.socket.device_lifecycle():__queue_receive(mock_device:generate_info_changed({preferences = {presetPosition = 100}}))
    test.wait_for_events()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        { capability = "windowShadePreset", component = "main", command = "presetPosition", args = {} }
      }
    )
    test.socket.zigbee:__expect_send({
      mock_device.id,
      Level.server.commands.MoveToLevelWithOnOff(mock_device,math.floor(100/100 * 254))
    })
  end
)

test.register_coroutine_test(
  "windowShadePreset capability should be handled with preset value = 1 ",
  function()
    test.socket.device_lifecycle():__queue_receive(mock_device:generate_info_changed({preferences = {presetPosition = 1}}))
    test.wait_for_events()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        { capability = "windowShadePreset", component = "main", command = "presetPosition", args = {} }
      }
    )
    test.socket.zigbee:__expect_send({
      mock_device.id,
      Level.server.commands.MoveToLevelWithOnOff(mock_device,math.floor(1/100 * 254))
    })
  end
)

test.register_coroutine_test(
  "windowShadePreset capability should be handled with a positive preset value of < 1",
  function()
    test.socket.device_lifecycle():__queue_receive(mock_device:generate_info_changed({preferences = {presetPosition = 0}}))
    test.wait_for_events()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        { capability = "windowShadePreset", component = "main", command = "presetPosition", args = {} }
      }
    )
    test.socket.zigbee:__expect_send({
      mock_device.id,
      Level.server.commands.MoveToLevelWithOnOff(mock_device,math.floor(0/100 * 254))
    })
  end
)

test.register_message_test(
    "Handle Window Shade Preset command",
    {
      {
        channel = "capability",
        direction = "receive",
        message = {
          mock_device.id,
          {
            capability = "windowShadePreset", component = "main",
            command = "presetPosition", args = {}
          }
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = {
          mock_device.id,
          Level.server.commands.MoveToLevelWithOnOff(mock_device, math.floor(50 / 100 * 254))
        }
      }
    }
)

test.register_coroutine_test(
    "Refresh necessary attributes",
    function()
      test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.windowShade.supportedWindowShadeCommands({ "open", "close", "pause" },{ visibility = { displayed = false }}))
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
        Level.attributes.CurrentLevel:read(mock_device)
      })
    end
)

test.register_coroutine_test(
    "Configure should configure all necessary attributes",
    function()
      test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added"})
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.windowShade.supportedWindowShadeCommands({ "open", "close", "pause" },{ visibility = { displayed = false }}))
      )
      test.wait_for_events()

      test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
      test.socket.zigbee:__set_channel_ordering("relaxed")
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
      mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    end
)

test.run_registered_tests()
