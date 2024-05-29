-- Copyright 2023 SmartThings
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
local zigbee_test_utils = require "integration_test.zigbee_test_utils"

local OnOff = clusters.OnOff
local Level = clusters.Level
local ColorControl = clusters.ColorControl

local PRIVATE_CLUSTER_ID = 0xFCC0
local PRIVATE_ATTRIBUTE_ID = 0x0009
local MFG_CODE = 0x115F

local RESTORE_POWER_STATE_ATTRIBUTE_ID = 0x0201

local mock_device = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("aqara-led-bulb.yml"),
    fingerprinted_endpoint_id = 0x01,
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "Aqara",
        model = "lumi.light.acn014",
        server_clusters = { 0x0006, 0x0008, 0x0300 }
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
  "Configure should configure all necessary attributes and refresh device",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
    test.socket.zigbee:__set_channel_ordering("relaxed")

    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, PRIVATE_ATTRIBUTE_ID
          , MFG_CODE, data_types.Uint8, 1)
      }
    )
    test.socket.zigbee:__expect_send({ mock_device.id, Level.attributes.OnTransitionTime:write(mock_device, 0) })
    test.socket.zigbee:__expect_send({ mock_device.id, Level.attributes.OffTransitionTime:write(mock_device, 0) })
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        ColorControl.commands.MoveToColorTemperature(mock_device, 200, 0)
      }
    )

    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, Level.ID)
    })
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        Level.attributes.CurrentLevel:configure_reporting(mock_device, 1, 3600, 1)
      }
    )
    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, ColorControl.ID)
    })
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        ColorControl.attributes.ColorTemperatureMireds:configure_reporting(mock_device, 1, 3600, 16)
      }
    )
    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, OnOff.ID)
    })
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        OnOff.attributes.OnOff:configure_reporting(mock_device, 0, 300, 1)
      }
    )

    test.socket.zigbee:__expect_send({ mock_device.id, OnOff.attributes.OnOff:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, Level.attributes.CurrentLevel:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.ColorTemperatureMireds:read(mock_device) })

    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)

test.register_coroutine_test(
  "Set Color Temperature command test",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({ mock_device.id,
      { capability = "colorTemperature", component = "main", command = "setColorTemperature", args = { 200 } } })

    local temp_in_mired = math.floor(1000000 / 200)
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        OnOff.commands.On(mock_device)
      }
    )
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        ColorControl.commands.MoveToColorTemperature(mock_device, temp_in_mired, 0x0000)
      }
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

test.run_registered_tests()
