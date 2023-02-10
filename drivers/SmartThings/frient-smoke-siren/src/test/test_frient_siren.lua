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
local test                            = require "integration_test"
local t_utils                         = require "integration_test.utils"

local cluster_base                    = require "st.zigbee.cluster_base"
local data_types                      = require "st.zigbee.data_types"
local clusters                        = require "st.zigbee.zcl.clusters"
local Basic                           = clusters.Basic
local IASZone                         = clusters.IASZone
local IASWD                           = clusters.IASWD
local PowerConfiguration              = clusters.PowerConfiguration
local SirenConfiguration              = require "st.zigbee.generated.zcl_clusters.IASWD.types.SirenConfiguration"
local SquawkConfiguration             = require "st.zigbee.generated.zcl_clusters.IASWD.types.SquawkConfiguration"

local capabilities                    = require "st.capabilities"
local zigbee_test_utils               = require "integration_test.zigbee_test_utils"

local IasEnrollResponseCode           = require "st.zigbee.generated.zcl_clusters.IASZone.types.EnrollResponseCode"
local base64                          = require "st.base64"

local PRIMARY_SW_VERSION_ATTRIBUTE_ID = 0x8000
local MFG_CODE                        = 0x1015

local mock_device                     = test.mock_device.build_test_zigbee_device(
    { profile = t_utils.get_profile_definition("siren-battery-source-tamper.yml"),
      zigbee_endpoints = {
        [0x01] = {
          id = 0x01,
          manufacturer = "frient A/S",
          model = "SIRZB-110",
          server_clusters = { 0x0005, 0x0006 }
        },
        [0x2B] = {
          id = 0x2B,
          server_clusters = { 0x0000, 0x0001, 0x0003, 0x0004, 0x0500, 0x0502, 0xFC05 }
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
    "Handle added lifecycle",
    function()
      test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
      test.socket.capability:__expect_send(
          mock_device:generate_test_message("main", capabilities.tamperAlert.tamper.clear())
      )
      test.socket.capability:__expect_send(
          mock_device:generate_test_message("main", capabilities.alarm.alarm.off())
      )
      test.socket.zigbee:__expect_send(
          {
            mock_device.id,
            cluster_base.read_manufacturer_specific_attribute(mock_device, Basic.ID, PRIMARY_SW_VERSION_ATTRIBUTE_ID,
                MFG_CODE, data_types.OctetString)
          }
      )
    end
)

test.register_coroutine_test(
    "Handle doConfigure lifecycle",
    function()
      test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
      test.socket.zigbee:__set_channel_ordering("relaxd")

      test.socket.zigbee:__expect_send({
        mock_device.id,
        zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, PowerConfiguration.ID, 0x2B)
                         :to_endpoint(0x2B)
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        PowerConfiguration.attributes.BatteryPercentageRemaining:configure_reporting(mock_device, 30, 21600, 1)
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, IASZone.ID, 0x2B)
                         :to_endpoint(0x2B)
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        IASZone.attributes.ZoneStatus:configure_reporting(mock_device, 0, 180, 0)
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        IASZone.attributes.IASCIEAddress:write(mock_device, zigbee_test_utils.mock_hub_eui)
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        IASZone.server.commands.ZoneEnrollResponse(
            mock_device,
            IasEnrollResponseCode.SUCCESS,
            0x00
        )
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        IASWD.attributes.MaxDuration:write(mock_device, 0x00F0)
      })
      mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    end
)

test.register_message_test(
    "Refresh Capability Command should refresh device",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_device.id, { capability = "refresh", command = "refresh", args = { } } }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_device.id, PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device) }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_device.id, IASZone.attributes.ZoneStatus:read(mock_device) }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_device.id, zigbee_test_utils.build_attribute_read(mock_device, Basic.ID, { PRIMARY_SW_VERSION_ATTRIBUTE_ID }, MFG_CODE):to_endpoint(0x2B) }
      }
    }
)

test.register_message_test(
    "Capability(alarm) command(both) on should be handled",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_device.id, { capability = "alarm", component = "main", command = "both", args = { } } }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_device.id, zigbee_test_utils.build_attribute_read(mock_device, Basic.ID, { PRIMARY_SW_VERSION_ATTRIBUTE_ID }, MFG_CODE):to_endpoint(0x2B) }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_device.id, IASWD.server.commands.StartWarning(mock_device,
            SirenConfiguration(0x17),
            data_types.Uint16(0x00F0),
            data_types.Uint8(0x28),
            data_types.Enum8(0x03)) }
      }
    }
)

