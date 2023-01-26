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
local zcl_cmds = require "st.zigbee.zcl.global_commands"
local IASZone = clusters.IASZone
local IASWD = clusters.IASWD
local OnOff = clusters.OnOff
local PowerConfiguration = clusters.PowerConfiguration
local TemperatureMeasurement = clusters.TemperatureMeasurement
local capabilities = require "st.capabilities"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local base64 = require "st.base64"
local data_types = require "st.zigbee.data_types"
local SirenConfiguration = require "st.zigbee.generated.zcl_clusters.IASWD.types.SirenConfiguration"

local zigbee_siren_profile = {
  components = {
    main = {
      capabilities = {
        [capabilities.alarm.ID] = { id = capabilities.alarm.ID },
        [capabilities.battery.ID] = { id = capabilities.battery.ID },
        [capabilities.soundSensor.ID] = { id = capabilities.soundSensor.ID },
        [capabilities.switch.ID] = { id = capabilities.switch.ID },
        [capabilities.temperatureMeasurement.ID] = { id = capabilities.temperatureMeasurement.ID },
        [capabilities.refresh.ID] = { id = capabilities.refresh.ID }
      },
      id = "main"
    }
  }
}

local mock_device = test.mock_device.build_test_zigbee_device({ profile = zigbee_siren_profile })
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
                                                                            SirenConfiguration(0x17),
                                                                            data_types.Uint16(0x00B4),
                                                                            data_types.Uint8(40),
                                                                            data_types.Enum8(3)) }
    }
  }
)

test.register_message_test(
  "Capability(switch) command(off) on should be handled",
  {
    {
      channel = "capability",
      direction = "receive",
      message = { mock_device.id, { capability = "switch", component = "main", command = "off", args = { } } }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = { mock_device.id, IASWD.server.commands.StartWarning(mock_device,
                                                                            SirenConfiguration(0x00),
                                                                            data_types.Uint16(0x00B4),
                                                                            data_types.Uint8(0x28),
                                                                            data_types.Enum8(0)) }
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
      message = { mock_device.id, IASWD.server.commands.StartWarning(mock_device,
                                                                            SirenConfiguration(0x17),
                                                                            data_types.Uint16(0x00B4),
                                                                            data_types.Uint8(40),
                                                                            data_types.Enum8(3)) }
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
      message = { mock_device.id, IASWD.server.commands.StartWarning(mock_device,
                                                                            SirenConfiguration(0x00),
                                                                            data_types.Uint16(0x00B4),
                                                                            data_types.Uint8(40),
                                                                            data_types.Enum8(0)) }
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
      message = { mock_device.id, IASWD.server.commands.StartWarning(mock_device,
                                                                            SirenConfiguration(0x13),
                                                                            data_types.Uint16(0x00B4),
                                                                            data_types.Uint8(40),
                                                                            data_types.Enum8(0)) }
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
      message = { mock_device.id, IASWD.server.commands.StartWarning(mock_device,
                                                                            SirenConfiguration(0x04),
                                                                            data_types.Uint16(0x00B4),
                                                                            data_types.Uint8(40),
                                                                            data_types.Enum8(3)) }
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
    test.socket.zigbee:__expect_send({
                                        mock_device.id,
                                        zigbee_test_utils.build_bind_request(mock_device,
                                                                            zigbee_test_utils.mock_hub_eui,
                                                                            OnOff.ID)
                                      })
    test.socket.zigbee:__expect_send({
                                        mock_device.id,
                                        OnOff.attributes.OnOff:configure_reporting(mock_device, 0, 300)
                                      })
    test.socket.zigbee:__expect_send({
                                        mock_device.id,
                                        OnOff.attributes.OnOff:read(mock_device)
                                      })

  mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)

test.register_message_test(
  "added lifecycle event",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = {mock_device.id, "added"}
    },
    -- {
    --   channel = "capability",
    --   direction = "send",
    --   message = mock_device:generate_test_message("main", capabilities.alarm.alarm.off())
    -- },
    -- {
    --   channel = "capability",
    --   direction = "send",
    --   message = mock_device:generate_test_message("main", capabilities.switch.switch.off())
    -- }
  }
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
    {
      channel = "zigbee",
      direction = "send",
      message = {
        mock_device.id,
        OnOff.attributes.OnOff:read(mock_device)
      }
    },
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.register_coroutine_test(
  "Setting an alarm command should be handled",
  function()
    local zcl_messages = require "st.zigbee.zcl"
    local messages = require "st.zigbee.messages"
    local zb_const = require "st.zigbee.constants"
    local buf_lib = require "st.buf"

    mock_device:set_field("alarmCommand", 1, {persist = true})

    local buf_from_str = function(str)
      return buf_lib.Reader(str)
    end

    local frame = " " .. " "

    local default_response = zcl_cmds.DefaultResponse.deserialize(buf_from_str(frame))
    local zclh = zcl_messages.ZclHeader({
      cmd = data_types.ZCLCommandId(zcl_cmds.DefaultResponse.ID)
    })

    local addrh = messages.AddressHeader(
        mock_device:get_short_address(),
        mock_device:get_endpoint(data_types.ClusterId(IASWD.ID)),
        zb_const.HUB.ADDR,
        zb_const.HUB.ENDPOINT,
        zb_const.HA_PROFILE_ID,
        IASWD.ID
    )
    local message_body = zcl_messages.ZclMessageBody({
      zcl_header = zclh,
      zcl_body = default_response
    })

    local msg = messages.ZigbeeMessageRx({
      address_header = addrh,
      body = message_body
    })

    test.socket.zigbee:__queue_receive({ mock_device.id, msg})

    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.alarm.alarm.siren()))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.switch.switch.on()))
  end
)

test.register_coroutine_test(
  "Setting a max duration should be handled",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.zigbee:__queue_receive({ mock_device.id, IASWD.attributes.MaxDuration:build_test_attr_report(mock_device, 50)})

    test.wait_for_events()
    test.mock_time.advance_time(1)

    test.socket.capability:__queue_receive({ mock_device.id, { capability = "alarm", component = "main", command = "siren", args = { } }})

    test.socket.zigbee:__expect_send({ mock_device.id, IASWD.server.commands.StartWarning(mock_device,
                                                                                  SirenConfiguration(0x13),
                                                                                  data_types.Uint16(0x0032),
                                                                                  data_types.Uint8(40),
                                                                                  data_types.Enum8(0)) })
  end
)

test.run_registered_tests()
