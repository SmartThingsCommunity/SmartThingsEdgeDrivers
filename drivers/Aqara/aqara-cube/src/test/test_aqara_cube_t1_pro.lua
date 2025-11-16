local test = require "integration_test"
local cluster_base = require "st.zigbee.cluster_base"
local t_utils = require "integration_test.utils"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local capabilities = require "st.capabilities"
local data_types = require "st.zigbee.data_types"
local clusters = require "st.zigbee.zcl.clusters"
local PowerConfiguration = clusters.PowerConfiguration

local PRI_CLU = 0xFCC0
local PRI_ATTR = 0x0009
local MFG_CODE = 0x115F

local ROTATE_CLU = 0x000C
local EVENT_CLU = 0x0012
local FACE_ATTR = 0x0149
local ACTION_ATTR = 0x0055
local CUBE_MODE = 0x0148

local cubeAction = capabilities["stse.cubeAction"]
local cubeFace = capabilities["stse.cubeFace"]
test.add_package_capability("cubeAction.yaml")
test.add_package_capability("cubeFace.yaml")

local CUBEACTION_TIME = 3


local mock_device = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("cube-t1-pro.yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "LUMI",
        model = "lumi.remote.cagl02",
        server_clusters = { PRI_CLU }
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
  "lifecycle - added test",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
    -- private protocol enable
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRI_CLU, PRI_ATTR, MFG_CODE,
        data_types.Uint8, 1) })
    -- init
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRI_CLU, CUBE_MODE, MFG_CODE,
        data_types.Uint8, 1) })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", cubeAction.cubeAction("noAction")))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", cubeFace.cubeFace("face1Up")))
    test.socket.zigbee:__expect_send({ mock_device.id, PowerConfiguration.attributes.BatteryVoltage:read(mock_device) })
  end
)

test.register_coroutine_test(
  "capability - refresh",
  function()
    test.socket.capability:__queue_receive({ mock_device.id,
      { capability = "refresh", component = "main", command = "refresh", args = {} } })
    test.socket.zigbee:__expect_send({ mock_device.id, PowerConfiguration.attributes.BatteryVoltage:read(mock_device) })
  end
)

test.register_coroutine_test(
  "data_handler test - shake",
  function()
    local attr_report_data = {
      { ACTION_ATTR, data_types.Uint16.ID, 0x0000 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, EVENT_CLU, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      cubeAction.cubeAction("shake")))
    test.timer.__create_and_queue_test_time_advance_timer(CUBEACTION_TIME, "oneshot")
    test.mock_time.advance_time(CUBEACTION_TIME)
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      cubeAction.cubeAction("noAction")))
  end
)

test.register_coroutine_test(
  "data_handler test - pick up and hold",
  function()
    local attr_report_data = {
      { ACTION_ATTR, data_types.Uint16.ID, 0x0004 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, EVENT_CLU, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      cubeAction.cubeAction("pickUpAndHold")))
    test.timer.__create_and_queue_test_time_advance_timer(CUBEACTION_TIME, "oneshot")
    test.mock_time.advance_time(CUBEACTION_TIME)
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      cubeAction.cubeAction("noAction")))
  end
)

test.register_coroutine_test(
  "data_handler test - flip to side 6",
  function()
    local attr_report_data = {
      { ACTION_ATTR, data_types.Uint16.ID, 0x0405 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, EVENT_CLU, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      cubeAction.cubeAction("flipToSide6")))
    test.timer.__create_and_queue_test_time_advance_timer(CUBEACTION_TIME, "oneshot")
    test.mock_time.advance_time(CUBEACTION_TIME)
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      cubeAction.cubeAction("noAction")))
  end
)

test.register_coroutine_test(
  "rotate_handler test - rotation",
  function()
    local attr_report_data = {
      { ACTION_ATTR, data_types.Uint16.ID, 0x0000 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, ROTATE_CLU, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      cubeAction.cubeAction("rotate")))
    test.timer.__create_and_queue_test_time_advance_timer(CUBEACTION_TIME, "oneshot")
    test.mock_time.advance_time(CUBEACTION_TIME)
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      cubeAction.cubeAction("noAction")))
  end
)

test.register_coroutine_test(
  "face_handler test - face up 1",
  function()
    local attr_report_data = {
      { FACE_ATTR, data_types.Uint8.ID, 0x00 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRI_CLU, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      cubeFace.cubeFace("face1Up")))
  end
)

test.run_registered_tests()
