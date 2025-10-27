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
local SinglePrecisionFloat = require "st.zigbee.data_types".SinglePrecisionFloat
local t_utils = require "integration_test.utils"
local test = require "integration_test"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local FrameCtrl = require "st.zigbee.zcl.frame_ctrl"

local initializedStateWithGuide = capabilities["stse.initializedStateWithGuide"]
local shadeRotateState = capabilities["stse.shadeRotateState"]
local shadeRotateStateId = "stse.shadeRotateState"
test.add_package_capability("initializedStateWithGuide.yaml")
test.add_package_capability("shadeRotateState.yaml")

local Basic = clusters.Basic
local WindowCovering = clusters.WindowCovering
local AnalogOutput = clusters.AnalogOutput
local Groups = clusters.Groups

local SHADE_LEVEL = "shadeLevel"

local PRIVATE_CLUSTER_ID = 0xFCC0
local PRIVATE_ATTRIBUTE_ID = 0x0009
local MFG_CODE = 0x115F
local PREF_ATTRIBUTE_ID = 0x0401
local SHADE_STATE_ATTRIBUTE_ID = 0x0404

local PREF_REVERSE_OFF = "\x00\x02\x00\x00\x00\x00\x00"
local PREF_REVERSE_ON = "\x00\x02\x00\x01\x00\x00\x00"

local MULTISTATE_CLUSTER_ID = 0x0013
local MULTISTATE_ATTRIBUTE_ID = 0x0055
local ROTATE_UP_VALUE = 0x0004
local ROTATE_DOWN_VALUE = 0x0005

local mock_device = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("window-treatment-aqara-roller-shade-rotate.yml"),
    fingerprinted_endpoint_id = 0x01,
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "LUMI",
        model = "lumi.curtain.aq2",
        server_clusters = { Basic.ID, 0x000D, 0x0013, 0x0102 }
      }
    }
  }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device)end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Handle added lifecycle",
  function()
    -- The initial window shade event should be send during the device's first time onboarding
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
      mock_device:generate_test_message("main", shadeRotateState.rotateState.idle({visibility = { displayed = false }}))
    )

    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, PRIVATE_ATTRIBUTE_ID, MFG_CODE
        ,
        data_types.Uint8,
        1) })
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, Basic.ID, PREF_ATTRIBUTE_ID, MFG_CODE,
        data_types.CharString,
        PREF_REVERSE_OFF) })
    -- Avoid sending the initial window shade event after driver switch-over, as the switch-over event itself re-triggers the added lifecycle.
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.windowShade.supportedWindowShadeCommands({ "open", "close", "pause" }, {visibility = {displayed = false}}))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", initializedStateWithGuide.initializedStateWithGuide.notInitialized())
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", shadeRotateState.rotateState.idle({visibility = { displayed = false }}))
    )

    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, PRIVATE_ATTRIBUTE_ID, MFG_CODE
        ,
        data_types.Uint8,
        1) })
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, Basic.ID, PREF_ATTRIBUTE_ID, MFG_CODE,
        data_types.CharString,
        PREF_REVERSE_OFF) })
  end
)

test.register_coroutine_test(
  "Handle doConfigure lifecycle",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
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
      Basic.attributes.ApplicationVersion:read(mock_device)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      Groups.server.commands.RemoveAllGroups(mock_device)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      AnalogOutput.attributes.PresentValue:read(mock_device)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_attribute_read(mock_device, Basic.ID, { PREF_ATTRIBUTE_ID }, MFG_CODE)
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
  "Window shade open cmd handler",
  function()
    local attr_report_data = {
      { PREF_ATTRIBUTE_ID, data_types.CharString.ID, "\x00\x00\x01\x00\x00\x00\x00" }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, Basic.ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      initializedStateWithGuide.initializedStateWithGuide.initialized()))
    test.wait_for_events()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        { capability = "windowShade", component = "main", command = "open", args = {} }
      }
    )
    test.socket.zigbee:__expect_send({
      mock_device.id,
      WindowCovering.server.commands.GoToLiftPercentage(mock_device, 100)
    })
  end
)

test.register_coroutine_test(
  "Window shade close cmd handler",
  function()
    local attr_report_data = {
      { PREF_ATTRIBUTE_ID, data_types.CharString.ID, "\x00\x00\x01\x00\x00\x00\x00" }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, Basic.ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      initializedStateWithGuide.initializedStateWithGuide.initialized()))
    test.wait_for_events()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        { capability = "windowShade", component = "main", command = "close", args = {} }
      }
    )
    test.socket.zigbee:__expect_send({
      mock_device.id,
      WindowCovering.server.commands.GoToLiftPercentage(mock_device, 0)
    })
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
    test.socket.zigbee:__expect_send({
      mock_device.id,
      WindowCovering.server.commands.Stop(mock_device)
    })
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
      mock_device:generate_test_message("main", shadeRotateState.rotateState.idle({state_change = true, visibility = { displayed = false }}))
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
      mock_device:generate_test_message("main", shadeRotateState.rotateState.idle({state_change = true, visibility = { displayed = false }}))
    )
  end
)

