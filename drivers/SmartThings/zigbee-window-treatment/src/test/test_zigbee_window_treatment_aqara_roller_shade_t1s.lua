-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

-- Test for Aqara Roller Shade Controller T1S (lumi.curtain.vagl02)
-- The T1S reports its position through AnalogOutput.PresentValue (0 = closed, 100 = open),
-- its motion state through the MultistateOutput cluster and its travel-point initialization
-- state through a manufacturer specific attribute of the Aqara private cluster.

local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local SinglePrecisionFloat = require "st.zigbee.data_types".SinglePrecisionFloat
local FrameCtrl = require "st.zigbee.zcl.frame_ctrl"
local t_utils = require "integration_test.utils"
local test = require "integration_test"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"

local initializedStateWithGuide = capabilities["stse.initializedStateWithGuide"]
local shadeRotateState = capabilities["stse.shadeRotateState"]
local shadeRotateStateId = "stse.shadeRotateState"
test.add_package_capability("initializedStateWithGuide.yaml")
test.add_package_capability("shadeRotateState.yaml")

local Basic = clusters.Basic
local WindowCovering = clusters.WindowCovering
local AnalogOutput = clusters.AnalogOutput
local Groups = clusters.Groups

local PRIVATE_CLUSTER_ID = 0xFCC0
local PRIVATE_ATTRIBUTE_ID = 0x0009
local MFG_CODE = 0x115F
local INIT_STATE_ATTRIBUTE_ID = 0x0407
local DIRECTION_ATTRIBUTE_ID = 0x0400

local INIT_STATE_INITIALIZED = 0x02
local INIT_STATE_NOT_INITIALIZED = 0x00

local MULTISTATE_CLUSTER_ID = 0x0013
local MULTISTATE_ATTRIBUTE_ID = 0x0055
local ROTATE_UP_VALUE = 0x0006
local ROTATE_DOWN_VALUE = 0x0005
local SHADE_STATE_CLOSE = 0
local SHADE_STATE_OPEN = 1
local SHADE_STATE_STOP = 2
local SHADE_STATE_BLOCKED = 4

local mock_device = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("window-treatment-aqara-roller-shade-rotate.yml"),
    fingerprinted_endpoint_id = 0x01,
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "LUMI",
        model = "lumi.curtain.vagl02",
        server_clusters = { Basic.ID, AnalogOutput.ID, MULTISTATE_CLUSTER_ID, WindowCovering.ID, PRIVATE_CLUSTER_ID }
      }
    }
  }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device)
end

test.set_test_init_function(test_init)

-- Helpers -------------------------------------------------------------------

local function build_init_state_report(value)
  return zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID,
    { { INIT_STATE_ATTRIBUTE_ID, data_types.Uint8.ID, value } }, MFG_CODE)
end

local function build_shade_state_report(value)
  return zigbee_test_utils.build_attribute_report(mock_device, MULTISTATE_CLUSTER_ID,
    { { MULTISTATE_ATTRIBUTE_ID, data_types.Uint16.ID, value } })
end

local function build_rotate_write(value)
  local message = cluster_base.write_manufacturer_specific_attribute(mock_device, MULTISTATE_CLUSTER_ID,
    MULTISTATE_ATTRIBUTE_ID, MFG_CODE, data_types.Uint16, value)
  message.body.zcl_header.frame_ctrl = FrameCtrl(0x10)
  return message
end

-- Mark the device as initialized (travel points set) so that control commands are accepted
local function set_initialized()
  test.socket.zigbee:__queue_receive({ mock_device.id, build_init_state_report(INIT_STATE_INITIALIZED) })
  test.socket.capability:__expect_send(mock_device:generate_test_message("main",
    initializedStateWithGuide.initializedStateWithGuide.initialized()))
  test.wait_for_events()
end

-- Mark the device as not initialized so that control commands are rejected
local function set_not_initialized()
  test.socket.zigbee:__queue_receive({ mock_device.id, build_init_state_report(INIT_STATE_NOT_INITIALIZED) })
  test.socket.capability:__expect_send(mock_device:generate_test_message("main",
    initializedStateWithGuide.initializedStateWithGuide.notInitialized()))
  test.wait_for_events()
end

-- Lifecycle -----------------------------------------------------------------

