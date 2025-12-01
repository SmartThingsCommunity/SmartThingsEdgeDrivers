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
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local t_utils = require "integration_test.utils"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local custom_capabilities = require "shus-mattress/custom_capabilities"

local shus_mattress_profile_def = t_utils.get_profile_definition("shus-smart-mattress.yml")
test.add_package_capability("aiMode.yaml")
test.add_package_capability("autoInflation.yaml")
test.add_package_capability("leftControl.yaml")
test.add_package_capability("rightControl.yaml")
test.add_package_capability("strongExpMode.yaml")
test.add_package_capability("yoga.yaml")
test.add_package_capability("mattressHardness.yaml")

local PRIVATE_CLUSTER_ID = 0xFCC2
local MFG_CODE = 0x1235

local mock_device = test.mock_device.build_test_zigbee_device(
{
  label = "Shus Smart Mattress",
  profile = shus_mattress_profile_def,
  zigbee_endpoints = {
    [1] = {
      id = 1,
      manufacturer = "SHUS",
      model = "SX-1",
      server_clusters = { 0x0000,PRIVATE_CLUSTER_ID }
    }
  }
})

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device)
  zigbee_test_utils.init_noop_health_check_timer()
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "lifecycle - added test",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      custom_capabilities.yoga.supportedYogaState({"stop", "left", "right"}, { visibility = { displayed = false }}) ))
    local read_0x0006_messge = cluster_base.read_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, 0x0006, MFG_CODE)
    local read_0x0007_messge = cluster_base.read_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, 0x0007, MFG_CODE)
    local read_0x0009_messge = cluster_base.read_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, 0x0009, MFG_CODE)
    local read_0x000a_messge = cluster_base.read_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, 0x000a, MFG_CODE)
    local read_0x0000_messge = cluster_base.read_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, 0x0000, MFG_CODE)
    local read_0x0001_messge = cluster_base.read_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, 0x0001, MFG_CODE)
    local read_0x0002_messge = cluster_base.read_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, 0x0002, MFG_CODE)
    local read_0x0003_messge = cluster_base.read_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, 0x0003, MFG_CODE)
    local read_0x0004_messge = cluster_base.read_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, 0x0004, MFG_CODE)
    local read_0x0005_messge = cluster_base.read_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, 0x0005, MFG_CODE)
    local read_0x0008_messge = cluster_base.read_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, 0x0008, MFG_CODE)
    local read_0x000C_messge = cluster_base.read_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, 0x000C, MFG_CODE)
    local read_0x000D_messge = cluster_base.read_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, 0x000D, MFG_CODE)
    local read_0x000E_messge = cluster_base.read_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, 0x000E, MFG_CODE)
    local read_0x000F_messge = cluster_base.read_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, 0x000F, MFG_CODE)
    local read_0x0010_messge = cluster_base.read_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, 0x0010, MFG_CODE)
    local read_0x0011_messge = cluster_base.read_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, 0x0011, MFG_CODE)
    test.socket.zigbee:__expect_send({mock_device.id, read_0x0006_messge})
    test.socket.zigbee:__expect_send({mock_device.id, read_0x0007_messge})
    test.socket.zigbee:__expect_send({mock_device.id, read_0x0009_messge})
    test.socket.zigbee:__expect_send({mock_device.id, read_0x000a_messge})
    test.socket.zigbee:__expect_send({mock_device.id, read_0x0000_messge})
    test.socket.zigbee:__expect_send({mock_device.id, read_0x0001_messge})
    test.socket.zigbee:__expect_send({mock_device.id, read_0x0002_messge})
    test.socket.zigbee:__expect_send({mock_device.id, read_0x0003_messge})
    test.socket.zigbee:__expect_send({mock_device.id, read_0x0004_messge})
    test.socket.zigbee:__expect_send({mock_device.id, read_0x0005_messge})
    test.socket.zigbee:__expect_send({mock_device.id, read_0x0008_messge})
    test.socket.zigbee:__expect_send({mock_device.id, read_0x000C_messge})
    test.socket.zigbee:__expect_send({mock_device.id, read_0x000D_messge})
    test.socket.zigbee:__expect_send({mock_device.id, read_0x000E_messge})
    test.socket.zigbee:__expect_send({mock_device.id, read_0x000F_messge})
    test.socket.zigbee:__expect_send({mock_device.id, read_0x0010_messge})
    test.socket.zigbee:__expect_send({mock_device.id, read_0x0011_messge})
  end
)

