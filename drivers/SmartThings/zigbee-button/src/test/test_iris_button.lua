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
local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local t_utils = require "integration_test.utils"
local test = require "integration_test"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"

local OnOff = clusters.OnOff
local IASZone = clusters.IASZone
local PowerConfiguration = clusters.PowerConfiguration
local IasEnrollResponseCode = IASZone.types.EnrollResponseCode

local button_attr = capabilities.button.button

local mock_device = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("one-button-battery.yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "CentraLite",
        model = "3455-L",
        server_clusters = {0x0000, 0x0001, 0x0003, 0x0006, 0x0020, 0x0500, 0x0B05}
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

test.register_coroutine_test(
  "OnOff cluster commands should result with sending pushed events for button",
  function()
    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, OnOff.ID, OnOff.server.commands.On.ID, 0x0000, "\x00", 0x04) })
    test.wait_for_events()
    test.mock_time.advance_time(0.1)
    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, OnOff.ID, OnOff.server.commands.Off.ID, 0x0000, "\x00", 0x04) })
    test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", button_attr.pushed({ state_change = true }))
    )
  end
)

test.register_coroutine_test(
  "OnOff cluster commands should result with sending held events for button",
  function()
    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, OnOff.ID, OnOff.server.commands.On.ID, 0x0000, "\x00", 0x04) })
    test.wait_for_events()
    test.mock_time.advance_time(8)
    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, OnOff.ID, OnOff.server.commands.Off.ID, 0x0000, "\x00", 0x04) })
    test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", button_attr.held({ state_change = true }))
    )
  end
)

test.register_coroutine_test(
  "Configure should configure all necessary attributes",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.zigbee:__expect_send({
      mock_device.id,
      PowerConfiguration.attributes.BatteryVoltage:configure_reporting(
        mock_device, 30, 21600, 1
      )
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(
        mock_device,
        zigbee_test_utils.mock_hub_eui,
        PowerConfiguration.ID
      )
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(
        mock_device,
        zigbee_test_utils.mock_hub_eui,
        OnOff.ID
      )
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      IASZone.attributes.IASCIEAddress:write(mock_device, zigbee_test_utils.mock_hub_eui)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      IASZone.server.commands.ZoneEnrollResponse(mock_device, IasEnrollResponseCode.SUCCESS, 0x00)
    })
    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)

test.register_coroutine_test(
    "Refresh should read the battery voltage",
    function()
      test.socket.capability:__queue_receive({ mock_device.id, { capability = "refresh", component = "main", command = "refresh", args = {} } })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        PowerConfiguration.attributes.BatteryVoltage:read(mock_device)
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        IASZone.attributes.ZoneStatus:read(mock_device)
      })
    end
)

test.register_coroutine_test(
  "added lifecycle event",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.button.supportedButtonValues({ "pushed", "held" }, { visibility = { displayed = false } })
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.button.numberOfButtons({ value = 1 }, { visibility = { displayed = false } })
      )
    )
    -- test.socket.capability:__expect_send({
    --   mock_device.id,
    --   {
    --     capability_id = "button", component_id = "main",
    --     attribute_id = "button", state = { value = "pushed" }
    --   }
    -- })

    test.socket.zigbee:__expect_send({
      mock_device.id,
      PowerConfiguration.attributes.BatteryVoltage:read(mock_device)
    })
  end
)

test.register_coroutine_test(
  "OnOff cluster commands should result with sending pushed events for button",
  function()
    test.socket.device_lifecycle():__queue_receive(mock_device:generate_info_changed({
      preferences = {
        holdTime = 1
      }
    }))
    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, OnOff.ID, OnOff.server.commands.On.ID, 0x0000, "\x00", 0x04) })
    test.wait_for_events()
    test.mock_time.advance_time(0.9)
    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, OnOff.ID, OnOff.server.commands.Off.ID, 0x0000, "\x00", 0x04) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", button_attr.pushed({ state_change = true }))
    )
  end
)

test.register_coroutine_test(
  "OnOff cluster commands should result with sending held events for button",
  function()
    test.socket.device_lifecycle():__queue_receive(mock_device:generate_info_changed({
      preferences = {
        holdTime = 1
      }
    }))
    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, OnOff.ID, OnOff.server.commands.On.ID, 0x0000, "\x00", 0x04) })
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, OnOff.ID, OnOff.server.commands.Off.ID, 0x0000, "\x00", 0x04) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", button_attr.held({ state_change = true }))
    )
  end
)

test.register_coroutine_test(
  "OnOff cluster commands should result with sending pushed events for button",
  function()
    test.socket.device_lifecycle():__queue_receive(mock_device:generate_info_changed({
      preferences = {
        holdTime = 3
      }
    }))
    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, OnOff.ID, OnOff.server.commands.On.ID, 0x0000, "\x00", 0x04) })
    test.wait_for_events()
    test.mock_time.advance_time(2.9)
    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, OnOff.ID, OnOff.server.commands.Off.ID, 0x0000, "\x00", 0x04) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", button_attr.pushed({ state_change = true }))
    )
  end
)

test.register_coroutine_test(
  "OnOff cluster commands should result with sending held events for button",
  function()
    test.socket.device_lifecycle():__queue_receive(mock_device:generate_info_changed({
      preferences = {
        holdTime = 3
      }
    }))
    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, OnOff.ID, OnOff.server.commands.On.ID, 0x0000, "\x00", 0x04) })
    test.wait_for_events()
    test.mock_time.advance_time(3)
    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, OnOff.ID, OnOff.server.commands.Off.ID, 0x0000, "\x00", 0x04) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", button_attr.held({ state_change = true }))
    )
  end
)

test.run_registered_tests()
