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
local clusters = require "st.zigbee.zcl.clusters"
local Basic = clusters.Basic
local OnOff = clusters.OnOff
local IASZone = clusters.IASZone
local capabilities = require "st.capabilities"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils = require "integration_test.utils"

local mock_device = test.mock_device.build_test_zigbee_device(
  { profile = t_utils.get_profile_definition("valve-battery-powerSource.yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "",
        model = "E253-KR0B0ZX-HA",
        server_clusters = {0x0000, 0x0006, 0x0500}
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
    "OnOff(on) reporting should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, OnOff.attributes.OnOff:build_test_attr_report(mock_device,
                                                                                                true) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.valve.valve.open())
      }
    }
)


test.register_message_test(
    "OnOff(off) reporting should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, OnOff.attributes.OnOff:build_test_attr_report(mock_device,
                                                                                                false) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.valve.valve.closed())
      }
    }
)

test.register_message_test(
    "Battery percentage report should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, IASZone.attributes.ZoneStatus:build_test_attr_report(mock_device, 0x0008) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.battery.battery(5))
      }
    }
)

test.register_message_test(
    "PowerSource(unknown) reporting should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, Basic.attributes.PowerSource:build_test_attr_report(mock_device,
                                                                                                0x00) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.powerSource.powerSource.unknown())
      }
    }
)

test.register_message_test(
    "PowerSource(mains) reporting should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, Basic.attributes.PowerSource:build_test_attr_report(mock_device,
                                                                                                0x01) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.powerSource.powerSource.mains())
      }
    }
)

test.register_message_test(
    "PowerSource(battery) reporting should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, Basic.attributes.PowerSource:build_test_attr_report(mock_device,
                                                                                                0x03) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.powerSource.powerSource.battery())
      }
    }
)

test.register_message_test(
    "PowerSource(dc) reporting should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, Basic.attributes.PowerSource:build_test_attr_report(mock_device,
                                                                                                0x04) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.powerSource.powerSource.dc())
      }
    }
)

test.register_message_test(
    "Capability(valve) command(open) on should be handled",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_device.id, { capability = "valve", component = "main", command = "open", args = { } } }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_device.id, OnOff.server.commands.On(mock_device) }
      }
    }
)

test.register_message_test(
    "Capability(valve) command(off) on should be handled",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_device.id, { capability = "valve", component = "main", command = "close", args = { } } }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_device.id, OnOff.server.commands.Off(mock_device) }
      }
    }
)

test.register_coroutine_test(
    "doConfigure lifecycle should configure device",
    function ()
      -- test.socket.zigbee:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        Basic.attributes.PowerSource:read(mock_device)
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        OnOff.attributes.OnOff:read(mock_device)
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        IASZone.attributes.ZoneStatus:read(mock_device)
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, Basic.ID)
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        Basic.attributes.PowerSource:configure_reporting(mock_device, 30, 21600)
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, OnOff.ID)
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        OnOff.attributes.OnOff:configure_reporting(mock_device, 0, 600, 0)
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, IASZone.ID)
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        IASZone.attributes.ZoneStatus:configure_reporting(mock_device, 0, 3600, 1)
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
          Basic.attributes.PowerSource:read(mock_device)
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
      {
        channel = "zigbee",
        direction = "send",
        message = {
          mock_device.id,
          IASZone.attributes.ZoneStatus:read(mock_device)
        }
      }
    },
    {
      inner_block_ordering = "relaxed"
    }
)

test.register_message_test(
    "Device added event should refresh device states",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_device.id, "added" },
      },
      {
        channel = "zigbee",
        direction = "send",
        message = {
          mock_device.id,
          Basic.attributes.PowerSource:read(mock_device)
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
      {
        channel = "zigbee",
        direction = "send",
        message = {
          mock_device.id,
          IASZone.attributes.ZoneStatus:read(mock_device)
        }
      }
    },
    {
      inner_block_ordering = "relaxed"
    }
)

test.run_registered_tests()