test.register_coroutine_test(
  "capability - refresh",
  function()
    test.socket.capability:__queue_receive({ mock_device.id,
      { capability = "refresh", component = "main", command = "refresh", args = {} } })
    local read_0x0006_messge = cluster_base.read_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, 0x0006, MFG_CODE)
    local read_0x0007_messge = cluster_base.read_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, 0x0007, MFG_CODE)
    local read_0x0009_messge = cluster_base.read_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, 0x0009, MFG_CODE)
    local read_0x000a_messge = cluster_base.read_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, 0x000a, MFG_CODE)
    local read_0x0000_messge = cluster_base.read_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, 0x0000, MFG_CODE)
    local read_0x0001_messge = cluster_base.read_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, 0x0001, MFG_CODE)
    local read_0x0002_messge = cluster_base.read_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, 0x0002, MFG_CODE)
    local read_0x0003_messge = cluster_base.read_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, 0x0003, MFG_CODE)
    local read_0x0004_messge = cluster_base.read_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, 0x0004, MFG_CODE)
    local read_0x0005_messge = cluster_base.read_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, 0x0005, MFG_CODE)
    local read_0x0008_messge = cluster_base.read_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, 0x0008, MFG_CODE)
    local read_0x000C_messge = cluster_base.read_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, 0x000C, MFG_CODE)
    local read_0x000D_messge = cluster_base.read_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, 0x000D, MFG_CODE)
    local read_0x000E_messge = cluster_base.read_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, 0x000E, MFG_CODE)
    local read_0x000F_messge = cluster_base.read_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, 0x000F, MFG_CODE)
    local read_0x0010_messge = cluster_base.read_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, 0x0010, MFG_CODE)
    local read_0x0011_messge = cluster_base.read_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, 0x0011, MFG_CODE)
    test.socket.zigbee:__expect_send({mock_device.id, read_0x0006_messge})
    test.socket.zigbee:__expect_send({mock_device.id, read_0x0007_messge})
    test.socket.zigbee:__expect_send({mock_device.id, read_0x0009_messge})
    test.socket.zigbee:__expect_send({mock_device.id, read_0x000a_messge})
    test.socket.zigbee:__expect_send({mock_device.id, read_0x0000_messge})
    test.socket.zigbee:__expect_send({mock_device.id, read_0x0001_messge})
    test.socket.zigbee:__expect_send({mock_device.id, read_0x0002_messge})
    test.socket.zigbee:__expect_send({mock_device.id, read_0x0003_messge})
    test.socket.zigbee:__expect_send({mock_device.id, read_0x0004_messge})
    test.socket.zigbee:__expect_send({mock_device.id, read_0x0005_messge})
    test.socket.zigbee:__expect_send({mock_device.id, read_0x0008_messge})
    test.socket.zigbee:__expect_send({mock_device.id, read_0x000C_messge})
    test.socket.zigbee:__expect_send({mock_device.id, read_0x000D_messge})
    test.socket.zigbee:__expect_send({mock_device.id, read_0x000E_messge})
    test.socket.zigbee:__expect_send({mock_device.id, read_0x000F_messge})
    test.socket.zigbee:__expect_send({mock_device.id, read_0x0010_messge})
    test.socket.zigbee:__expect_send({mock_device.id, read_0x0011_messge})
  end
)

test.register_coroutine_test(
  "Device reported leftback 0 and driver emit custom_capabilities.left_control.leftback.idle({ visibility = { displayed = false }})",
  function()
    local attr_report_data = {
      { 0x0000, data_types.Uint8.ID, 0 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      custom_capabilities.left_control.leftback.idle({ visibility = { displayed = false }})))
  end
)

test.register_coroutine_test(
  "Device reported leftback 1 and driver emit custom_capabilities.left_control.leftback.idle({ visibility = { displayed = false }})",
  function()
    local attr_report_data = {
      { 0x0000, data_types.Uint8.ID, 1 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      custom_capabilities.left_control.leftback.idle({ visibility = { displayed = false }})))
  end
)

