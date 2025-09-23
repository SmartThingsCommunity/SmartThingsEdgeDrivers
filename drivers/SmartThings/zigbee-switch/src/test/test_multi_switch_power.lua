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
local OnOff = clusters.OnOff
local ElectricalMeasurement = clusters.ElectricalMeasurement
local capabilities = require "st.capabilities"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils = require "integration_test.utils"
local messages = require "st.zigbee.messages"
local config_reporting_response = require "st.zigbee.zcl.global_commands.configure_reporting_response"
local zb_const = require "st.zigbee.constants"
local zcl_messages = require "st.zigbee.zcl"
local data_types = require "st.zigbee.data_types"
local Status = require "st.zigbee.generated.types.ZclStatus"

local profile = t_utils.get_profile_definition("switch-power-smartplug.yml")

local mock_base_device = test.mock_device.build_test_zigbee_device(
    {
      label = "AURORA Outlet 1",
      profile = profile,
      zigbee_endpoints = {
        [1] = {
          id = 1,
          manufacturer = "Aurora",
          model = "DoubleSocket50AU",
          server_clusters = { 0x0019, 0x0006, 0x0B04 }
        }
      },
      fingerprinted_endpoint_id = 0x01
    }
)

local mock_parent_device = test.mock_device.build_test_zigbee_device(
    {
      profile = profile,
      zigbee_endpoints = {
        [1] = {
          id = 1,
          manufacturer = "Aurora",
          model = "DoubleSocket50AU",
          server_clusters = { 0x0019, 0x0006, 0x0B04 }
        }
      },
      fingerprinted_endpoint_id = 0x01
    }
)

local mock_child_device = test.mock_device.build_test_child_device({
  profile = profile,
  device_network_id = string.format("%04X:%02X", mock_parent_device:get_short_address(), 2),
  parent_device_id = mock_parent_device.id,
  parent_assigned_child_key = string.format("%02X", 2)
})

zigbee_test_utils.prepare_zigbee_env_info()

local function test_init()
  mock_base_device:set_field("_configuration_version", 1, {persist = true})
  test.mock_device.add_test_device(mock_base_device)
  mock_parent_device:set_field("_configuration_version", 1, {persist = true})
  test.mock_device.add_test_device(mock_parent_device)
  mock_child_device:set_field("_configuration_version", 1, {persist = true})
  test.mock_device.add_test_device(mock_child_device)end

test.set_test_init_function(test_init)

local function build_config_response_msg(device, cluster, status)
  local addr_header = messages.AddressHeader(
    device:get_short_address(),
    device.fingerprinted_endpoint_id,
    zb_const.HUB.ADDR,
    zb_const.HUB.ENDPOINT,
    zb_const.HA_PROFILE_ID,
    cluster
  )
  local config_response_body = config_reporting_response.ConfigureReportingResponse({}, status)
  local zcl_header = zcl_messages.ZclHeader({
    cmd = data_types.ZCLCommandId(config_response_body.ID)
  })
  local message_body = zcl_messages.ZclMessageBody({
    zcl_header = zcl_header,
    zcl_body = config_response_body
  })
  return messages.ZigbeeMessageRx({
    address_header = addr_header,
    body = message_body
  })
end

test.register_coroutine_test(
    "configuration version below 1",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(5*60, "oneshot")
      test.mock_device.add_test_device(mock_parent_device)
      test.mock_device.add_test_device(mock_child_device)
      assert(mock_parent_device:get_field("_configuration_version") == nil)
      test.socket.device_lifecycle:__queue_receive({ mock_parent_device.id, "init" })
      assert(mock_child_device:get_field("_configuration_version") == nil)
      test.socket.device_lifecycle:__queue_receive({ mock_child_device.id, "init" })
      test.wait_for_events()
      test.socket.zigbee:__set_channel_ordering("relaxed")
      test.socket.zigbee:__expect_send({mock_parent_device.id, ElectricalMeasurement.attributes.ActivePower:configure_reporting(mock_parent_device, 5, 600, 5)})
      test.socket.zigbee:__expect_send({mock_parent_device.id, ElectricalMeasurement.attributes.ActivePower:configure_reporting(mock_parent_device, 5, 600, 5):to_endpoint(0x02)})
      test.mock_time.advance_time(50 * 60  + 1)
      test.wait_for_events()
      test.socket.zigbee:__queue_receive({mock_parent_device.id, build_config_response_msg(mock_parent_device, ElectricalMeasurement.ID, Status.SUCCESS)})
      test.socket.zigbee:__queue_receive({mock_parent_device.id, build_config_response_msg(mock_parent_device, ElectricalMeasurement.ID, Status.SUCCESS):from_endpoint(0x02)})
      test.wait_for_events()
      assert(mock_child_device:get_field("_configuration_version") == 1, "config version for child should be 1")
      assert(mock_parent_device:get_field("_configuration_version") == 1, "config version for parent should be 1")
    end,
    {
      test_init = function()
        -- no op to avoid auto device add and immediate init event on driver startup
      end
    }
)

