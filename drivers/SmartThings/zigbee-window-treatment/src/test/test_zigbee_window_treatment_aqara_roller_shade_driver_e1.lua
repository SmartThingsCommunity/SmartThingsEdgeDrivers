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
local SinglePrecisionFloat = require "st.zigbee.data_types".SinglePrecisionFloat
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local cluster_base = require "st.zigbee.cluster_base"
local clusters = require "st.zigbee.zcl.clusters"
local data_types = require "st.zigbee.data_types"
local t_utils = require "integration_test.utils"
local capabilities = require "st.capabilities"
local test = require "integration_test"

-- local write_attribute = require "st.zigbee.zcl.global_commands.write_attribute"
-- local zcl_messages = require "st.zigbee.zcl"
-- local messages = require "st.zigbee.messages"
-- local zb_const = require "st.zigbee.constants"
-- local FrameCtrl = require "st.zigbee.zcl.frame_ctrl"

local initializedStateWithGuide = capabilities["stse.initializedStateWithGuide"]
local chargingStatus = capabilities["stse.chargingStatus"]
local shadeRotateState = capabilities["stse.shadeRotateState"]
local shadeRotateStateId = "stse.shadeRotateState"
test.add_package_capability("initializedStateWithGuide.yaml")
test.add_package_capability("shadeRotateState.yaml")
test.add_package_capability("chargingStatus.yaml")

local AnalogOutput = clusters.AnalogOutput
local Groups = clusters.Groups

local SHADE_LEVEL = "shadeLevel"

local PRIVATE_CLUSTER_ID = 0xFCC0
local PRIVATE_ATTRIBUTE_ID = 0x0009
local MULTISTATE_CLUSTER_ID = 0x0013
local MULTISTATE_ATTRIBUTE_ID = 0x0055
local MFG_CODE = 0x115F
local PRIVATE_HEART_BATTERY_ENERGY_ID = 0x00F7
local PRIVATE_CURTAIN_POLARITY_ATTRIBUTE_ID = 0x0400
local PRIVATE_CURTAIN_RANGE_FLAG_ATTRIBUTE_ID = 0x0402
local PRIVATE_SET_CURTAIN_SPEED_ATTRIBUTE_ID = 0x0408
local PRIVATE_STATE_OF_CHARGE_ATTRIBUTE_ID = 0x0409

local mock_device = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("window-treatment-aqara-roller-shade-rotate-e1.yml"),
    fingerprinted_endpoint_id = 0x01,
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "LUMI",
        model = "lumi.curtain.acn002",
        server_clusters = {  PRIVATE_CLUSTER_ID, 0x000D, 0x0013 }
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

-- local function custom_write_attribute(device, cluster, attribute, data_type, value, mfg_code)
--     local data = data_types.validate_or_build_type(value, data_type)
--     local message = cluster_base.write_attribute(device, data_types.ClusterId(cluster), attribute, data)
--     if mfg_code ~= nil then
--       message.body.zcl_header.frame_ctrl:set_mfg_specific()
--       message.body.zcl_header.mfg_code = data_types.validate_or_build_type(mfg_code, data_types.Uint16, "mfg_code")
--     else
--       message.body.zcl_header.frame_ctrl = FrameCtrl(0x10)
--     end
--     return message
-- end

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
      mock_device:generate_test_message("main", shadeRotateState.rotateState.idle())
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.battery.battery(100))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", chargingStatus.chargingStatus.notCharging())
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("ReverseLiftingDirection", capabilities.switch.switch.off())
    )
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, PRIVATE_ATTRIBUTE_ID, MFG_CODE
        ,
        data_types.Uint8,
        1) })
  end
)

test.register_coroutine_test(
  "Handle doConfigure lifecycle",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      Groups.server.commands.RemoveAllGroups(mock_device)
    })
    test.socket.zigbee:__expect_send({
        mock_device.id,
        zigbee_test_utils.build_attribute_read(mock_device, PRIVATE_CLUSTER_ID, { PRIVATE_CURTAIN_POLARITY_ATTRIBUTE_ID }, MFG_CODE)
      })
    test.socket.zigbee:__expect_send({
        mock_device.id,
        zigbee_test_utils.build_attribute_read(mock_device, PRIVATE_CLUSTER_ID, { PRIVATE_CURTAIN_RANGE_FLAG_ATTRIBUTE_ID }, MFG_CODE)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      AnalogOutput.attributes.PresentValue:read(mock_device)
    })
    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)

test.register_coroutine_test(
  "Window shade state closed",
  function()
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.zigbee:__queue_receive(
      {
        mock_device.id,
        AnalogOutput.attributes.PresentValue:build_test_attr_report(mock_device, SinglePrecisionFloat(0, -127, 0))
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(0))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShade.windowShade.closed())
    )
  end
)

test.register_coroutine_test(
  "Window shade state open",
  function()
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.zigbee:__queue_receive(
      {
        mock_device.id,
        AnalogOutput.attributes.PresentValue:build_test_attr_report(mock_device, SinglePrecisionFloat(0, 6, 0.5625))
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(100))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShade.windowShade.open())
    )
  end
)

test.register_coroutine_test(
  "Window shade state partially open",
  function()
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.zigbee:__queue_receive(
      {
        mock_device.id,
        AnalogOutput.attributes.PresentValue:build_test_attr_report(mock_device, SinglePrecisionFloat(0, 5, 0.5625))
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(50))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShade.windowShade.partially_open())
    )
  end
)

