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

local test = require "integration_test"
local t_utils = require "integration_test.utils"
local clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local capabilities = require "st.capabilities"
local SinglePrecisionFloat = require "st.zigbee.data_types".SinglePrecisionFloat
local zigbee_test_utils = require "integration_test.zigbee_test_utils"

local OnOff = clusters.OnOff
local AnalogInput = clusters.AnalogInput

local PRIVATE_CLUSTER_ID = 0xFCC0
local PRIVATE_ATTRIBUTE_ID = 0x0009
local MFG_CODE = 0x115F
local RESTORE_POWER_STATE_ATTRIBUTE_ID = 0x0201
local CHANGE_TO_WIRELESS_SWITCH_ATTRIBUTE_ID = 0x0200
local POWER_METER_ENDPOINT = 0x15
local ENERGY_METER_ENDPOINT = 0x1F
local WIRELESS_SWITCH_CLUSTER_ID = 0x0012
local WIRELESS_SWITCH_ATTRIBUTE_ID = 0x0055
local WIRELESS_SWITCH_PUSHED_VALUE = 1
local BUTTON_1_ENDPOINT = 0x29
local BUTTON_2_ENDPOINT = 0x2A

local LAST_REPORT_TIME = "LAST_REPORT_TIME"
local PRIVATE_MODE = "PRIVATE_MODE"

local mock_device = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("aqara-switch-power.yml"),
    fingerprinted_endpoint_id = 0x01,
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "LUMI",
        model = "lumi.switch.n3acn1",
        server_clusters = { 0x0006 }
      }
    }
  }
)

local mock_child = test.mock_device.build_test_child_device({
  profile = t_utils.get_profile_definition("aqara-switch-child.yml"),
  device_network_id = string.format("%04X:%02X", mock_device:get_short_address(), 2),
  parent_device_id = mock_device.id,
  parent_assigned_child_key = string.format("%02X", 2)
})

local mock_child2 = test.mock_device.build_test_child_device({
  profile = t_utils.get_profile_definition("aqara-switch-child.yml"),
  device_network_id = string.format("%04X:%02X", mock_device:get_short_address(), 3),
  parent_device_id = mock_device.id,
  parent_assigned_child_key = string.format("%02X", 3)
})

zigbee_test_utils.prepare_zigbee_env_info()

local function test_init()
  test.mock_device.add_test_device(mock_device)
  test.mock_device.add_test_device(mock_child)
  test.mock_device.add_test_device(mock_child2)
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Lifecycle - added test",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.button.numberOfButtons({ value = 3 },
    { visibility = { displayed = false } })))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.powerMeter.power({ value = 0.0, unit = "W" })))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.energyMeter.energy({ value = 0.0, unit = "Wh" })))
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, PRIVATE_ATTRIBUTE_ID, MFG_CODE,
        data_types.Uint8, 1) })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.button.supportedButtonValues({ "pushed" },
    { visibility = { displayed = false } })))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.button.button.pushed({ state_change = false })))

  end
)

test.register_coroutine_test(
  "Lifecycle - added test",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({ mock_child.id, "added" })
    test.socket.capability:__expect_send(mock_child:generate_test_message("main", capabilities.button.numberOfButtons({ value = 1 },
    { visibility = { displayed = false } })))
    test.socket.capability:__expect_send(mock_child:generate_test_message("main", capabilities.button.supportedButtonValues({ "pushed" },
    { visibility = { displayed = false } })))
    test.socket.capability:__expect_send(mock_child:generate_test_message("main", capabilities.button.button.pushed({ state_change = false })))
  end
)

test.register_coroutine_test(
  "Refresh device should read all necessary attributes",
  function()
    mock_device:set_field(PRIVATE_MODE, 1, { persist = true })

    test.socket.capability:__queue_receive({ mock_device.id,
      { capability = "refresh", component = "main", command = "refresh", args = {} } })
    test.socket.zigbee:__expect_send({ mock_device.id,
      OnOff.attributes.OnOff:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id,
      AnalogInput.attributes.PresentValue:read(mock_device):to_endpoint(POWER_METER_ENDPOINT) })
    test.socket.zigbee:__expect_send({ mock_device.id,
      AnalogInput.attributes.PresentValue:read(mock_device):to_endpoint(ENERGY_METER_ENDPOINT) })
  end
)

test.register_coroutine_test(
  "Reported on status should be handled : parent device",
  function()
    mock_device:set_field(PRIVATE_MODE, 1, { persist = true })
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.socket.zigbee:__queue_receive({ mock_device.id,
      OnOff.attributes.OnOff:build_test_attr_report(mock_device, true):from_endpoint(0x01) })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.switch.switch.on()))
    test.mock_time.advance_time(2)
    test.socket.zigbee:__expect_send({ mock_device.id,
      AnalogInput.attributes.PresentValue:read(mock_device):to_endpoint(POWER_METER_ENDPOINT) })
  end
)

test.register_coroutine_test(
  "Reported on status should be handled : child device",
  function()
    mock_device:set_field(PRIVATE_MODE, 1, { persist = true })
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.socket.zigbee:__queue_receive({ mock_device.id,
      OnOff.attributes.OnOff:build_test_attr_report(mock_device, true):from_endpoint(0x02) })
    test.socket.capability:__expect_send(mock_child:generate_test_message("main", capabilities.switch.switch.on()))
    test.mock_time.advance_time(2)
    test.socket.zigbee:__expect_send({ mock_device.id,
      AnalogInput.attributes.PresentValue:read(mock_device):to_endpoint(POWER_METER_ENDPOINT) })
  end
)