test.register_coroutine_test(
    "configuration version at 1 doesn't reconfigure",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(5*60, "oneshot")
      test.mock_device.add_test_device(mock_parent_device)
      test.mock_device.add_test_device(mock_child_device)
      mock_child_device:set_field("_configuration_version", 1, {persist = true})
      mock_parent_device:set_field("_configuration_version", 1, {persist = true})
      assert(mock_parent_device:get_field("_configuration_version") == 1)
      assert(mock_child_device:get_field("_configuration_version") == 1)
      test.socket.device_lifecycle:__queue_receive({ mock_parent_device.id, "init" })
      test.socket.device_lifecycle:__queue_receive({ mock_child_device.id, "init" })
      test.wait_for_events()
      assert(mock_child_device:get_field("_configuration_version") == 1)
      assert(mock_parent_device:get_field("_configuration_version") == 1)
    end,
    {
      test_init = function()
        -- no op to avoid auto device add and immediate init event on driver startup
      end
    }
)

test.register_message_test(
    "Refresh on parent device should read all necessary attributes",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_parent_device.id, { capability = "refresh", component = "main", command = "refresh", args = {} } }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = {
          mock_parent_device.id,
          OnOff.attributes.OnOff:read(mock_parent_device):to_endpoint(0x01)
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = {
          mock_parent_device.id,
          ElectricalMeasurement.attributes.ActivePower:read(mock_parent_device):to_endpoint(0x01)
        }
      }
    },
    {
      inner_block_ordering = "relaxed"
    }
)

test.register_message_test(
    "Refresh on child device should read all necessary attributes",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_child_device.id, { capability = "refresh", component = "main", command = "refresh", args = {} } }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = {
          mock_parent_device.id,
          OnOff.attributes.OnOff:read(mock_parent_device):to_endpoint(0x02)
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = {
          mock_parent_device.id,
          ElectricalMeasurement.attributes.ActivePower:read(mock_parent_device):to_endpoint(0x02)
        }
      }
    },
    {
      inner_block_ordering = "relaxed"
    }
)

test.register_message_test(
    "Reported on off status should be handled: on child device",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_child_device.id, OnOff.attributes.OnOff:build_test_attr_report(mock_parent_device,
            true)                              :from_endpoint(0x02) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_device:generate_test_message("main", capabilities.switch.switch.on())
      },
      {
        channel = "devices",
        direction = "send",
        message = {
          "register_native_capability_attr_handler",
          { device_uuid = mock_child_device.id, capability_id = "switch", capability_attr_id = "switch" }
        }
      },
    }
)

test.register_message_test(
    "Reported on off status should be handled: on parent device",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_parent_device.id, OnOff.attributes.OnOff:build_test_attr_report(mock_parent_device,
            true)                               :from_endpoint(0x01) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent_device:generate_test_message("main", capabilities.switch.switch.on())
      },
      {
        channel = "devices",
        direction = "send",
        message = {
          "register_native_capability_attr_handler",
          { device_uuid = mock_parent_device.id, capability_id = "switch", capability_attr_id = "switch" }
        }
      },
    }
)

test.register_message_test(
    "Reported on off status should be handled: off child device",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_child_device.id, OnOff.attributes.OnOff:build_test_attr_report(mock_parent_device,
            false)                             :from_endpoint(0x02) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_device:generate_test_message("main", capabilities.switch.switch.off())
      },
      {
        channel = "devices",
        direction = "send",
        message = {
          "register_native_capability_attr_handler",
          { device_uuid = mock_child_device.id, capability_id = "switch", capability_attr_id = "switch" }
        }
      },
    }
)

test.register_message_test(
    "Reported on off status should be handled: off parent device",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_parent_device.id, OnOff.attributes.OnOff:build_test_attr_report(mock_parent_device,
            false)                              :from_endpoint(0x01) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent_device:generate_test_message("main", capabilities.switch.switch.off())
      },
      {
        channel = "devices",
        direction = "send",
        message = {
          "register_native_capability_attr_handler",
          { device_uuid = mock_parent_device.id, capability_id = "switch", capability_attr_id = "switch" }
        }
      },
    }
)