test.register_coroutine_test(
  "Handle added lifecycle",
  function()
    -- The initial window shade events should be sent during the first time onboarding of the device
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.windowShade.supportedWindowShadeCommands({ "open", "close", "pause" }, { visibility = { displayed = false } }))
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
      mock_device:generate_test_message("main", shadeRotateState.rotateState.idle({ visibility = { displayed = false } }))
    )
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, PRIVATE_ATTRIBUTE_ID, MFG_CODE,
        data_types.Uint8, 1) })

    -- After a driver switch-over the added lifecycle is re-triggered. The stateful events
    -- (shadeLevel, windowShade, initializedStateWithGuide) must not be re-emitted so that the
    -- previously known state is preserved.
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.windowShade.supportedWindowShadeCommands({ "open", "close", "pause" }, { visibility = { displayed = false } }))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", shadeRotateState.rotateState.idle({ visibility = { displayed = false } }))
    )
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, PRIVATE_ATTRIBUTE_ID, MFG_CODE,
        data_types.Uint8, 1) })
  end,
  {
    min_api_version = 14
  }
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
      Groups.server.commands.RemoveAllGroups(mock_device)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      AnalogOutput.attributes.PresentValue:read(mock_device)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_attribute_read(mock_device, PRIVATE_CLUSTER_ID, { INIT_STATE_ATTRIBUTE_ID }, MFG_CODE)
    })
    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end,
  {
    min_api_version = 14
  }
)

-- Initialization state --------------------------------------------------------

test.register_coroutine_test(
  "Init state report 0x02 should be handled as initialized",
  function()
    test.socket.zigbee:__queue_receive({ mock_device.id, build_init_state_report(INIT_STATE_INITIALIZED) })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      initializedStateWithGuide.initializedStateWithGuide.initialized()))
  end,
  {
    min_api_version = 14
  }
)

test.register_coroutine_test(
  "Init state report other than 0x02 should be handled as notInitialized",
  function()
    test.socket.zigbee:__queue_receive({ mock_device.id, build_init_state_report(INIT_STATE_NOT_INITIALIZED) })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      initializedStateWithGuide.initializedStateWithGuide.notInitialized()))
    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, build_init_state_report(0x01) })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      initializedStateWithGuide.initializedStateWithGuide.notInitialized()))
  end,
  {
    min_api_version = 14
  }
)

-- Shade level (AnalogOutput.PresentValue) -------------------------------------

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
  end,
  {
    min_api_version = 14
  }
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
  end,
  {
    min_api_version = 14
  }
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
  end,
  {
    min_api_version = 14
  }
)

test.register_coroutine_test(
  "Window shade level above 100 should be clamped to 100",
  function()
    test.socket.capability:__set_channel_ordering("relaxed")
    -- 120 = 1.875 * 2^6
    test.socket.zigbee:__queue_receive(
      {
        mock_device.id,
        AnalogOutput.attributes.PresentValue:build_test_attr_report(mock_device, SinglePrecisionFloat(0, 6, 0.875))
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(100))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShade.windowShade.open())
    )
  end,
  {
    min_api_version = 14
  }
)

-- Shade motion state (MultistateOutput.PresentValue) --------------------------

test.register_coroutine_test(
  "Shade state report open should emit opening",
  function()
    test.socket.zigbee:__queue_receive({ mock_device.id, build_shade_state_report(SHADE_STATE_OPEN) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShade.windowShade.opening())
    )
  end,
  {
    min_api_version = 14
  }
)

test.register_coroutine_test(
  "Shade state report close should emit closing",
  function()
    test.socket.zigbee:__queue_receive({ mock_device.id, build_shade_state_report(SHADE_STATE_CLOSE) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShade.windowShade.closing())
    )
  end,
  {
    min_api_version = 14
  }
)

test.register_coroutine_test(
  "Shade state report stop should read the shade position",
  function()
    test.socket.zigbee:__queue_receive({ mock_device.id, build_shade_state_report(SHADE_STATE_STOP) })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      AnalogOutput.attributes.PresentValue:read(mock_device)
    })
  end,
  {
    min_api_version = 14
  }
)

test.register_coroutine_test(
  "Shade state report blocked should read the shade position",
  function()
    test.socket.zigbee:__queue_receive({ mock_device.id, build_shade_state_report(SHADE_STATE_BLOCKED) })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      AnalogOutput.attributes.PresentValue:read(mock_device)
    })
  end,
  {
    min_api_version = 14
  }
)

-- Window shade commands ---------------------------------------------------------

test.register_coroutine_test(
  "Window shade open cmd handler",
  function()
    set_initialized()
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
  end,
  {
    min_api_version = 14
  }
)

test.register_coroutine_test(
  "Window shade close cmd handler",
  function()
    set_initialized()
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
  end,
  {
    min_api_version = 14
  }
)

test.register_coroutine_test(
  "Window shade pause cmd handler",
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
  end,
  {
    min_api_version = 14
  }
)