test.register_coroutine_test(
  "Device reported leftwaist 0 and driver emit custom_capabilities.left_control.leftwaist.idle({ visibility = { displayed = false }})",
  function()
    local attr_report_data = {
      { 0x0001, data_types.Uint8.ID, 0 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      custom_capabilities.left_control.leftwaist.idle({ visibility = { displayed = false }})))
  end
)

test.register_coroutine_test(
  "Device reported leftwaist 1 and driver emit custom_capabilities.left_control.leftwaist.idle({ visibility = { displayed = false }})",
  function()
    local attr_report_data = {
      { 0x0001, data_types.Uint8.ID, 1 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      custom_capabilities.left_control.leftwaist.idle({ visibility = { displayed = false }})))
  end
)

test.register_coroutine_test(
  "Device reported lefthip 0 and driver emit custom_capabilities.left_control.lefthip.idle({ visibility = { displayed = false }})",
  function()
    local attr_report_data = {
      { 0x0002, data_types.Uint8.ID, 0 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      custom_capabilities.left_control.lefthip.idle({ visibility = { displayed = false }})))
  end
)

test.register_coroutine_test(
  "Device reported lefthip 1 and driver emit custom_capabilities.left_control.lefthip.idle({ visibility = { displayed = false }})",
  function()
    local attr_report_data = {
      { 0x0002, data_types.Uint8.ID, 1 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      custom_capabilities.left_control.lefthip.idle({ visibility = { displayed = false }})))
  end
)

test.register_coroutine_test(
  "Device reported rightback 0 and driver emit custom_capabilities.right_control.rightback.idle({ visibility = { displayed = false }})",
  function()
    local attr_report_data = {
      { 0x0003, data_types.Uint8.ID, 0 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      custom_capabilities.right_control.rightback.idle({ visibility = { displayed = false }})))
  end
)

test.register_coroutine_test(
  "Device reported rightback 1 and driver emit custom_capabilities.right_control.rightback.idle({ visibility = { displayed = false }})",
  function()
    local attr_report_data = {
      { 0x0003, data_types.Uint8.ID, 1 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      custom_capabilities.right_control.rightback.idle({ visibility = { displayed = false }})))
  end
)

test.register_coroutine_test(
  "Device reported rightwaist 0 and driver emit custom_capabilities.right_control.rightwaist.idle({ visibility = { displayed = false }})",
  function()
    local attr_report_data = {
      { 0x0004, data_types.Uint8.ID, 0 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      custom_capabilities.right_control.rightwaist.idle({ visibility = { displayed = false }})))
  end
)

test.register_coroutine_test(
  "Device reported rightwaist 1 and driver emit custom_capabilities.right_control.rightwaist.idle({ visibility = { displayed = false }})",
  function()
    local attr_report_data = {
      { 0x0004, data_types.Uint8.ID, 1 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      custom_capabilities.right_control.rightwaist.idle({ visibility = { displayed = false }})))
  end
)

test.register_coroutine_test(
  "Device reported righthip 0 and driver emit custom_capabilities.right_control.righthip.idle({ visibility = { displayed = false }})",
  function()
    local attr_report_data = {
      { 0x0005, data_types.Uint8.ID, 0 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      custom_capabilities.right_control.righthip.idle({ visibility = { displayed = false }})))
  end
)

test.register_coroutine_test(
  "Device reported righthip 1 and driver emit custom_capabilities.right_control.righthip.idle({ visibility = { displayed = false }})",
  function()
    local attr_report_data = {
      { 0x0005, data_types.Uint8.ID, 1 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      custom_capabilities.right_control.righthip.idle({ visibility = { displayed = false }})))
  end
)

test.register_coroutine_test(
  "Device reported leftBackHardness 1 and driver emit custom_capabilities.mattressHardness.leftBackHardness(1)",
  function()
    local attr_report_data = {
      { 0x000C, data_types.Uint8.ID, 1 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      custom_capabilities.mattressHardness.leftBackHardness(1)))
  end
)

