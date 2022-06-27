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

local base64 = require "st.base64"
local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local t_utils = require "integration_test.utils"
local test = require "integration_test"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"

local Basic = clusters.Basic
local WindowCovering = clusters.WindowCovering

local test = require "integration_test"
test.add_package_capability("initializedState.yaml")

local mock_device = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("window-aqara-curtain.yml"),
    fingerprinted_endpoint_id = 0x01,
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "LUMI",
        model = "lumi.curtain",
        server_clusters = {0x0000, 0x000D, 0x0013, 0x0102}
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
  "Handle Configure lifecycle",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added"})
    test.socket.capability:__expect_send({
      mock_device.id,
      {
        capability_id = "windowShade", component_id = "main",
        attribute_id = "supportedWindowShadeCommands", state = { value= { "open", "close", "pause" } }
      }
    })
        test.socket.capability:__expect_send({
      mock_device.id,
      {
        capability_id = "aqara.initializedstate", component_id = "main",
        attribute_id = "supportedInitializedState", state = { value= {"initialize"} }
      }
    })
    test.socket.zigbee:__expect_send({mock_device.id, cluster_base.write_manufacturer_specific_attribute(mock_device, Basic.ID, 0x0401, 0x115F, data_types.CharString, "\x00\x02\x00\x00\x00\x00\x00")})
    test.socket.zigbee:__expect_send({mock_device.id, cluster_base.write_manufacturer_specific_attribute(mock_device, Basic.ID, 0x0401, 0x115F, data_types.CharString, "\x00\x08\x00\x00\x00\x00\x00")})
    test.wait_for_events()

    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
    test.socket.zigbee:__set_channel_ordering("relaxed")
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
      WindowCovering.attributes.CurrentPositionLiftPercentage:read(mock_device)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_attribute_read(mock_device, 0x0000, {0x0401}, 0x115F)
    })
    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)

test.register_coroutine_test(
  "Window Shade state closed",
  function()
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.zigbee:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercentage:build_test_attr_report(mock_device, 0)
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShade.windowShade.closed())
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(0))
    )
  end
)

test.register_coroutine_test(
  "Window Shade state open",
  function()
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.zigbee:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercentage:build_test_attr_report(mock_device, 100)
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShade.windowShade.open())
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
  "WindowShade open cmd handler",
  function()
    test.socket.capability:__queue_receive(
        {
          mock_device.id,
          { capability = "windowShade", component = "main", command = "open", args = {} }
        }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShade.windowShade.closed())
    )
    test.socket.zigbee:__expect_send({
      mock_device.id,
      WindowCovering.server.commands.GoToLiftPercentage(mock_device, 100)
    })
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "WindowShade close cmd handler",
  function()
    test.socket.capability:__queue_receive(
        {
          mock_device.id,
          { capability = "windowShade", component = "main", command = "close", args = {} }
        }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShade.windowShade.closed())
    )
    test.socket.zigbee:__expect_send({
      mock_device.id,
      WindowCovering.server.commands.GoToLiftPercentage(mock_device, 0)
    })
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "WindowShade pause cmd handler",
  function()
    test.socket.capability:__queue_receive(
        {
          mock_device.id,
          { capability = "windowShade", component = "main", command = "pause", args = {} }
        }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShade.windowShade.closed())
    )
    test.socket.zigbee:__expect_send({
      mock_device.id,
      WindowCovering.server.commands.Stop(mock_device)
    })
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "Handle opencloseDirection in infochanged",
  function()
    test.socket.zigbee:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercentage:build_test_attr_report(mock_device, 100)
      }
    )
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShade.windowShade.open())
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(100))
    )
    test.wait_for_events()
    test.socket.environment_update:__queue_receive({ "zigbee", { hub_zigbee_id = base64.encode(zigbee_test_utils.mock_hub_eui) } })

    local updates = {
      preferences = {
      }
    }
    updates.preferences["aqara.opencloseDirection"] = true
    test.wait_for_events()
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed(updates))
    test.socket.zigbee:__expect_send({mock_device.id, cluster_base.write_manufacturer_specific_attribute(mock_device, Basic.ID, 0x0401, 0x115F, data_types.CharString, "\x00\x02\x00\x01\x00\x00\x00")})
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.windowShade.windowShade.closed()))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(0)))
    test.wait_for_events()
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed(updates))

    updates.preferences["aqara.opencloseDirection"] = false
    test.wait_for_events()
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed(updates))
    test.socket.zigbee:__expect_send({mock_device.id, cluster_base.write_manufacturer_specific_attribute(mock_device, Basic.ID, 0x0401, 0x115F, data_types.CharString, "\x00\x02\x00\x00\x00\x00\x00")})
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.windowShade.windowShade.open()))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(100)))
  end
)

test.register_coroutine_test(
  "Handle softTouch in infochanged",
  function()
    test.socket.environment_update:__queue_receive({ "zigbee", { hub_zigbee_id = base64.encode(zigbee_test_utils.mock_hub_eui) } })

    local updates = {
      preferences = {
      }
    }
    updates.preferences["aqara.softTouch"] = true
    test.wait_for_events()
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed(updates))
    test.socket.zigbee:__expect_send({mock_device.id, cluster_base.write_manufacturer_specific_attribute(mock_device, Basic.ID, 0x0401, 0x115F, data_types.CharString, "\x00\x08\x00\x00\x00\x00\x00")})
    test.wait_for_events()
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed(updates))

    updates.preferences["aqara.softTouch"] = false
    test.wait_for_events()
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed(updates))
    test.socket.zigbee:__expect_send({mock_device.id, cluster_base.write_manufacturer_specific_attribute(mock_device, Basic.ID, 0x0401, 0x115F, data_types.CharString, "\x00\x08\x00\x00\x00\x01\x00")})
  end
)

test.register_coroutine_test(
  "Refresh necessary attributes",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.capability:__queue_receive({
      mock_device.id,
      {
        capability = "refresh", component = "main", command = "refresh", args = {}
      }
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_attribute_read(mock_device, 0x0000, {0x0401}, 0x115F)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      WindowCovering.attributes.CurrentPositionLiftPercentage:read(mock_device)
    })
  end
)

test.run_registered_tests()