test.register_message_test(
    "Capability(alarm) command(off) on should be handled",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_device.id, { capability = "alarm", component = "main", command = "off", args = { } } }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_device.id, zigbee_test_utils.build_attribute_read(mock_device, Basic.ID, { PRIMARY_SW_VERSION_ATTRIBUTE_ID }, MFG_CODE):to_endpoint(0x2B) }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_device.id, IASWD.server.commands.StartWarning(mock_device,
            SirenConfiguration(00),
            data_types.Uint16(0x00F0),
            data_types.Uint8(00),
            data_types.Enum8(00)) }
      }
    }
)

test.register_message_test(
    "Capability(alarm) command(siren) on should be handled",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_device.id, { capability = "alarm", component = "main", command = "siren", args = { } } }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_device.id, zigbee_test_utils.build_attribute_read(mock_device, Basic.ID, { PRIMARY_SW_VERSION_ATTRIBUTE_ID }, MFG_CODE):to_endpoint(0x2B) }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_device.id, IASWD.server.commands.StartWarning(mock_device,
            SirenConfiguration(0x13),
            data_types.Uint16(0x00F0),
            data_types.Uint8(00),
            data_types.Enum8(00)) }
      }
    }
)

test.register_message_test(
    "Capability(alarm) command(strobe) on should be handled",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_device.id, { capability = "alarm", component = "main", command = "strobe", args = { } } }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_device.id, zigbee_test_utils.build_attribute_read(mock_device, Basic.ID, { PRIMARY_SW_VERSION_ATTRIBUTE_ID }, MFG_CODE):to_endpoint(0x2B) }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_device.id, IASWD.server.commands.StartWarning(mock_device,
            SirenConfiguration(0x04),
            data_types.Uint16(0x00F0),
            data_types.Uint8(0x28),
            data_types.Enum8(0x03)) }
      }
    }
)

test.register_message_test(
    "Capability(tone) command(beep) on should be handled",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_device.id, { capability = "tone", component = "main", command = "beep", args = { } } }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_device.id, zigbee_test_utils.build_attribute_read(mock_device, Basic.ID, { PRIMARY_SW_VERSION_ATTRIBUTE_ID }, MFG_CODE):to_endpoint(0x2B) }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_device.id, IASWD.server.commands.Squawk(mock_device,
            SquawkConfiguration(0x0B)) }
      }
    }
)

test.register_message_test(
    "Battery percentage remaining report should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, PowerConfiguration.attributes.BatteryPercentageRemaining:build_test_attr_report(mock_device, 30) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.battery.battery(15))
      }
    }
)

test.register_coroutine_test(
    "Setting a max duration should be handled",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.zigbee:__queue_receive({ mock_device.id, IASWD.attributes.MaxDuration:build_test_attr_report(mock_device, 50) })

      test.wait_for_events()
      test.mock_time.advance_time(1)

      test.socket.capability:__queue_receive({ mock_device.id, { capability = "alarm", component = "main", command = "siren", args = { } } })

      test.socket.zigbee:__expect_send({ mock_device.id,
                                         zigbee_test_utils.build_attribute_read(mock_device, Basic.ID, { PRIMARY_SW_VERSION_ATTRIBUTE_ID }, MFG_CODE)
                                                          :to_endpoint(0x2B) })
      test.socket.zigbee:__expect_send({ mock_device.id, IASWD.server.commands.StartWarning(mock_device,
          SirenConfiguration(0x13),
          data_types.Uint16(0x0032),
          data_types.Uint8(0),
          data_types.Enum8(0)) })
    end
)

test.register_coroutine_test(
    "Health check should check all relevant attributes",
    function()
      test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })

      test.mock_time.advance_time(50000) -- battery is 21600 for max reporting interval
      test.socket.zigbee:__set_channel_ordering("relaxed")

      test.socket.zigbee:__expect_send(
          {
            mock_device.id,
            PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device)
          }
      )
      test.socket.zigbee:__expect_send(
          {
            mock_device.id,
            IASZone.attributes.ZoneStatus:read(mock_device)
          }
      )
      test.socket.capability:__expect_send(
          mock_device:generate_test_message("main", capabilities.tamperAlert.tamper.clear())
      )
      test.socket.capability:__expect_send(
          mock_device:generate_test_message("main", capabilities.alarm.alarm.off())
      )
      test.socket.zigbee:__expect_send(
          {
            mock_device.id,
            cluster_base.read_manufacturer_specific_attribute(mock_device, Basic.ID, PRIMARY_SW_VERSION_ATTRIBUTE_ID,
                MFG_CODE, data_types.OctetString)
          }
      )
    end,
    {
      test_init = function()
        test.mock_device.add_test_device(mock_device)
        test.timer.__create_and_queue_test_time_advance_timer(30, "interval", "health_check")
      end
    }
)

test.run_registered_tests()