test.register_coroutine_test(
  "Device reported leftWaistHardness 1 and driver emit custom_capabilities.mattressHardness.leftWaistHardness(1)",
  function()
    local attr_report_data = {
      { 0x000D, data_types.Uint8.ID, 1 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      custom_capabilities.mattressHardness.leftWaistHardness(1)))
  end
)

test.register_coroutine_test(
  "Device reported leftHipHardness 1 and driver emit custom_capabilities.mattressHardness.leftHipHardness(1)",
  function()
    local attr_report_data = {
      { 0x000E, data_types.Uint8.ID, 1 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      custom_capabilities.mattressHardness.leftHipHardness(1)))
  end
)

test.register_coroutine_test(
  "Device reported rightBackHardness 1 and driver emit custom_capabilities.mattressHardness.rightBackHardness(1)",
  function()
    local attr_report_data = {
      { 0x000F, data_types.Uint8.ID, 1 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      custom_capabilities.mattressHardness.rightBackHardness(1)))
  end
)

test.register_coroutine_test(
  "Device reported rightWaistHardness 1 and driver emit custom_capabilities.mattressHardness.rightWaistHardness(1)",
  function()
    local attr_report_data = {
      { 0x0010, data_types.Uint8.ID, 1 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      custom_capabilities.mattressHardness.rightWaistHardness(1)))
  end
)

test.register_coroutine_test(
  "Device reported rightHipHardness 1 and driver emit custom_capabilities.mattressHardness.rightHipHardness(1)",
  function()
    local attr_report_data = {
      { 0x0011, data_types.Uint8.ID, 1 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      custom_capabilities.mattressHardness.rightHipHardness(1)))
  end
)

test.register_coroutine_test(
  "Device reported yoga 2 and driver emit custom_capabilities.yoga.state.right()",
  function()
    local attr_report_data = {
      { 0x0008, data_types.Uint8.ID, 2 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      custom_capabilities.yoga.state.right()))
  end
)

test.register_coroutine_test(
  "Device reported yoga 1 and driver emit custom_capabilities.yoga.state.left()",
  function()
    local attr_report_data = {
      { 0x0008, data_types.Uint8.ID, 1 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      custom_capabilities.yoga.state.left()))
  end
)

test.register_coroutine_test(
  "Device reported yoga 0 and driver emit custom_capabilities.yoga.state.stop()",
  function()
    local attr_report_data = {
      { 0x0008, data_types.Uint8.ID, 0 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      custom_capabilities.yoga.state.stop()))
  end
)

test.register_coroutine_test(
  "Device reported ai_mode left false and driver emit custom_capabilities.ai_mode.left.off()",
  function()
    local attr_report_data = {
      { 0x0006, data_types.Boolean.ID, false }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      custom_capabilities.ai_mode.left.off()))
  end
)

test.register_coroutine_test(
  "Device reported ai_mode left true and driver emit custom_capabilities.ai_mode.left.on()",
  function()
    local attr_report_data = {
      { 0x0006, data_types.Boolean.ID, true }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      custom_capabilities.ai_mode.left.on()))
  end
)

test.register_coroutine_test(
  "Device reported ai_mode right true and driver emit custom_capabilities.ai_mode.right.on()",
  function()
    local attr_report_data = {
      { 0x0007, data_types.Boolean.ID, true }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      custom_capabilities.ai_mode.right.on()))
  end
)

test.register_coroutine_test(
  "Device reported ai_mode right false and driver emit custom_capabilities.ai_mode.right.off()",
  function()
    local attr_report_data = {
      { 0x0007, data_types.Boolean.ID, false }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      custom_capabilities.ai_mode.right.off()))
  end
)

test.register_coroutine_test(
  "Device reported inflationState false and driver emit custom_capabilities.auto_inflation.inflationState.off()",
  function()
    local attr_report_data = {
      { 0x0009, data_types.Boolean.ID, false }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      custom_capabilities.auto_inflation.inflationState.off()))
  end
)

test.register_coroutine_test(
  "Device reported inflationState true and driver emit custom_capabilities.auto_inflation.inflationState.on()",
  function()
    local attr_report_data = {
      { 0x0009, data_types.Boolean.ID, true }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      custom_capabilities.auto_inflation.inflationState.on()))
  end
)

