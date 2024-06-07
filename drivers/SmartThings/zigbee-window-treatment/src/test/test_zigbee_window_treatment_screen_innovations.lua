-- Copyright 2024 SmartThings
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

local Basic = clusters.Basic
local WindowCovering = clusters.WindowCovering
local PowerConfiguration = clusters.PowerConfiguration

local mock_device = test.mock_device.build_test_zigbee_device(
    {
      profile = t_utils.get_profile_definition("window-treatment-powerSource.yml"),
      fingerprinted_endpoint_id = 0x01,
      zigbee_endpoints = {
        [1] = {
          id = 1,
          manufacturer = "Screen Innovations",
          model = "WM25/L-Z",
          server_clusters = {0x0000, 0x0001, 0x0102}
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
    "Window Shade state open",
    function()
      test.socket.capability:__set_channel_ordering("relaxed")
      test.socket.zigbee:__queue_receive(
        {
          mock_device.id,
          WindowCovering.attributes.CurrentPositionLiftPercentage:build_test_attr_report(mock_device, 0)
        }
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.windowShade.windowShade.open())
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(0))
      )
    end
)

test.register_coroutine_test(
    "Window Shade state closed",
    function()
      test.socket.capability:__set_channel_ordering("relaxed")
      test.socket.zigbee:__queue_receive(
        {
          mock_device.id,
          WindowCovering.attributes.CurrentPositionLiftPercentage:build_test_attr_report(mock_device, 100)
        }
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.windowShade.windowShade.closed())
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(100))
      )
    end
)

test.register_coroutine_test(
    "Window Shade state partially open",
    function()
      test.socket.capability:__set_channel_ordering("relaxed")
      test.socket.zigbee:__queue_receive(
        {
          mock_device.id,
          WindowCovering.attributes.CurrentPositionLiftPercentage:build_test_attr_report(mock_device, 25)
        }
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.windowShade.windowShade.partially_open())
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(25))
      )
    end
)

test.register_coroutine_test(
    "WindowShade open cmd test case",
    function()
      test.socket.capability:__queue_receive(
          {
            mock_device.id,
            { capability = "windowShade", component = "main", command = "open", args = {} }
          }
      )
      test.socket.zigbee:__expect_send({
        mock_device.id,
        WindowCovering.server.commands.UpOrOpen(mock_device)
      })
      test.wait_for_events()
    end
)

test.register_coroutine_test(
    "WindowShade close cmd test case",
    function()
      test.socket.capability:__queue_receive(
          {
            mock_device.id,
            { capability = "windowShade", component = "main", command = "close", args = {} }
          }
      )
      test.socket.zigbee:__expect_send({
        mock_device.id,
        WindowCovering.server.commands.DownOrClose(mock_device)
      })
      test.wait_for_events()
    end
)

test.register_coroutine_test(
    "WindowShade pause cmd test case",
    function()
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
      test.wait_for_events()
    end
)

test.register_coroutine_test(
    "Battery Percentage Remaining test cases",
    function()
      mock_device:set_field("motorState", "idle")
      local battery_test_map = {
          [200] = 100,
          [100] = 50,
          [0] = 0
      }
      for bat_perc_rem, batt_perc_out in pairs(battery_test_map) do
        test.socket.zigbee:__queue_receive({ mock_device.id,
          PowerConfiguration.attributes.BatteryPercentageRemaining:build_test_attr_report(mock_device, bat_perc_rem) })
        test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.battery.battery(batt_perc_out)) )
        test.wait_for_events()
      end
    end
)

test.register_coroutine_test(
  "Refresh should generate expected messages",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.capability:__queue_receive({ mock_device.id, { capability = "refresh", component = "main", command = "refresh", args = {} } })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      WindowCovering.attributes.CurrentPositionLiftPercentage:read(mock_device)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      Basic.attributes.PowerSource:read(mock_device)
    })
  end
)

test.register_coroutine_test(
  "doConfigure should generate expected messages",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
    test.socket.zigbee:__set_channel_ordering("relaxed")
    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, PowerConfiguration.ID)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      PowerConfiguration.attributes.BatteryPercentageRemaining:configure_reporting(mock_device, 30, 21600, 1)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, WindowCovering.ID)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      WindowCovering.attributes.CurrentPositionLiftPercentage:configure_reporting(mock_device, 0, 600, 1)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, WindowCovering.ID)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      WindowCovering.attributes.CurrentPositionLiftPercentage:configure_reporting(mock_device, 1, 3600, 1)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, PowerConfiguration.ID)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      PowerConfiguration.attributes.BatteryPercentageRemaining:configure_reporting(mock_device, 1, 3600, 1)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, Basic.ID)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      Basic.attributes.PowerSource:configure_reporting(mock_device, 1, 3600)
    })

    -- read values after delay
    test.mock_time.advance_time(3)
    test.socket.zigbee:__expect_send({
      mock_device.id,
      WindowCovering.attributes.CurrentPositionLiftPercentage:read(mock_device)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      Basic.attributes.PowerSource:read(mock_device)
    })
  end
)

test.run_registered_tests()