test.register_coroutine_test(
  "Handle reverseRollerShadeDir in infochanged",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.environment_update:__queue_receive({ "zigbee",
      { hub_zigbee_id = base64.encode(zigbee_test_utils.mock_hub_eui) } })

    local updates = {
      preferences = {
      }
    }
    updates.preferences["stse.reverseRollerShadeDir"] = true
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed(updates))
    test.mock_time.advance_time(1)

    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        cluster_base.write_manufacturer_specific_attribute(mock_device, Basic.ID, PREF_ATTRIBUTE_ID, MFG_CODE,
          data_types.CharString, PREF_REVERSE_ON)
      }
    )
    local attr_report_data = {
      { PREF_ATTRIBUTE_ID, data_types.CharString.ID, "\x00\x00\x01\x00\x00\x00\x00" }
    }

    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, Basic.ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      initializedStateWithGuide.initializedStateWithGuide.initialized()))
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
      zigbee_test_utils.build_attribute_read(mock_device, Basic.ID, { PREF_ATTRIBUTE_ID }, MFG_CODE)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      AnalogOutput.attributes.PresentValue:read(mock_device)
    })
  end
)

test.register_coroutine_test(
  "SetShadeLevel command handler",
  function()
    local attr_report_data = {
      { PREF_ATTRIBUTE_ID, data_types.CharString.ID, "\x00\x00\x01\x00\x00\x00\x00" }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, Basic.ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      initializedStateWithGuide.initializedStateWithGuide.initialized()))
    test.wait_for_events()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        { capability = "windowShadeLevel", component = "main", command = "setShadeLevel", args = { 50 }}
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(50))
    )
    test.socket.zigbee:__expect_send({
      mock_device.id,
      WindowCovering.server.commands.GoToLiftPercentage(mock_device, 50)
    })
  end
)


test.register_coroutine_test(
  "PREF_ATTRIBUTE_ID attribute handler - notInitialized",
  function()
    local attr_report_data = {
      { PREF_ATTRIBUTE_ID, data_types.CharString.ID, "\x00\x00\x00\x00\x00\x00\x00" }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, Basic.ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      initializedStateWithGuide.initializedStateWithGuide.notInitialized()))
  end
)

test.register_coroutine_test(
  "SHADE_STATE_ATTRIBUTE_ID attribute handler",
  function()
    local attr_report_data = {
      { SHADE_STATE_ATTRIBUTE_ID, data_types.Uint8.ID, 0 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, Basic.ID, attr_report_data, MFG_CODE)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      AnalogOutput.attributes.PresentValue:read(mock_device)
    })
  end
)

test.register_coroutine_test(
  "Handle sensitivity adjustment capability",
  function()
    local attr_report_data = {
      { PREF_ATTRIBUTE_ID, data_types.CharString.ID, "\x00\x00\x01\x00\x00\x00\x00" }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, Basic.ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      initializedStateWithGuide.initializedStateWithGuide.initialized()))
    test.wait_for_events()

    test.socket.capability:__queue_receive({ mock_device.id,
    { capability = "stse.shadeRotateState", component = "main", command = "setRotateState", args = {"rotateUp"} }})
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      shadeRotateState.rotateState.idle({state_change = true, visibility = { displayed = false }}) ))

      local message = cluster_base.write_manufacturer_specific_attribute(mock_device, MULTISTATE_CLUSTER_ID,
        MULTISTATE_ATTRIBUTE_ID, MFG_CODE, data_types.Uint16, ROTATE_UP_VALUE)
      message.body.zcl_header.frame_ctrl = FrameCtrl(0x10)

    test.socket.zigbee:__expect_send({ mock_device.id, message })

    test.socket.capability:__queue_receive({ mock_device.id,
    { capability = "stse.shadeRotateState", component = "main", command = "setRotateState", args = {"rotateDown"} }})
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      shadeRotateState.rotateState.idle({state_change = true, visibility = { displayed = false }}) ))

      local message = cluster_base.write_manufacturer_specific_attribute(mock_device, MULTISTATE_CLUSTER_ID,
        MULTISTATE_ATTRIBUTE_ID, MFG_CODE, data_types.Uint16, ROTATE_DOWN_VALUE)
      message.body.zcl_header.frame_ctrl = FrameCtrl(0x10)

    test.socket.zigbee:__expect_send({ mock_device.id, message })
  end
)


test.run_registered_tests()
