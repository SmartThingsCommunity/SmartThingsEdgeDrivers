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

local test = require "integration_test"
local capabilities = require "st.capabilities"
local zw = require "st.zwave"
local zw_test_utils = require "integration_test.zwave_test_utils"
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({version=2})
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version=4 })
local t_utils = require "integration_test.utils"

local WYFY_MANUFACTURER_ID = 0x015F
local WYFY_PRODUCT_TYPE = 0x3121
local WYFY_PRODUCT_ID = 0x5102

local profile = t_utils.get_profile_definition("switch-binary.yml")

local WYFY_multicomponent_endpoints = {
  { -- ep 1
    command_classes = {
      { value = zw.SWITCH_BINARY }
    }
  },
  { -- ep 2
    command_classes = {
      { value = zw.SWITCH_BINARY }
    }
  }
}

local mock_parent_device = test.mock_device.build_test_zwave_device({
  profile = profile,
  zwave_endpoints = WYFY_multicomponent_endpoints,
  zwave_manufacturer_id = WYFY_MANUFACTURER_ID,
  zwave_product_type = WYFY_PRODUCT_TYPE,
  zwave_product_id = WYFY_PRODUCT_ID
})

local mock_base_device = test.mock_device.build_test_zwave_device({
  label = "WYFY Switch 1",
  profile = profile,
  zwave_endpoints = WYFY_multicomponent_endpoints,
  zwave_manufacturer_id = WYFY_MANUFACTURER_ID,
  zwave_product_type = WYFY_PRODUCT_TYPE,
  zwave_product_id = WYFY_PRODUCT_ID
})

local mock_child_device = test.mock_device.build_test_child_device({
  profile = profile,
  parent_device_id = mock_parent_device.id,
  parent_assigned_child_key = string.format("%02X", 2)
})

local function test_init()
  test.mock_device.add_test_device(mock_parent_device)
  test.mock_device.add_test_device(mock_child_device)
  test.mock_device.add_test_device(mock_base_device)
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "doConfigure lifecycle event should generate proper configuration commands",
  function()
    test.socket.zwave:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({ mock_parent_device.id, "doConfigure" })
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_parent_device,
      Configuration:Set({parameter_number = 2, size = 1, configuration_value = 1})
    ))
    mock_parent_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)

test.register_message_test(
  "Switch on/off capability command on from parent device should be handled",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_parent_device.id,
        { capability = "switch", command = "on", component = "main", args = {} }
      }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_parent_device,
        SwitchBinary:Set(
          { target_value = SwitchBinary.value.ON_ENABLE },
          { encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = { 1 } }
        )
      )
    }
  }
)

test.register_message_test(
  "Switch on/off capability command on from child device should be handled",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_child_device.id,
        { capability = "switch", command = "on", component = "main", args = {} }
      }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_parent_device,
        SwitchBinary:Set(
          { target_value = SwitchBinary.value.ON_ENABLE },
          { encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = { 2 } }
        )
      )
    }
  }
)

test.register_message_test(
  "Switch on/off capability command from parent device should be handled: off",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_parent_device.id,
        { capability = "switch", command = "off", component = "main", args = {} }
      }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_parent_device,
        SwitchBinary:Set(
          { target_value = SwitchBinary.value.OFF_DISABLE },
          { encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = { 1 } }
        )
      )
    }
  }
)

test.register_message_test(
  "Switch on/off capability command from child device should be handled: off",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_child_device.id,
        { capability = "switch", command = "off", component = "main", args = {} }
      }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_parent_device,
        SwitchBinary:Set(
          { target_value = SwitchBinary.value.OFF_DISABLE },
          { encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = { 2 } }
        )
      )
    }
  }
)

test.register_message_test(
  "Binary switch on/off report from parent device should be handled: on",
  {
    {
    channel = "device_lifecycle",
    direction = "receive",
    message = { mock_parent_device.id, "init" },
    },
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_parent_device.id,
        zw_test_utils.zwave_test_build_receive_command(
          SwitchBinary:Report(
            { target_value = SwitchBinary.value.ON_ENABLE,
              current_value = SwitchBinary.value.ON_ENABLE},
            { encap = zw.ENCAP.AUTO, src_channel = 1, dst_channels = { 0 } }
          )
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_parent_device:generate_test_message("main", capabilities.switch.switch.on())
    }
  }
)

test.register_message_test(
  "Binary switch on/off report from child device should be handled: on",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_child_device.id, "init" },
    },
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_child_device.id,
        zw_test_utils.zwave_test_build_receive_command(
          SwitchBinary:Report(
            { target_value = SwitchBinary.value.ON_ENABLE,
              current_value = SwitchBinary.value.ON_ENABLE},
            { encap = zw.ENCAP.AUTO, src_channel = 2, dst_channels = { 0 } }
          )
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_child_device:generate_test_message("main", capabilities.switch.switch.on())
    }
  }
)

test.register_coroutine_test(
  "Switch capability off commands from parent device should evoke the correct Z-Wave SETs and GETs",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_parent_device.id,
      { capability = "switch", command = "off", component = "main", args = {} }
    })

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_parent_device,
        SwitchBinary:Set(
          { target_value = SwitchBinary.value.OFF_DISABLE },
          { encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = { 1 } }
        )
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_parent_device,
        SwitchBinary:Get({},
          { encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = { 1 } }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Switch capability off commands from child device should evoke the correct Z-Wave SETs and GETs",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_child_device.id,
      { capability = "switch", command = "off", component = "main", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_parent_device,
        SwitchBinary:Set(
          { target_value = SwitchBinary.value.OFF_DISABLE },
          { encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = { 2 } }
        )
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_parent_device,
        SwitchBinary:Get({},
          { encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = { 2 } }
        )
      )
    )
  end
)

local function prepare_metadata(device, endpoint, profile)
  local device_name_without_number = string.sub(device.label, 0,-2)
  local name = string.format("%s%d", device_name_without_number, endpoint)
  return {
    type = "EDGE_CHILD",
    label = name,
    profile = profile,
    parent_device_id = device.id,
    parent_assigned_child_key = string.format("%02X", endpoint)
  }
end

test.register_coroutine_test(
    "added lifecycle event should create children in parent device",
    function()
      test.socket.zwave:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle:__queue_receive({ mock_base_device.id, "added" })
      mock_base_device:expect_device_create(
          prepare_metadata(mock_base_device, 2, "switch-binary")
      )
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_base_device,
              SwitchBinary:Get({},
                  { encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = { 1 } }
              )
          )
      )
    end
)

test.register_coroutine_test(
    "added lifecycle event for child should refresh device only",
    function()
      test.socket.zwave:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle:__queue_receive({ mock_child_device.id, "added" })
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_parent_device,
              SwitchBinary:Get({},
                  { encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = { 2 } }
              )
          )
      )
    end
)

test.run_registered_tests()
