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
local data_types = require "st.zigbee.data_types"

local Basic = clusters.Basic
local WindowCovering = clusters.WindowCovering
local PowerConfiguration = clusters.PowerConfiguration

local MFG_CODE = 0x1228
local PRIVATE_CLUSTER_ID = 0xFCCC
local PRIVATE_ATTRIBUTE_ID = 0x0012

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
    "Motor direction idle with Window Shade state partially open",
    function()
      test.socket.capability:__set_channel_ordering("relaxed")
      local attr_report_data = {
        { PRIVATE_ATTRIBUTE_ID, data_types.Uint8.ID, 0 }-- device sends 0 for idle
      }
      test.socket.zigbee:__queue_receive({
            mock_device.id,
            zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
      })
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

test.register_coroutine_test(
    "added should generate expected messages",
    function()
      test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added"})
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main",
          capabilities.windowShade.supportedWindowShadeCommands({ "open", "close", "pause" },{ visibility = { displayed = false }}))
      )
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.wait_for_events()
      test.socket.zigbee:__set_channel_ordering("relaxed")

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

test.register_coroutine_test(
  "Motor direction opening with window_shade_level_cmd",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    local attr_report_data = {
          { PRIVATE_ATTRIBUTE_ID, data_types.Uint8.ID, 1 }-- device sends 1 for opening
    }
    test.socket.zigbee:__queue_receive({
          mock_device.id,
          zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })

    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        { capability = "windowShadeLevel", component = "main", command = "setShadeLevel", args = { 45 } }
      }
    )
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        WindowCovering.server.commands.GoToLiftPercentage(mock_device, 45)
      }
    )

    test.socket.zigbee:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercentage:build_test_attr_report(mock_device, 45)
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShade.windowShade.opening())
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(45))
    )
  end
)

test.register_coroutine_test(
  "Motor direction closing with window_shade_level_cmd",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    local attr_report_data = {
          { PRIVATE_ATTRIBUTE_ID, data_types.Uint8.ID, 2 }-- device sends 2 for closing
    }
    test.socket.zigbee:__queue_receive({
          mock_device.id,
          zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })

    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        { capability = "windowShadeLevel", component = "main", command = "setShadeLevel", args = { 85 } }
      }
    )
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        WindowCovering.server.commands.GoToLiftPercentage(mock_device, 85)
      }
    )

    test.socket.zigbee:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercentage:build_test_attr_report(mock_device, 85)
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShade.windowShade.closing())
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(85))
    )
  end
)

test.register_coroutine_test(
  "Motor direction closing with window_shade_preset_cmd",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    local attr_report_data = {
          { PRIVATE_ATTRIBUTE_ID, data_types.Uint8.ID, 2 }-- device sends 2 for closing
    }
    test.socket.zigbee:__queue_receive({
          mock_device.id,
          zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })

    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {capability = "windowShadePreset", component = "main", command = "presetPosition", args = {}},
      }
    )
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        WindowCovering.server.commands.GoToLiftPercentage(mock_device, 50)
      }
    )

    test.socket.zigbee:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercentage:build_test_attr_report(mock_device, 50)
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShade.windowShade.closing())
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(50))
    )
  end
)

test.register_coroutine_test(
    "Power Source test cases",
    function()
        test.socket.zigbee:__set_channel_ordering("relaxed")

        test.socket.zigbee:__queue_receive({ mock_device.id,
        Basic.attributes.PowerSource:build_test_attr_report(mock_device, 3)})
        test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.powerSource.powerSource.battery()))
        test.wait_for_events()

        test.socket.zigbee:__queue_receive({ mock_device.id,
        Basic.attributes.PowerSource:build_test_attr_report(mock_device, 4)})
        test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.powerSource.powerSource.dc()))
        test.wait_for_events()

        test.socket.zigbee:__queue_receive({ mock_device.id,
        Basic.attributes.PowerSource:build_test_attr_report(mock_device, 0)})
        test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.powerSource.powerSource.unknown()))
        test.wait_for_events()
    end
)

test.run_registered_tests()