test.register_message_test(
    "ActivePower Report should be handled: Sensor value is in W, capability attribute value is in W, parent device",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = {
          mock_parent_device.id,
          ElectricalMeasurement.attributes.ActivePower:build_test_attr_report(mock_parent_device, 27):from_endpoint(0x01)
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent_device:generate_test_message("main", capabilities.powerMeter.power({ value = 27.0, unit = "W" }))
      },
      {
        channel = "devices",
        direction = "send",
        message = {
          "register_native_capability_attr_handler",
          { device_uuid = mock_parent_device.id, capability_id = "powerMeter", capability_attr_id = "power" }
        }
      }
    }
)

test.register_message_test(
    "ActivePower Report should be handled: Sensor value is in W, capability attribute value is in W, child device",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = {
          mock_parent_device.id,
          ElectricalMeasurement.attributes.ActivePower:build_test_attr_report(mock_parent_device, 27):from_endpoint(0x02)
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_device:generate_test_message("main", capabilities.powerMeter.power({ value = 27.0, unit = "W" }))
      },
      {
        channel = "devices",
        direction = "send",
        message = {
          "register_native_capability_attr_handler",
          { device_uuid = mock_parent_device.id, capability_id = "powerMeter", capability_attr_id = "power" }
        }
      }
    }
)

test.register_message_test(
    "Capability command switch on child should be handled",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_child_device.id, { capability = "switch", component = "main", command = "on", args = { } } }
      },
      {
        channel = "devices",
        direction = "send",
        message = {
          "register_native_capability_cmd_handler",
          { device_uuid = mock_child_device.id, capability_id = "switch", capability_cmd_id = "on" }
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_parent_device.id, OnOff.server.commands.On(mock_parent_device):to_endpoint(0x02) }
      }
    }
)

test.register_message_test(
    "Capability command switch on parent should be handled",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_parent_device.id, { capability = "switch", component = "main", command = "on", args = { } } }
      },
      {
        channel = "devices",
        direction = "send",
        message = {
          "register_native_capability_cmd_handler",
          { device_uuid = mock_parent_device.id, capability_id = "switch", capability_cmd_id = "on" }
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_parent_device.id, OnOff.server.commands.On(mock_parent_device):to_endpoint(0x01) }
      }
    }
)

test.register_message_test(
    "Capability command switch off child should be handled",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_child_device.id, { capability = "switch", component = "main", command = "off", args = { } } }
      },
      {
        channel = "devices",
        direction = "send",
        message = {
          "register_native_capability_cmd_handler",
          { device_uuid = mock_child_device.id, capability_id = "switch", capability_cmd_id = "off" }
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_parent_device.id, OnOff.server.commands.Off(mock_parent_device):to_endpoint(0x02) }
      }
    }
)

test.register_message_test(
    "Capability command switch off parent should be handled",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_parent_device.id, { capability = "switch", component = "main", command = "off", args = { } } }
      },
      {
        channel = "devices",
        direction = "send",
        message = {
          "register_native_capability_cmd_handler",
          { device_uuid = mock_parent_device.id, capability_id = "switch", capability_cmd_id = "off" }
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_parent_device.id, OnOff.server.commands.Off(mock_parent_device):to_endpoint(0x01) }
      }
    }
)

test.register_coroutine_test(
    "added lifecycle event should create children in parent device",
    function()
      test.socket.zigbee:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle:__queue_receive({ mock_base_device.id, "added" })
      mock_base_device:expect_device_create({
        type = "EDGE_CHILD",
        label = "AURORA Outlet 2",
        profile = "switch-power-smartplug",
        parent_device_id = mock_base_device.id,
        parent_assigned_child_key = "02"
      })
      test.socket.zigbee:__expect_send({
        mock_base_device.id,
        OnOff.attributes.OnOff:read(mock_base_device):to_endpoint(0x01)
      })
      test.socket.zigbee:__expect_send({
        mock_base_device.id,
        ElectricalMeasurement.attributes.ActivePower:read(mock_base_device):to_endpoint(0x01)
      })
    end
)

test.register_coroutine_test(
    "added lifecycle event should refresh child device",
    function()
      test.socket.zigbee:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle:__queue_receive({ mock_child_device.id, "added" })
      test.socket.zigbee:__expect_send({
        mock_parent_device.id,
        OnOff.attributes.OnOff:read(mock_child_device):to_endpoint(0x02)
      })
      test.socket.zigbee:__expect_send({
        mock_parent_device.id,
        ElectricalMeasurement.attributes.ActivePower:read(mock_child_device):to_endpoint(0x02)
      })
    end
)

test.run_registered_tests()
