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
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local cluster_base = require "st.zigbee.cluster_base"
local clusters = require "st.zigbee.zcl.clusters"
local data_types = require "st.zigbee.data_types"
local t_utils = require "integration_test.utils"
local capabilities = require "st.capabilities"
local test = require "integration_test"
local FrameCtrl = require "st.zigbee.zcl.frame_ctrl"

local initializedStateWithGuide = capabilities["stse.initializedStateWithGuide"]
local chargingState = capabilities["stse.chargingState"]
local hookLockState = capabilities["stse.hookLockState"]
local hookLockStateId = "stse.hookLockState"
test.add_package_capability("initializedStateWithGuide.yaml")
test.add_package_capability("hookLockState.yaml")
test.add_package_capability("chargingState.yaml")

local Groups = clusters.Groups
local Basic = clusters.Basic
local WindowCovering = clusters.WindowCovering
local PowerConfiguration = clusters.PowerConfiguration
local PRIVATE_CURTAIN_MANUAL_ATTRIBUTE_ID = 0x0401
local PRIVATE_CURTAIN_RANGE_FLAG_ATTRIBUTE_ID = 0x0402
local PRIVATE_CURTAIN_STATUS_ATTRIBUTE_ID = 0x0421
local PRIVATE_CURTAIN_LOCKING_SETTING_ATTRIBUTE_ID = 0x0427
local PRIVATE_CURTAIN_LOCKING_STATUS_ATTRIBUTE_ID = 0x0428
local PRIVATE_CLUSTER_ID = 0xFCC0
local MFG_CODE = 0x115F


local mock_device = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("window-treatment-aqara-curtain-driver-e1.yml"),
    fingerprinted_endpoint_id = 0x01,
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "LUMI",
        model = "lumi.curtain.agl001",
        server_clusters = {  PRIVATE_CLUSTER_ID, Groups.ID, Basic.ID, PowerConfiguration.ID, WindowCovering.ID }
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

local function custom_write_attribute(device, cluster, attribute, data_type, value, mfg_code)
    local data = data_types.validate_or_build_type(value, data_type)
    local message = cluster_base.write_attribute(device, data_types.ClusterId(cluster), attribute, data)
    if mfg_code ~= nil then
      message.body.zcl_header.frame_ctrl:set_mfg_specific()
      message.body.zcl_header.mfg_code = data_types.validate_or_build_type(mfg_code, data_types.Uint16, "mfg_code")
    else
      message.body.zcl_header.frame_ctrl = FrameCtrl(0x10)
    end
    return message
end

test.register_coroutine_test(
  "Handle added lifecycle",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.windowShade.supportedWindowShadeCommands({ "open", "close", "pause" }, {visibility = {displayed = false}}))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(0))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShade.windowShade.closed())
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", initializedStateWithGuide.initializedStateWithGuide.notInitialized())
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", hookLockState.hookLockState.unlocked())
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", chargingState.chargingState.stopped())
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.battery.battery(100))
    )
  end
)

test.register_coroutine_test(
  "Handle doConfigure lifecycle",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
    test.socket.zigbee:__expect_send({
        mock_device.id,
        zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, PowerConfiguration.ID)
    })
    test.socket.zigbee:__expect_send({
        mock_device.id,
        PowerConfiguration.attributes.BatteryPercentageRemaining:configure_reporting(mock_device, 30, 3600, 1)
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
        Groups.server.commands.RemoveAllGroups(mock_device)
    })
    test.socket.zigbee:__expect_send({
        mock_device.id,
        zigbee_test_utils.build_attribute_read(mock_device, PRIVATE_CLUSTER_ID, { PRIVATE_CURTAIN_RANGE_FLAG_ATTRIBUTE_ID }, MFG_CODE)
    })
    test.socket.zigbee:__expect_send({
        mock_device.id,
        zigbee_test_utils.build_attribute_read(mock_device, PRIVATE_CLUSTER_ID, { PRIVATE_CURTAIN_LOCKING_STATUS_ATTRIBUTE_ID }, MFG_CODE)
    })
    test.socket.zigbee:__expect_send({
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercentage:read(mock_device)
    })
    test.socket.zigbee:__expect_send({
        mock_device.id,
        PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device)
    })
    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)

test.register_coroutine_test(
  "Handle reverseCurtainDirection in infochanged",
  function()
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({
      preferences = { ["stse.reverseCurtainDirection"] = true }
    }))
    test.socket.zigbee:__expect_send({
      mock_device.id,
      custom_write_attribute(mock_device , WindowCovering.ID, WindowCovering.attributes.Mode.ID,
      data_types.Bitmap8, 0x01, nil)
    })
  end
)

