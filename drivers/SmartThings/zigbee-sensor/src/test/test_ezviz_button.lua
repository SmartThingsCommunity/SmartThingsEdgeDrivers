-- Copyright 2025 SmartThings
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
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"
local dkjson = require 'dkjson'
local utils = require "st.utils"
local zb_const = require "st.zigbee.constants"
local messages = require "st.zigbee.messages"
local data_types = require "st.zigbee.data_types"
local zcl_messages = require "st.zigbee.zcl"
local IasEnrollResponseCode = require "st.zigbee.generated.zcl_clusters.IASZone.types.EnrollResponseCode"
local report_attr = require "st.zigbee.zcl.global_commands.report_attribute"

local IASZone = clusters.IASZone
local PowerConfiguration = clusters.PowerConfiguration
local ZoneStatusAttribute = IASZone.attributes.ZoneStatus

local EZVIZ_PRIVATE_CLUSTER = 0xFE05
local EZVIZ_PRIVATE_ATTR = 0x0000

local ZIGBEE_GENERIC_REMOTE_CONTROL = "generic-remote-control"

local mock_device_ezviz_button = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition(ZIGBEE_GENERIC_REMOTE_CONTROL .. ".yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "EZVIZ",
        server_clusters = { 0x0500, 0x0001 }
      }
    }
  }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device_ezviz_button)
  zigbee_test_utils.init_noop_health_check_timer()
end

test.set_test_init_function(test_init)

test.register_message_test(
    "Battery percentage report should be handled (button)",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device_ezviz_button.id, PowerConfiguration.attributes.BatteryPercentageRemaining:build_test_attr_report(mock_device_ezviz_button, 55) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device_ezviz_button:generate_test_message("main", capabilities.battery.battery(28))
      }
    }
)

local function build_test_attr_report(device, value)
    local report_body = report_attr.ReportAttribute({
      report_attr.ReportAttributeAttributeRecord(EZVIZ_PRIVATE_ATTR, data_types.Uint8.ID, value)
    })
    local zclh = zcl_messages.ZclHeader({
      cmd = data_types.ZCLCommandId(report_body.ID)
    })
    local addrh = messages.AddressHeader(
      device:get_short_address(),
      device.fingerprinted_endpoint_id,
      zb_const.HUB.ADDR,
      zb_const.HUB.ENDPOINT,
      zb_const.HA_PROFILE_ID,
      EZVIZ_PRIVATE_CLUSTER
    )
    local message_body = zcl_messages.ZclMessageBody({
      zcl_header = zclh,
      zcl_body = report_body
    })
    return messages.ZigbeeMessageRx({
      address_header = addrh,
      body = message_body
    })
end

test.register_message_test(
    "EZVIZ private attribute report should result with sending pushed event",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device_ezviz_button.id, build_test_attr_report(mock_device_ezviz_button, 0x01) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device_ezviz_button:generate_test_message("main", capabilities.button.button.pushed({ state_change = true }))
      }
    }
)

test.register_message_test(
    "EZVIZ private attribute report should result with sending double event",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device_ezviz_button.id, build_test_attr_report(mock_device_ezviz_button, 0x02) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device_ezviz_button:generate_test_message("main", capabilities.button.button.double({ state_change = true }))
      }
    }
)

test.register_message_test(
    "EZVIZ private attribute report should result with sending held event",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device_ezviz_button.id, build_test_attr_report(mock_device_ezviz_button, 0x03) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device_ezviz_button:generate_test_message("main", capabilities.button.button.held({ state_change = true }))
      }
    }
)

test.register_coroutine_test(
    "Health check should check all relevant attributes",
    function()
      test.mock_time.advance_time(50000)
      test.socket.zigbee:__set_channel_ordering("relaxed")
      test.socket.zigbee:__expect_send({ mock_device_ezviz_button.id, PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device_ezviz_button) })
      test.wait_for_events()
    end,
    {
      test_init = function()
        test.mock_device.add_test_device(mock_device_ezviz_button)
        test.timer.__create_and_queue_test_time_advance_timer(30, "interval", "health_check")
      end
    }
)

test.register_coroutine_test(
    "Refresh necessary attributes",
    function()
      test.wait_for_events()

      test.socket.zigbee:__set_channel_ordering("relaxed")
      test.socket.capability:__queue_receive({ mock_device_ezviz_button.id, { capability = "refresh", component = "main", command = "refresh", args = {} } })
      test.socket.zigbee:__expect_send(
        {
          mock_device_ezviz_button.id,
          PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device_ezviz_button)
        }
      )
      test.socket.zigbee:__expect_send({ mock_device_ezviz_button.id, ZoneStatusAttribute:read(mock_device_ezviz_button) })
    end
)

test.register_coroutine_test(
    "Configure should configure all necessary attributes",
    function()
      local device_info_copy = utils.deep_copy(mock_device_ezviz_button.raw_st_data)
      device_info_copy.profile.id = "generic-remote-control"
      local device_info_json = dkjson.encode(device_info_copy)
      test.wait_for_events()

      test.socket.zigbee:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle:__queue_receive({ mock_device_ezviz_button.id, "doConfigure" })
      test.socket.zigbee:__expect_send(
          {
            mock_device_ezviz_button.id,
            zigbee_test_utils.build_bind_request(mock_device_ezviz_button,
                                                 zigbee_test_utils.mock_hub_eui,
                                                 PowerConfiguration.ID)
          }
      )
      test.socket.zigbee:__expect_send(
        {
          mock_device_ezviz_button.id,
          PowerConfiguration.attributes.BatteryPercentageRemaining:configure_reporting(mock_device_ezviz_button,
                                                                   30,
                                                                   21600,
                                                                   1)
        }
      )
      test.socket.zigbee:__expect_send(
        {
        mock_device_ezviz_button.id,
        PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device_ezviz_button)
      })
      test.socket.zigbee:__expect_send({
        mock_device_ezviz_button.id,
        IASZone.attributes.IASCIEAddress:write(mock_device_ezviz_button, zigbee_test_utils.mock_hub_eui)
      })
      test.socket.zigbee:__expect_send({
        mock_device_ezviz_button.id,
        IASZone.server.commands.ZoneEnrollResponse(mock_device_ezviz_button, IasEnrollResponseCode.SUCCESS, 0x00)
      })


      test.socket.zigbee:__expect_send(
          {
            mock_device_ezviz_button.id,
            IASZone.attributes.ZoneStatus:configure_reporting(mock_device_ezviz_button,
                                                                     30,
                                                                     300,
                                                                     0)
          }
      )
      test.socket.zigbee:__expect_send(
          {
            mock_device_ezviz_button.id,
            zigbee_test_utils.build_bind_request(mock_device_ezviz_button,
                                                 zigbee_test_utils.mock_hub_eui,
                                                 IASZone.ID)
          }
      )
      test.socket.device_lifecycle:__queue_receive({ mock_device_ezviz_button.id, "infoChanged", device_info_json })
      test.socket.zigbee:__expect_send({ mock_device_ezviz_button.id, IASZone.attributes.ZoneStatus:read(mock_device_ezviz_button) })

      mock_device_ezviz_button:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    end
)

test.run_registered_tests()