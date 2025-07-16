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
local test = require "integration_test"
local clusters = require "st.zigbee.zcl.clusters"
local IASZone = clusters.IASZone
local IASWD = clusters.IASWD
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local data_types = require "st.zigbee.data_types"
local SirenConfiguration = require "st.zigbee.generated.zcl_clusters.IASWD.types.SirenConfiguration"
local t_utils = require "integration_test.utils"

local mock_device = test.mock_device.build_test_zigbee_device(
    {
      profile = t_utils.get_profile_definition("switch-alarm.yml"),
      zigbee_endpoints   = {
        [1] = {
          id = 1,
          manufacturer = "ClimaxTechnology",
          model = "SRAC_00.00.00.16TC",
          server_clusters = { 0x0000, 0x0003, 0x0500, 0x0502 }
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

test.register_message_test(
    "Capability(switch) command(on) on should be handled",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_device.id, { capability = "switch", command = "on", args = { } } }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_device.id, IASWD.server.commands.StartWarning(mock_device,
                                                                              SirenConfiguration(0x13),
                                                                              data_types.Uint16(0x00B4),
                                                                              data_types.Uint8(40),
                                                                              data_types.Enum8(0))
        }
      }
    }
)

test.register_coroutine_test(
    "doConifigure lifecycle should configure device",
    function ()
      test.socket.zigbee:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         IASWD.attributes.MaxDuration:write(mock_device, 0xFFFE)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, IASZone.ID)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         IASZone.attributes.ZoneStatus:configure_reporting(mock_device, 0, 180, 0)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         IASZone.attributes.ZoneStatus:read(mock_device)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         IASZone.attributes.IASCIEAddress:write(mock_device, zigbee_test_utils.mock_hub_eui)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         IASZone.server.commands.ZoneEnrollResponse(mock_device, 0x00, 0x00)
                                       })

      mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    end
)

test.register_message_test(
    "Refresh should read all necessary attributes",
    {
      {
        channel = "capability",
        direction = "receive",
        message = {
          mock_device.id,
          { capability = "refresh", component = "main", command = "refresh", args = {} }
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = {
          mock_device.id,
          IASZone.attributes.ZoneStatus:read(mock_device)
        }
      },
    },
    {
      inner_block_ordering = "relaxed"
    }
)

test.run_registered_tests()
