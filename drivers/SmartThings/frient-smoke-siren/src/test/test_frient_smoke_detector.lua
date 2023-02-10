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
local TemperatureMeasurement          = clusters.TemperatureMeasurement

local ZoneStatusAttribute             = IASZone.attributes.ZoneStatus

local capabilities                    = require "st.capabilities"
local zigbee_test_utils               = require "integration_test.zigbee_test_utils"

local IasEnrollResponseCode           = require "st.zigbee.generated.zcl_clusters.IASZone.types.EnrollResponseCode"
local base64                          = require "st.base64"

local PRIMARY_SW_VERSION_ATTRIBUTE_ID = 0x8000
local MFG_CODE                        = 0x1015

local mock_device                     = test.mock_device.build_test_zigbee_device(
    { profile          = t_utils.get_profile_definition("smoke-siren-temperature-battery.yml"),
      zigbee_endpoints = {
        [0x01] = {
          id              = 0x01,
          manufacturer    = "frient A/S",
          model           = "SMSZB-120",
          server_clusters = { 0x0003, 0x0005, 0x0006 }
        },
        [0x23] = {
          id              = 0x23,
          server_clusters = { 0x0000, 0x0001, 0x0003, 0x000f, 0x0020, 0x0500, 0x0502 }
        },
        [0x26] = {
          id              = 0x26,
          server_clusters = { 0x0000, 0x0003, 0x0402 }
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
          mock_device:generate_test_message("main", capabilities.smokeDetector.smoke.clear())
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
        zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, PowerConfiguration.ID, 0x23)
                         :to_endpoint(0x23)
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        PowerConfiguration.attributes.BatteryVoltage:configure_reporting(mock_device, 30, 21600, 1)
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, IASZone.ID, 0x23)
                         :to_endpoint(0x23)
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
        zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, TemperatureMeasurement.ID, 0x26)
                         :to_endpoint(0x26)
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        TemperatureMeasurement.attributes.MeasuredValue:configure_reporting(mock_device, 30, 300, 16)
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        IASWD.attributes.MaxDuration:write(mock_device, 0x00F0)
      })
      mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    end
)

test.register_message_test(
    "Battery voltage report should be handled",
    {
      {
        channel   = "zigbee",
        direction = "receive",
        message   = { mock_device.id, PowerConfiguration.attributes.BatteryVoltage:build_test_attr_report(mock_device, 30) }
      },
      {
        channel   = "capability",
        direction = "send",
        message   = mock_device:generate_test_message("main", capabilities.battery.battery(100))
      }
    }
)

test.register_coroutine_test(
    "Health check should check all relevant attributes",
    function()
      test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })

      test.mock_time.advance_time(50000) -- battery is 21600 for max reporting interval
      test.socket.zigbee:__set_channel_ordering("relaxed")
      test.socket.capability:__expect_send(
          mock_device:generate_test_message("main", capabilities.smokeDetector.smoke.clear())
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
      test.socket.zigbee:__expect_send(
          {
            mock_device.id,
            PowerConfiguration.attributes.BatteryVoltage:read(mock_device)
          }
      )
      test.socket.zigbee:__expect_send(
          {
            mock_device.id,
            IASZone.attributes.ZoneStatus:read(mock_device)
          }
      )
      test.socket.zigbee:__expect_send(
          {
            mock_device.id,
            TemperatureMeasurement.attributes.MeasuredValue:read(mock_device)
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