test.register_coroutine_test(
  "Handle softTouch in infochanged",
  function()
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({
      preferences = { ["stse.softTouch"] = true }
    }))
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID,
      PRIVATE_CURTAIN_MANUAL_ATTRIBUTE_ID, MFG_CODE, data_types.Boolean, false) })
  end
)


test.register_coroutine_test(
  "Window shade open cmd handler (initialized)",
  function()
    local attr_report_data = {
      { PRIVATE_CURTAIN_RANGE_FLAG_ATTRIBUTE_ID, data_types.Boolean.ID, true }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", initializedStateWithGuide.initializedStateWithGuide.initialized())
    )
    test.wait_for_events()
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
  end
)

test.register_coroutine_test(
  "Window shade close cmd handler (notInitialized)",
  function()
    local attr_report_data = {
      { PRIVATE_CURTAIN_RANGE_FLAG_ATTRIBUTE_ID, data_types.Boolean.ID, false }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", initializedStateWithGuide.initializedStateWithGuide.notInitialized())
    )
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        { capability = "windowShade", component = "main", command = "close", args = {} }
      }
    )
    -- test.socket.zigbee:__expect_send({
    --     mock_device.id,
    --     WindowCovering.server.commands.DownOrClose(mock_device)
    -- })
  end
)

test.register_coroutine_test(
  "Window shade pause cmd handler(partially open)(initialized)",
  function()
    local attr_report_data = {
      { PRIVATE_CURTAIN_RANGE_FLAG_ATTRIBUTE_ID, data_types.Boolean.ID, true }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", initializedStateWithGuide.initializedStateWithGuide.initialized())
    )
    test.wait_for_events()
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
  "hook LocK Lock cmd handler",
  function()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        { capability = hookLockStateId, component = "main", command = "hookLock", args = {} }
      }
    )
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID,
      PRIVATE_CURTAIN_LOCKING_SETTING_ATTRIBUTE_ID, MFG_CODE, data_types.Uint8, 0x01) })
  end
)

test.register_coroutine_test(
  "hook LocK Unlock cmd handler",
  function()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        { capability = hookLockStateId, component = "main", command = "hookUnlock", args = {} }
      }
    )
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID,
      PRIVATE_CURTAIN_LOCKING_SETTING_ATTRIBUTE_ID, MFG_CODE, data_types.Uint8, 0x00) })
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
        zigbee_test_utils.build_attribute_read(mock_device, PRIVATE_CLUSTER_ID, { PRIVATE_CURTAIN_RANGE_FLAG_ATTRIBUTE_ID }, MFG_CODE)
    })
    test.socket.zigbee:__expect_send({
        mock_device.id,
        zigbee_test_utils.build_attribute_read(mock_device, PRIVATE_CLUSTER_ID, { PRIVATE_CURTAIN_LOCKING_STATUS_ATTRIBUTE_ID }, MFG_CODE)
    })
    test.socket.zigbee:__expect_send({
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercentage:read(mock_device)
    })
    test.socket.zigbee:__expect_send({
        mock_device.id,
        PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device)
    })
  end
)


test.register_coroutine_test(
  "curtain charging state report should be handled",
  function()
    local attr_report_data = {
      { Basic.attributes.PowerSource.ID, data_types.Enum8.ID, 4 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, Basic.ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", chargingState.chargingState.charging())
    )
  end
)


test.register_message_test(
  "Battery percentage report should be handled",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, PowerConfiguration.attributes.BatteryPercentageRemaining:build_test_attr_report(mock_device, 200) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.battery.battery(100))
    }
  }
)

test.register_coroutine_test(
  "curtain range flag report should be handled",
  function()
    local attr_report_data = {
      { PRIVATE_CURTAIN_RANGE_FLAG_ATTRIBUTE_ID, data_types.Boolean.ID, true }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", initializedStateWithGuide.initializedStateWithGuide.initialized())
    )
  end
)

test.register_coroutine_test(
  "Shade state report should be handled",
  function()
    local attr_report_data = {
      { PRIVATE_CURTAIN_STATUS_ATTRIBUTE_ID, data_types.Uint8.ID, 0x01 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShade.windowShade.opening())
    )
  end
)

test.register_coroutine_test(
  "hook lock state report should be handled",
  function()
    local attr_report_data = {
      { PRIVATE_CURTAIN_LOCKING_STATUS_ATTRIBUTE_ID, data_types.Uint8.ID, 0x02 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", hookLockState.hookLockState.locking())
    )
  end
)

test.run_registered_tests()
