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

local test = require "integration_test"
local t_utils = require "integration_test.utils"
local clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local capabilities = require "st.capabilities"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"

local OnOff = clusters.OnOff

local PRIVATE_CLUSTER_ID = 0xFCC0
local MFG_CODE = 0x115F
local RESTORE_POWER_STATE_ATTRIBUTE_ID = 0x0201
local ELECTRIC_SWITCH_TYPE_ATTRIBUTE_ID = 0x000A


local PRIVATE_MODE = "PRIVATE_MODE"

local mock_device = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("aqara-switch-module-no-power.yml"),
    fingerprinted_endpoint_id = 0x01,
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "LUMI",
        model = "lumi.switch.l0agl1",
        server_clusters = { 0x0006 }
      }
    }
  }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device)
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Lifecycle - added test",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
  end
)

test.register_coroutine_test(
  "Refresh device",
  function()
    mock_device:set_field(PRIVATE_MODE, 1, { persist = true })
    test.socket.capability:__queue_receive({ mock_device.id,
      { capability = "refresh", component = "main", command = "refresh", args = {} } })
    test.socket.zigbee:__expect_send({ mock_device.id,
      OnOff.attributes.OnOff:read(mock_device) })
end
)

test.register_coroutine_test(
  "Reported on status should be handled",
  function()
    mock_device:set_field(PRIVATE_MODE, 1, { persist = true })
    test.socket.zigbee:__queue_receive({ mock_device.id,
      OnOff.attributes.OnOff:build_test_attr_report(mock_device, true):from_endpoint(0x01) })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.switch.switch.on()))
  end
)

test.register_coroutine_test(
  "Reported off status should be handled",
  function()
    mock_device:set_field(PRIVATE_MODE, 1, { persist = true })
    test.socket.zigbee:__queue_receive({ mock_device.id,
      OnOff.attributes.OnOff:build_test_attr_report(mock_device, false):from_endpoint(0x01) })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.switch.switch.off()))
  end
)

test.register_coroutine_test(
  "Capability on command should be handled",
  function()
    test.socket.capability:__queue_receive({ mock_device.id,
      { capability = "switch", component = "main", command = "on", args = {} } })
    mock_device:expect_native_cmd_handler_registration("switch", "on")
    test.socket.zigbee:__expect_send({ mock_device.id,
      OnOff.server.commands.On(mock_device) })
  end
)

test.register_coroutine_test(
  "Capability off command should be handled",
  function()
    test.socket.capability:__queue_receive({ mock_device.id,
      { capability = "switch", component = "main", command = "off", args = {} } })
    mock_device:expect_native_cmd_handler_registration("switch", "off")
    test.socket.zigbee:__expect_send({ mock_device.id,
      OnOff.server.commands.Off(mock_device) })
  end
)

test.register_coroutine_test(
  "Handle restorePowerState in infochanged",
  function()
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({
      preferences = { ["stse.restorePowerState"] = true }
    }))
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID,
        RESTORE_POWER_STATE_ATTRIBUTE_ID, MFG_CODE, data_types.Boolean, true) })
  end
)

test.register_coroutine_test(
  "Handle electricSwitchType in infochanged",
  function()
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({
      preferences = { ["stse.electricSwitchType"] = 'rocker' }
    }))
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID,
        ELECTRIC_SWITCH_TYPE_ATTRIBUTE_ID, MFG_CODE, data_types.Uint8, 1) })
  end
)

test.run_registered_tests()