test.register_coroutine_test(
  "Device reported strong_exp_mode false and driver emit custom_capabilities.strong_exp_mode.expState.off()",
  function()
    local attr_report_data = {
      { 0x000a, data_types.Boolean.ID, false }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      custom_capabilities.strong_exp_mode.expState.off()))
  end
)

test.register_coroutine_test(
  "Device reported strong_exp_mode true and driver emit custom_capabilities.strong_exp_mode.expState.on()",
  function()
    local attr_report_data = {
      { 0x000a, data_types.Boolean.ID, true }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      custom_capabilities.strong_exp_mode.expState.on()))
  end
)


test.register_coroutine_test(
  "capability leftControl on and driver send on ",
  function()
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = custom_capabilities.ai_mode.ID, component = "main", command ="leftControl" , args = {"on"}}
    })
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID,
      0x0006, MFG_CODE, data_types.Boolean, true)
    })
  end
)

test.register_coroutine_test(
  "capability leftControl off and driver send off ",
  function()
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = custom_capabilities.ai_mode.ID, component = "main", command ="leftControl" , args = {"off"}}
    })
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID,
        0x0006, MFG_CODE, data_types.Boolean, false)
    })
  end
)

test.register_coroutine_test(
  "capability rightControl on and driver send on ",
  function()
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = custom_capabilities.ai_mode.ID, component = "main", command ="rightControl" , args = {"on"}}
    })
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID,
        0x0007, MFG_CODE, data_types.Boolean, true)
    })
  end
)

test.register_coroutine_test(
  "capability rightControl off and driver send off ",
  function()
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = custom_capabilities.ai_mode.ID, component = "main", command ="rightControl" , args = {"off"}}
    })
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID,
        0x0007, MFG_CODE, data_types.Boolean, false)
    })
  end
)

test.register_coroutine_test(
  "capability auto_inflation stateControl on and driver send on ",
  function()
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = custom_capabilities.auto_inflation.ID, component = "main", command ="stateControl" , args = {"on"}}
    })
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID,
        0x0009, MFG_CODE, data_types.Boolean, true)
    })
  end
)

test.register_coroutine_test(
  "capability auto_inflation stateControl off and driver send off ",
  function()
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = custom_capabilities.auto_inflation.ID, component = "main", command ="stateControl" , args = {"off"}}
    })
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID,
        0x0009, MFG_CODE, data_types.Boolean, false)
    })
  end
)

test.register_coroutine_test(
  "capability strong_exp_mode stateControl on and driver send on ",
  function()
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = custom_capabilities.strong_exp_mode.ID, component = "main", command ="stateControl" , args = {"on"}}
    })
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID,
        0x000a, MFG_CODE, data_types.Boolean, true)
    })
  end
)

test.register_coroutine_test(
  "capability strong_exp_mode stateControl off and driver send off ",
  function()
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = custom_capabilities.strong_exp_mode.ID, component = "main", command ="stateControl" , args = {"off"}}
    })
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID,
        0x000a, MFG_CODE, data_types.Boolean, false)
    })
  end
)

test.register_coroutine_test(
  "capability left_control backControl soft and driver send soft ",
  function()
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = custom_capabilities.left_control.ID, component = "main", command ="backControl" , args = {"soft"}}
    })
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID,
        0x0000, MFG_CODE, data_types.Uint8, 0)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      custom_capabilities.left_control.leftback.soft()))
  end
)

test.register_coroutine_test(
  "capability waistControl backControl soft and driver send soft ",
  function()
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = custom_capabilities.left_control.ID, component = "main", command ="waistControl" , args = {"soft"}}
    })
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID,
        0x0001, MFG_CODE, data_types.Uint8, 0)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      custom_capabilities.left_control.leftwaist.soft()))
  end
)

test.register_coroutine_test(
  "capability left_control hipControl soft and driver send soft ",
  function()
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = custom_capabilities.left_control.ID, component = "main", command ="hipControl" , args = {"soft"}}
    })
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID,
        0x0002, MFG_CODE, data_types.Uint8, 0)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      custom_capabilities.left_control.lefthip.soft()))
  end
)

