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
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local t_utils = require "integration_test.utils"
local test = require "integration_test"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local WindowCovering = clusters.WindowCovering
local INVERT_CLUSTER = 0xFC00
local INVERT_CLUSTER_ATTRIBUTE = 0x0000
local MFG_CODE = 0x0000

local mock_device = test.mock_device.build_test_zigbee_device({
  profile = t_utils.get_profile_definition("window-treatment-micronic.yml"),
  fingerprinted_endpoint_id = 0x01,
  zigbee_endpoints = {
    [1] = {
      id = 1,
      manufacturer = "micronic-ko",
      model = "acm301",
      server_clusters = { 0x0000, 0x0003, 0xFC00, 0x0102 }
    }
  }
})

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device)
  zigbee_test_utils.init_noop_health_check_timer()
end

test.set_test_init_function(test_init)

test.register_coroutine_test("Window Shade state closed", function()
  test.socket.capability:__set_channel_ordering("relaxed")
  test.socket.zigbee:__queue_receive({ mock_device.id,
    WindowCovering.attributes.CurrentPositionLiftPercentage:build_test_attr_report(
      mock_device, 0) })
  test.socket.capability:__expect_send(mock_device:generate_test_message("main",
    capabilities.windowShade.windowShade.closed()))
end)

test.register_coroutine_test("Window Shade state open", function()
  test.socket.capability:__set_channel_ordering("relaxed")
  test.socket.zigbee:__queue_receive({ mock_device.id,
    WindowCovering.attributes.CurrentPositionLiftPercentage:build_test_attr_report(
      mock_device, 100) })
  test.socket.capability:__expect_send(mock_device:generate_test_message("main",
    capabilities.windowShade.windowShade.open()))
end)

test.register_coroutine_test("Handle reverse in infochanged", function()
  test.socket.zigbee:__queue_receive({ mock_device.id,
    WindowCovering.attributes.CurrentPositionLiftPercentage:build_test_attr_report(
      mock_device, 100) })
  test.socket.capability:__set_channel_ordering("relaxed")
  test.socket.capability:__expect_send(mock_device:generate_test_message("main",
    capabilities.windowShade.windowShade.open()))
  test.wait_for_events()
  test.socket.environment_update:__queue_receive({ "zigbee", {
    hub_zigbee_id = base64.encode(zigbee_test_utils.mock_hub_eui)
  } })

  local updates = {
    preferences = {
      reverse = true
    }
  }
  test.wait_for_events()
  test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed(updates))
  test.socket.zigbee:__expect_send({ mock_device.id,
    cluster_base.write_manufacturer_specific_attribute(mock_device, INVERT_CLUSTER,
      INVERT_CLUSTER_ATTRIBUTE, MFG_CODE, data_types.Boolean, updates.preferences.reverse) })
  test.socket.capability:__expect_send(mock_device:generate_test_message("main",
    capabilities.windowShade.windowShade.closed()))
  -- Emit same InfoChanged event again
  test.wait_for_events()
  test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed(updates))
  -- No events should be emitted
  updates.preferences.reverse = false
  test.wait_for_events()
  test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed(updates))
  test.socket.zigbee:__expect_send({ mock_device.id,
    cluster_base.write_manufacturer_specific_attribute(mock_device, INVERT_CLUSTER,
      INVERT_CLUSTER_ATTRIBUTE, MFG_CODE, data_types.Boolean, updates.preferences.reverse) })
  test.socket.capability:__expect_send(mock_device:generate_test_message("main",
    capabilities.windowShade.windowShade.open()))
end)

test.register_coroutine_test("Refresh necessary attributes", function()
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
  test.socket.capability:__expect_send(mock_device:generate_test_message("main",
    capabilities.windowShade.supportedWindowShadeCommands({ "open", "close", "pause" }, {
      visibility = {
        displayed = false
      }
    })))
  test.wait_for_events()

  test.socket.zigbee:__set_channel_ordering("relaxed")
  test.socket.capability:__queue_receive({ mock_device.id, {
    capability = "refresh",
    component = "main",
    command = "refresh",
    args = {}
  } })
  test.socket.zigbee:__expect_send({ mock_device.id,
    zigbee_test_utils.build_attribute_read(mock_device, INVERT_CLUSTER,
      { INVERT_CLUSTER_ATTRIBUTE }, 0x0000) })
end)

test.run_registered_tests()
