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
local Basic = clusters.Basic
local OnOff = clusters.OnOff
local PowerConfiguration = clusters.PowerConfiguration
local capabilities = require "st.capabilities"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils = require "integration_test.utils"

-- 父设备（端点1）：valve + battery + powerSource + firmwareUpdate + refresh
local mock_device = test.mock_device.build_test_zigbee_device(
  { profile = t_utils.get_profile_definition("sonoff-irrigation-2.yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "SONOFF",
        model = "SWV-ZF2E",
        server_clusters = { 0x0000, 0x0001, 0x0006, 0x0404, 0xFC11 }
      },
      [2] = {
        id = 2,
        manufacturer = "SONOFF",
        model = "SWV-ZF2E",
        server_clusters = { 0x0006 }
      }
    }
  }
)

-- 子设备（端点2）：只有 valve + refresh，无电池/电源
local mock_child = test.mock_device.build_test_child_device({
  profile = t_utils.get_profile_definition("valve.yml"),
  device_network_id = string.format("%04X:%02X", mock_device:get_short_address(), 2),
  parent_device_id = mock_device.id,
  parent_assigned_child_key = string.format("%02X", 2)
})

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device)
  test.mock_device.add_test_device(mock_child)
  zigbee_test_utils.init_noop_health_check_timer()
end

test.set_test_init_function(test_init)

-- ============================================================================
-- 父设备（端点1）测试：OnOff 属性上报 → valve 事件
-- ============================================================================

test.register_message_test(
    "OnOff(on) should set valve to open",
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
    "OnOff(off) should set valve to closed",
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

-- ============================================================================
-- 子设备（端点2）测试：OnOff 属性上报 → 子设备 valve 事件
-- ============================================================================

test.register_message_test(
    "OnOff(on) from endpoint 2 should set child valve to open",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_child.id, OnOff.attributes.OnOff:build_test_attr_report(mock_device,
                                                                                  true):from_endpoint(0x02) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.valve.valve.open())
      }
    }
)

test.register_message_test(
    "OnOff(off) from endpoint 2 should set child valve to closed",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_child.id, OnOff.attributes.OnOff:build_test_attr_report(mock_device,
                                                                                  false):from_endpoint(0x02) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.valve.valve.closed())
      }
    }
)

-- ============================================================================
-- 父设备电池/电源测试
-- ============================================================================

-- Battery percentage
test.register_message_test(
    "Battery percentage report should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, PowerConfiguration.attributes.BatteryPercentageRemaining:build_test_attr_report(mock_device, 55) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.battery.battery(28))
      }
    }
)

-- PowerSource(battery)
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

-- ============================================================================
-- 父设备（端点1）valve 命令测试
-- ============================================================================

test.register_message_test(
    "Capability(valve) command(open) should send OnOff.On and read OnOff",
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
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_device.id, OnOff.attributes.OnOff:read(mock_device) }
      }
    }
)

test.register_message_test(
    "Capability(valve) command(close) should send OnOff.Off and read OnOff",
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
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_device.id, OnOff.attributes.OnOff:read(mock_device) }
      }
    }
)

-- ============================================================================
-- 子设备（端点2）valve 命令测试
-- ============================================================================

test.register_message_test(
    "Child valve command(open) should send OnOff.On to endpoint 2",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_child.id, { capability = "valve", component = "main", command = "open", args = { } } }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_device.id, OnOff.server.commands.On(mock_device):to_endpoint(0x02) }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_device.id, OnOff.attributes.OnOff:read(mock_device):to_endpoint(0x02) }
      }
    }
)

test.register_message_test(
    "Child valve command(close) should send OnOff.Off to endpoint 2",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_child.id, { capability = "valve", component = "main", command = "close", args = { } } }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_device.id, OnOff.server.commands.Off(mock_device):to_endpoint(0x02) }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_device.id, OnOff.attributes.OnOff:read(mock_device):to_endpoint(0x02) }
      }
    }
)

-- ============================================================================
-- doConfigure 生命周期测试
-- ============================================================================

test.register_coroutine_test(
    "doConfigure lifecycle should configure device",
    function ()
      test.socket.zigbee:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device)
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        OnOff.attributes.OnOff:read(mock_device)
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        Basic.attributes.PowerSource:read(mock_device)
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, PowerConfiguration.ID)
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        PowerConfiguration.attributes.BatteryPercentageRemaining:configure_reporting(mock_device, 30, 21600, 1)
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
        zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, Basic.ID)
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        Basic.attributes.PowerSource:configure_reporting(mock_device, 5, 600)
      })

      mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    end
)

-- ============================================================================
-- Refresh 测试
-- ============================================================================

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
        message = { mock_device.id, Basic.attributes.PowerSource:read(mock_device) }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_device.id, OnOff.attributes.OnOff:read(mock_device) }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_device.id, PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device) }
      }
    },
    {
      inner_block_ordering = "relaxed"
    }
)

-- ============================================================================
-- Device added 生命周期测试（验证子设备创建 + refresh）
-- ============================================================================

test.register_coroutine_test(
    "added lifecycle should create child device and refresh parent states",
    function()
      test.socket.zigbee:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })

      -- 验证子设备创建
      mock_device:expect_device_create({
        type = "EDGE_CHILD",
        label = string.format("%s 2", mock_device.label),
        profile = "valve",
        parent_device_id = mock_device.id,
        parent_assigned_child_key = "02"
      })

      -- 验证 refresh 读取父设备属性
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
        PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device)
      })
    end
)

test.run_registered_tests()