test.register_coroutine_test(
  "Reported off status should be handled by parent device",
  function()
    mock_device:set_field(PRIVATE_MODE, 1, { persist = true })
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.socket.zigbee:__queue_receive({ mock_device.id,
      OnOff.attributes.OnOff:build_test_attr_report(mock_device, false):from_endpoint(0x01) })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.switch.switch.off()))
    test.mock_time.advance_time(2)
    test.socket.zigbee:__expect_send({ mock_device.id,
      AnalogInput.attributes.PresentValue:read(mock_device):to_endpoint(POWER_METER_ENDPOINT) })
  end
)

test.register_coroutine_test(
  "Reported off status should be handled by child device",
  function()
    mock_device:set_field(PRIVATE_MODE, 1, { persist = true })
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.socket.zigbee:__queue_receive({ mock_device.id,
      OnOff.attributes.OnOff:build_test_attr_report(mock_device, false):from_endpoint(0x02) })
    test.socket.capability:__expect_send(mock_child:generate_test_message("main", capabilities.switch.switch.off()))
    test.mock_time.advance_time(2)
    test.socket.zigbee:__expect_send({ mock_device.id,
      AnalogInput.attributes.PresentValue:read(mock_device):to_endpoint(POWER_METER_ENDPOINT) })
  end
)

test.register_coroutine_test(
  "Capability on command should be handled : parent device",
  function()
    test.socket.capability:__queue_receive({ mock_device.id,
      { capability = "switch", component = "main", command = "on", args = {} } })
    mock_device:expect_native_cmd_handler_registration("switch", "on")
    test.socket.zigbee:__expect_send({ mock_device.id,
      OnOff.server.commands.On(mock_device) })
  end
)

test.register_coroutine_test(
  "Capability on command should be handled : child device",
  function()
    test.socket.capability:__queue_receive({ mock_child.id,
      { capability = "switch", component = "main", command = "on", args = {} } })
    mock_child:expect_native_cmd_handler_registration("switch", "on")
    test.socket.zigbee:__expect_send({ mock_device.id,
      OnOff.server.commands.On(mock_device):to_endpoint(0x02) })
  end
)

test.register_coroutine_test(
  "Capability off command should be handled : parent device",
  function()
    test.socket.capability:__queue_receive({ mock_device.id,
      { capability = "switch", component = "main", command = "off", args = {} } })
    mock_device:expect_native_cmd_handler_registration("switch", "off")
    test.socket.zigbee:__expect_send({ mock_device.id,
      OnOff.server.commands.Off(mock_device) })
  end
)

test.register_coroutine_test(
  "Capability off command should be handled : child device",
  function()
    test.socket.capability:__queue_receive({ mock_child.id,
      { capability = "switch", component = "main", command = "off", args = {} } })
    mock_child:expect_native_cmd_handler_registration("switch", "off")
    test.socket.zigbee:__expect_send({ mock_device.id,
      OnOff.server.commands.Off(mock_device):to_endpoint(0x02) })
  end
)

test.register_coroutine_test(
  "Wireless button pushed report should be correctly handled : parent device",
  function()
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, WIRELESS_SWITCH_CLUSTER_ID, {
        { WIRELESS_SWITCH_ATTRIBUTE_ID, data_types.Uint16.ID, WIRELESS_SWITCH_PUSHED_VALUE }
      }, MFG_CODE):from_endpoint(BUTTON_1_ENDPOINT)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.button.button.pushed({ state_change = true })))
  end
)

test.register_coroutine_test(
  "Wireless button pushed report should be correctly handled : child device",
  function()
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, WIRELESS_SWITCH_CLUSTER_ID, {
        { WIRELESS_SWITCH_ATTRIBUTE_ID, data_types.Uint16.ID, WIRELESS_SWITCH_PUSHED_VALUE }
      }, MFG_CODE):from_endpoint(BUTTON_2_ENDPOINT)
    })
    test.socket.capability:__expect_send(mock_child:generate_test_message("main",
      capabilities.button.button.pushed({ state_change = true })))
  end
)

test.register_coroutine_test(
  "Power meter handled",
  function()
    mock_device:set_field(PRIVATE_MODE, 1, { persist = true })

    test.socket.zigbee:__queue_receive({
      mock_device.id,
      AnalogInput.attributes.PresentValue:build_test_attr_report(mock_device,
        SinglePrecisionFloat(0, 9, 0.953125)):from_endpoint(POWER_METER_ENDPOINT)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.powerMeter.power({ value = 1000.0, unit = "W" }))
    )
    test.socket.zigbee:__expect_send({ mock_device.id,
      AnalogInput.attributes.PresentValue:read(mock_device):to_endpoint(ENERGY_METER_ENDPOINT) })
  end
)

test.register_coroutine_test(
  "Energy meter handled",
  function()
    mock_device:set_field(PRIVATE_MODE, 1, { persist = true })

    local current_time = os.time() - 60 * 20
    mock_device:set_field(LAST_REPORT_TIME, current_time)

    test.socket.zigbee:__queue_receive({
      mock_device.id,
      AnalogInput.attributes.PresentValue:build_test_attr_report(mock_device,
        SinglePrecisionFloat(0, 9, 0.953125)):from_endpoint(ENERGY_METER_ENDPOINT)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.energyMeter.energy({ value = 1000000.0, unit = "Wh" }))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.powerConsumptionReport.powerConsumption({ deltaEnergy = 0.0, energy = 1000000.0 }))
    )
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
  "Handle changeToWirelessSwitch in infochanged",
  function()
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({
      preferences = { ["stse.changeToWirelessSwitch"] = true }
    }))
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID,
        CHANGE_TO_WIRELESS_SWITCH_ATTRIBUTE_ID, MFG_CODE, data_types.Uint8, 0) })
  end
)

test.run_registered_tests()