test.register_coroutine_test(
  "capability left_control backControl hard and driver send hard ",
  function()
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = custom_capabilities.left_control.ID, component = "main", command ="backControl" , args = {"hard"}}
    })
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID,
        0x0000, MFG_CODE, data_types.Uint8, 1)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      custom_capabilities.left_control.leftback.hard()))
  end
)

test.register_coroutine_test(
  "capability waistControl backControl hard and driver send hard ",
  function()
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = custom_capabilities.left_control.ID, component = "main", command ="waistControl" , args = {"hard"}}
    })
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID,
        0x0001, MFG_CODE, data_types.Uint8, 1)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      custom_capabilities.left_control.leftwaist.hard()))
  end
)

test.register_coroutine_test(
  "capability left_control hipControl hard and driver send hard ",
  function()
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = custom_capabilities.left_control.ID, component = "main", command ="hipControl" , args = {"hard"}}
    })
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID,
        0x0002, MFG_CODE, data_types.Uint8, 1)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      custom_capabilities.left_control.lefthip.hard()))
  end
)

test.register_coroutine_test(
  "capability right_control backControl soft and driver send soft ",
  function()
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = custom_capabilities.right_control.ID, component = "main", command ="backControl" , args = {"soft"}}
    })
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID,
        0x0003, MFG_CODE, data_types.Uint8, 0)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      custom_capabilities.right_control.rightback.soft()))
  end
)

test.register_coroutine_test(
  "capability right_control waistControl soft and driver send soft ",
  function()
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = custom_capabilities.right_control.ID, component = "main", command ="waistControl" , args = {"soft"}}
    })
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID,
        0x0004, MFG_CODE, data_types.Uint8, 0)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      custom_capabilities.right_control.rightwaist.soft()))
  end
)

test.register_coroutine_test(
  "capability right_control hipControl soft and driver send soft ",
  function()
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = custom_capabilities.right_control.ID, component = "main", command ="hipControl" , args = {"soft"}}
    })
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID,
        0x0005, MFG_CODE, data_types.Uint8, 0)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      custom_capabilities.right_control.righthip.soft()))
  end
)

test.register_coroutine_test(
  "capability right_control backControl hard and driver send hard ",
  function()
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = custom_capabilities.right_control.ID, component = "main", command ="backControl" , args = {"hard"}}
    })
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID,
        0x0003, MFG_CODE, data_types.Uint8, 1)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      custom_capabilities.right_control.rightback.hard()))
  end
)

test.register_coroutine_test(
  "capability right_control waistControl hard and driver send hard ",
  function()
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = custom_capabilities.right_control.ID, component = "main", command ="waistControl" , args = {"hard"}}
    })
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID,
        0x0004, MFG_CODE, data_types.Uint8, 1)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      custom_capabilities.right_control.rightwaist.hard()))
  end
)

test.register_coroutine_test(
  "capability right_control hipControl hard and driver send hard ",
  function()
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = custom_capabilities.right_control.ID, component = "main", command ="hipControl" , args = {"hard"}}
    })
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID,
        0x0005, MFG_CODE, data_types.Uint8, 1)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      custom_capabilities.right_control.righthip.hard()))
  end
)

test.register_coroutine_test(
  "capability yoga stateControl left and driver send left ",
  function()
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = custom_capabilities.yoga.ID, component = "main", command ="stateControl" , args = {"left"}}
      })
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID,
        0x0008, MFG_CODE, data_types.Uint8, 1)
    })
  end
)

test.register_coroutine_test(
  "capability yoga stateControl right and driver send right ",
  function()
    test.socket.capability:__queue_receive({
    mock_device.id,
      { capability = custom_capabilities.yoga.ID, component = "main", command ="stateControl" , args = {"right"}}
      })
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID,
        0x0008, MFG_CODE, data_types.Uint8, 2)
      })
  end
)

test.register_coroutine_test(
  "capability yoga stateControl stop and driver send stop ",
  function()
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = custom_capabilities.yoga.ID, component = "main", command ="stateControl" , args = {"stop"}}
      })
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID,
        0x0008, MFG_CODE, data_types.Uint8, 0)
      })
  end
)

test.run_registered_tests()