test.register_coroutine_test(
  "Window shade setShadeLevel cmd handler",
  function()
    set_initialized()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        { capability = "windowShadeLevel", component = "main", command = "setShadeLevel", args = { 30 } }
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(30))
    )
    test.socket.zigbee:__expect_send({
      mock_device.id,
      WindowCovering.server.commands.GoToLiftPercentage(mock_device, 30)
    })
  end,
  {
    min_api_version = 14
  }
)

test.register_coroutine_test(
  "Window shade commands should be allowed before the init state has been reported",
  function()
    -- A device that has not answered the travel point read must remain controllable
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
  end,
  {
    min_api_version = 14
  }
)

test.register_coroutine_test(
  "Window shade commands should be ignored when the device is not initialized",
  function()
    set_not_initialized()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        { capability = "windowShade", component = "main", command = "open", args = {} }
      }
    )
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        { capability = "windowShade", component = "main", command = "close", args = {} }
      }
    )
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        { capability = "windowShadeLevel", component = "main", command = "setShadeLevel", args = { 30 } }
      }
    )
    -- No zigbee message and no shadeLevel event is expected
  end,
  {
    min_api_version = 14
  }
)

-- Stateless step ---------------------------------------------------------------

test.register_coroutine_test(
  "statelessWindowShadeLevelStep should step from the current shade level",
  function()
    set_initialized()
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
    test.wait_for_events()

    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        { capability = "statelessWindowShadeLevelStep", component = "main", command = "stepShadeLevel", args = { 10 } }
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(60))
    )
    test.socket.zigbee:__expect_send({
      mock_device.id,
      WindowCovering.server.commands.GoToLiftPercentage(mock_device, 60)
    })
  end,
  {
    min_api_version = 17
  }
)

-- Rotate ------------------------------------------------------------------------

test.register_coroutine_test(
  "Rotate up cmd handler",
  function()
    set_initialized()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        { capability = shadeRotateStateId, component = "main", command = "setRotateState", args = { "rotateUp" } }
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        shadeRotateState.rotateState.idle({ state_change = true, visibility = { displayed = false } }))
    )
    test.socket.zigbee:__expect_send({ mock_device.id, build_rotate_write(ROTATE_UP_VALUE) })
  end,
  {
    min_api_version = 14
  }
)

test.register_coroutine_test(
  "Rotate down cmd handler",
  function()
    set_initialized()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        { capability = shadeRotateStateId, component = "main", command = "setRotateState", args = { "rotateDown" } }
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        shadeRotateState.rotateState.idle({ state_change = true, visibility = { displayed = false } }))
    )
    test.socket.zigbee:__expect_send({ mock_device.id, build_rotate_write(ROTATE_DOWN_VALUE) })
  end,
  {
    min_api_version = 14
  }
)

test.register_coroutine_test(
  "Rotate cmd should only reset the UI when the device is not initialized",
  function()
    set_not_initialized()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        { capability = shadeRotateStateId, component = "main", command = "setRotateState", args = { "rotateUp" } }
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        shadeRotateState.rotateState.idle({ state_change = true, visibility = { displayed = false } }))
    )
    -- No zigbee message is expected
  end,
  {
    min_api_version = 14
  }
)

-- Preferences --------------------------------------------------------------------

test.register_coroutine_test(
  "Handle reverseRollerShadeDir true in infoChanged",
  function()
    local updates = { preferences = {} }
    updates.preferences["stse.reverseRollerShadeDir"] = true
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed(updates))
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, DIRECTION_ATTRIBUTE_ID,
          MFG_CODE, data_types.Boolean, true)
      }
    )
  end,
  {
    min_api_version = 14
  }
)

test.register_coroutine_test(
  "Handle reverseRollerShadeDir false in infoChanged",
  function()
    local updates = { preferences = {} }
    updates.preferences["stse.reverseRollerShadeDir"] = false
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed(updates))
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, DIRECTION_ATTRIBUTE_ID,
          MFG_CODE, data_types.Boolean, false)
      }
    )
  end,
  {
    min_api_version = 14
  }
)

-- Refresh ---------------------------------------------------------------------------

test.register_coroutine_test(
  "Refresh necessary attributes",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "refresh", component = "main", command = "refresh", args = {} }
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      AnalogOutput.attributes.PresentValue:read(mock_device)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_attribute_read(mock_device, PRIVATE_CLUSTER_ID, { INIT_STATE_ATTRIBUTE_ID }, MFG_CODE)
    })
  end,
  {
    min_api_version = 14
  }
)

test.run_registered_tests()