test.register_coroutine_test(
  "chargingStatus report should be handled",
  function()
    local attr_report_data = {
      { PRIVATE_STATE_OF_CHARGE_ATTRIBUTE_ID, data_types.Uint8.ID, 0x01 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      chargingStatus.chargingStatus.charging()))
  end
)

test.register_coroutine_test(
  "Shade state report should be handled",
  function()
    local attr_report_data = {
      { MULTISTATE_ATTRIBUTE_ID, data_types.Uint16.ID, 0x0001 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, MULTISTATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShade.windowShade.opening())
    )
  end
)

test.register_coroutine_test(
  "curtain polarity report should be handled",
  function()
    local attr_report_data = {
      { PRIVATE_CURTAIN_POLARITY_ATTRIBUTE_ID, data_types.Boolean.ID, true }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("ReverseLiftingDirection", capabilities.switch.switch.on())
    )
  end
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
  "curtain charging status report should be handled",
  function()
    local attr_report_data = {
      { PRIVATE_STATE_OF_CHARGE_ATTRIBUTE_ID, data_types.Uint8.ID, 0x01 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", chargingStatus.chargingStatus.charging())
    )
  end
)

test.register_coroutine_test(
  "Battery voltage report should be handled",
  function()
    local attr_report_data = {
      { PRIVATE_HEART_BATTERY_ENERGY_ID, data_types.CharString.ID,
       "\x03\x28\x1B\x05\x21\x02\x00\x09\x21\x00\x01\x0A\x21\x00\x00\x0B\x20\x00\x0C\x20\x01\x0D\x23\x1A\x0F\x00\x00\x11\x23\x01\x00\x00\x00\x64\x20\x2E\x65\x20\x5C" }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.battery.battery(92))
    )
  end
)

test.register_coroutine_test(
  "Window shade open cmd handler",
  function()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        { capability = "windowShade", component = "main", command = "open", args = {} }
      }
    )
    -- test.socket.zigbee:__expect_send({
    --   mock_device.id,
    --   custom_write_attribute(mock_device , AnalogOutput.ID, AnalogOutput.attributes.PresentValue.ID, data_types.SinglePrecisionFloat,
    --    SinglePrecisionFloat(0, 6, 0.5625), nil)
    -- })
  end
)

test.register_coroutine_test(
  "Window shade close cmd handler",
  function()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        { capability = "windowShade", component = "main", command = "close", args = {} }
      }
    )
    -- test.socket.zigbee:__expect_send({
    --   mock_device.id,
    --   custom_write_attribute(mock_device , AnalogOutput.ID, AnalogOutput.attributes.PresentValue.ID, data_types.SinglePrecisionFloat,
    --    SinglePrecisionFloat(0, -127, 0), nil)
    -- })
  end
)

test.register_coroutine_test(
  "Window shade pause cmd handler(partially open)",
  function()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        { capability = "windowShade", component = "main", command = "pause", args = {} }
      }
    )
    -- test.socket.zigbee:__expect_send({
    --   mock_device.id,
    --   custom_write_attribute(mock_device , MULTISTATE_CLUSTER_ID, MULTISTATE_ATTRIBUTE_ID, data_types.Uint16, 0x0002, nil)
    -- })
  end
)

test.register_coroutine_test(
  "Rotate up cmd handler",
  function()
    mock_device:set_field(SHADE_LEVEL, 0)
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        { capability = shadeRotateStateId, component = "main", command = "setRotateState", args = { state = "rotateUp" } }
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", shadeRotateState.rotateState.idle({state_change = true}))
    )
  end
)

test.register_coroutine_test(
  "Rotate down cmd handler",
  function()
    mock_device:set_field(SHADE_LEVEL, 0)
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        { capability = shadeRotateStateId, component = "main", command = "setRotateState",
          args = { state = "rotateDown" } }
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", shadeRotateState.rotateState.idle({state_change = true}))
    )
  end
)

test.register_coroutine_test(
  "Capability on command should be handled : device reverse lifting direction",
  function()
    test.socket.capability:__queue_receive({ mock_device.id,
      { capability = "switch", component = "ReverseLiftingDirection", command = "on", args = {} } })
    -- test.socket.zigbee:__expect_send({ mock_device.id,
    --   cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID,
    --     PRIVATE_CURTAIN_POLARITY_ATTRIBUTE_ID, MFG_CODE, data_types.Boolean, true) })
  end
)

test.register_coroutine_test(
  "Handle adjustOperatingSpeed in infochanged",
  function()
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({
      preferences = { ["stse.adjustOperatingSpeed"] = "1" }
    }))
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, PRIVATE_SET_CURTAIN_SPEED_ATTRIBUTE_ID,
        MFG_CODE, data_types.Uint8, 0x01) })
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
      zigbee_test_utils.build_attribute_read(mock_device, PRIVATE_CLUSTER_ID, { PRIVATE_CURTAIN_POLARITY_ATTRIBUTE_ID }, MFG_CODE)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_attribute_read(mock_device, PRIVATE_CLUSTER_ID, { PRIVATE_CURTAIN_RANGE_FLAG_ATTRIBUTE_ID }, MFG_CODE)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      AnalogOutput.attributes.PresentValue:read(mock_device)
    })
  end
)

test.run_registered_tests()
