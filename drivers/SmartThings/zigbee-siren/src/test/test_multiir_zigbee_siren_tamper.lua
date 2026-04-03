-- Copyright 2026 SmartThings
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
local OnOff = clusters.OnOff
local IASZone = clusters.IASZone
local IASWD = clusters.IASWD
local SirenConfiguration = IASWD.types.SirenConfiguration
local DEFAULT_MAX_WARNING_DURATION = 1800
local ALARM_STROBE_DUTY_CYCLE = 40
local capabilities = require "st.capabilities"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local data_types = require "st.zigbee.data_types"
local t_utils = require "integration_test.utils"

local mock_device = test.mock_device.build_test_zigbee_device(
        {
            profile = t_utils.get_profile_definition("switch-alarm-tamper-warningduration-volume.yml"),
            zigbee_endpoints = {
                [0x01] = {
                    id = 0x01,
                    manufacturer = "MultIR",
                    model = "MIR-SR100",
                    server_clusters = { IASWD.ID, IASZone.ID,OnOff.ID}
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
  "doConifigure lifecycle should configure device",
  function ()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
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

  mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Handle added lifecycle",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.switch.switch.off()))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.alarm.alarm.off()))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.tamperAlert.tamper.clear()))
    test.socket.zigbee:__expect_send({ mock_device.id,
      IASWD.attributes.MaxDuration:read(mock_device)})
  end,
  {
     min_api_version = 19
  }
)

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
                                                                            data_types.Uint16(DEFAULT_MAX_WARNING_DURATION),
                                                                            data_types.Uint8(ALARM_STROBE_DUTY_CYCLE),
                                                                            data_types.Enum8(3)) }
    }
  },
  {
     min_api_version = 19
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
                                                                            data_types.Uint16(DEFAULT_MAX_WARNING_DURATION),
                                                                            data_types.Uint8(ALARM_STROBE_DUTY_CYCLE),
                                                                            data_types.Enum8(0)) }
    }
  },
  {
     min_api_version = 19
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
                                                                            data_types.Uint16(DEFAULT_MAX_WARNING_DURATION),
                                                                            data_types.Uint8(ALARM_STROBE_DUTY_CYCLE),
                                                                            data_types.Enum8(3)) }
    }
  },
  {
     min_api_version = 19
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
                                                                            data_types.Uint16(DEFAULT_MAX_WARNING_DURATION),
                                                                            data_types.Uint8(ALARM_STROBE_DUTY_CYCLE),
                                                                            data_types.Enum8(0)) }
    }
  },
  {
     min_api_version = 19
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
                                                                            data_types.Uint16(DEFAULT_MAX_WARNING_DURATION),
                                                                            data_types.Uint8(ALARM_STROBE_DUTY_CYCLE),
                                                                            data_types.Enum8(0)) }
    }
  },
  {
     min_api_version = 19
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
                                                                            SirenConfiguration(0x07),
                                                                            data_types.Uint16(DEFAULT_MAX_WARNING_DURATION),
                                                                            data_types.Uint8(ALARM_STROBE_DUTY_CYCLE),
                                                                            data_types.Enum8(3)) }
    }
  },
  {
     min_api_version = 19
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
    }
  },
  {
    inner_block_ordering = "relaxed",
    min_api_version = 19
  }
)

test.register_message_test(
  "ZoneStatusChangeNotification should be handled: tamper/detected",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, IASZone.client.commands.ZoneStatusChangeNotification.build_test_rx(mock_device, 0x0004, 0x00) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.tamperAlert.tamper.detected())
    }
  },
  {
     min_api_version = 19
  }
)

test.register_message_test(
  "ZoneStatusChangeNotification should be handled: tamper/clear",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, IASZone.client.commands.ZoneStatusChangeNotification.build_test_rx(mock_device, 0x0000, 0x00) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.tamperAlert.tamper.clear())
    }
  },
  {
     min_api_version = 19
  }
)

test.register_message_test(
  "Reported ZoneStatus should be handled:  tamper/clear",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, IASZone.attributes.ZoneStatus:build_test_attr_report(mock_device, 0x0000) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.tamperAlert.tamper.clear())
    }
  },
  {
     min_api_version = 19
  }
)

test.register_message_test(
  "Reported ZoneStatus should be handled:  tamper/detected",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, IASZone.attributes.ZoneStatus:build_test_attr_report(mock_device, 0x0004) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.tamperAlert.tamper.detected())
    }
  },
  {
     min_api_version = 19
  }
)

test.run_registered_tests()
