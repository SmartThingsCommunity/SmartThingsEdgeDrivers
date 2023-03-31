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
local Basic = (require "st.zwave.CommandClass.Basic")({version=1})
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({version=2})
local t_utils = require "integration_test.utils"

-- supported comand classes
local sensor_endpoints = {
  {command_classes = {
    {value = zw.BASIC},
    {value = zw.SWITCH_BINARY},
  }},
  {command_classes = {
    {value = zw.BASIC},
    {value = zw.SWITCH_BINARY},
  }},
  {command_classes = {
    {value = zw.BASIC},
    {value = zw.SWITCH_BINARY},
  }},
  {command_classes = {
    {value = zw.BASIC},
    {value = zw.SWITCH_BINARY},
  }}
}

local mock_device = test.mock_device.build_test_zwave_device({
    profile = t_utils.get_profile_definition("ecolink-wireless-siren.yml"),
    zwave_endpoints = sensor_endpoints,
    zwave_manufacturer_id = 0x014A,
    zwave_product_type = 0x0005,
    zwave_product_id = 0x000A
})

local function test_init()
  test.mock_device.add_test_device(mock_device)
end

test.set_test_init_function(test_init)

test.register_message_test(
  "Basic set 0x00 should be handled as alarm off, switch off in main component",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_device.id, "init" }
    },
    {
      channel = "zwave",
      direction = "receive",
      message =
      {
        mock_device.id,
        zw_test_utils.zwave_test_build_receive_command(Basic:Set({ value = 0x00 }))
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.alarm.alarm.off())
    }
  }
)

test.register_message_test(
  "Basic set 0x00 should be handled as alarm off, switch off in siren1 component",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_device.id, "init" }
    },
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
          zw_test_utils.zwave_test_build_receive_command(
            Basic:Set(
            {
              value = 0x00
            },
            {
              encap = zw.ENCAP.AUTO,
              src_channel = 2,
              dst_channels = { 0 }
            }
          )
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("siren1",  capabilities.alarm.alarm.off())
    }
  }
)

test.register_message_test(
  "Basic set 0x00 should be handled as alarm off, swtich off in siren2 component",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_device.id, "init" }
    },
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
          zw_test_utils.zwave_test_build_receive_command(
            Basic:Set(
            {
              value = 0xFF
            },
            {
              encap = zw.ENCAP.AUTO,
              src_channel = 3,
              dst_channels = { 0 }
            }
          )
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("siren2",  capabilities.alarm.alarm.both())
    }
  }
)

test.register_message_test(
  "Basic set 0xFF should be handled as alarm on, switch both in main component",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_device.id, "init" }
    },
    {
      channel = "zwave",
      direction = "receive",
      message =
      {
        mock_device.id,
        zw_test_utils.zwave_test_build_receive_command(Basic:Set({ value = 0xFF }))
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.alarm.alarm.both())
    }
  }
)

test.register_message_test(
  "Basic set 0xFF should be handled as alarm on, switch both in siren1 component",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_device.id, "init" }
    },
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
          zw_test_utils.zwave_test_build_receive_command(
            Basic:Set(
            {
              value = 0xFF
            },
            {
              encap = zw.ENCAP.AUTO,
              src_channel = 2,
              dst_channels = { 0 }
            }
          )
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("siren1",  capabilities.alarm.alarm.both())
    }
  }
)

test.register_message_test(
  "Basic set 0xFF should be handled as alarm on, switch both in siren2 component",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_device.id, "init" }
    },
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
          zw_test_utils.zwave_test_build_receive_command(
            Basic:Set(
            {
              value = 0xFF
            },
            {
              encap = zw.ENCAP.AUTO,
              src_channel = 3,
              dst_channels = { 0 }
            }
          )
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("siren2",  capabilities.alarm.alarm.both())
    }
  }
)

test.register_coroutine_test(
  "Refresh should generate the correct commands",
  function()
    test.socket.zwave:__set_channel_ordering("relaxed")
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "refresh", command = "refresh", component = "main", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchBinary:Get({}, {dst_channels={1}})
      )
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchBinary:Get({}, { encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = { 2 } })
      )
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchBinary:Get({}, { encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = { 3 } })
      )
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchBinary:Get({}, { encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = { 4 } })
      )
    )
  end
)

test.register_coroutine_test(
  "Receiving the both command from main component should generate the correct commands",
  function()
    test.socket.zwave:__set_channel_ordering("relaxed")
    test.socket.capability:__queue_receive({
      mock_device.id,
      {capability = "alarm", command = "both", component = "main", args = {}}
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Basic:Set({value = 0xFF}, {dst_channels = {1}})
      )
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchBinary:Get({}, {dst_channels = {1}})
      )
    )

  end
)
test.register_coroutine_test(
  "Receiving the both command from siren1 component should generate the correct commands including delayed commands",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.socket.capability:__queue_receive({
      mock_device.id,
      {capability = "alarm", command = "both", component = "siren1", args = {}}
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Basic:Set({value = 0xFF}, {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {2}})
      )
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchBinary:Get({}, {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {2}})
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(2)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchBinary:Get({}, {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {2}})
      )
    )

  end
)

test.register_coroutine_test(
  "Receiving the both command from siren2 component should generate the correct commands",
  function()
    test.socket.zwave:__set_channel_ordering("relaxed")
    test.socket.capability:__queue_receive({
      mock_device.id,
      {capability = "alarm", command = "both", component = "siren2", args = {}}
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Basic:Set({value = 0xFF}, {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {3}})
      )
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchBinary:Get({}, {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {3}})
      )
    )

  end
)

test.register_coroutine_test(
  "Receiving the both command from siren3 component should generate the correct commands",
  function()
    test.socket.zwave:__set_channel_ordering("relaxed")
    test.socket.capability:__queue_receive({
      mock_device.id,
      {capability = "alarm", command = "both", component = "siren3", args = {}}
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Basic:Set({value = 0xFF}, {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {4}})
      )
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchBinary:Get({}, {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {4}})
      )
    )
  end
)


test.register_coroutine_test(
  "Receiving the off command from main should generate the correct commands",
  function()
    test.socket.zwave:__set_channel_ordering("relaxed")
    test.socket.capability:__queue_receive({
      mock_device.id,
      {capability = "alarm", command = "off", component = "main", args = {}}
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Basic:Set({value = 0}, {dst_channels = {1}})
      )
    )
    test.socket.zwave:__expect_send(
    zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchBinary:Get({}, {dst_channels = {1}})
      )
    )
  end
)
test.register_coroutine_test(
  "Receiving the off command from siren1 should generate the correct commands",
  function()
    test.socket.zwave:__set_channel_ordering("relaxed")
    test.socket.capability:__queue_receive({
      mock_device.id,
      {capability = "alarm", command = "off", component = "siren1", args = {}}
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Basic:Set({value = 0}, {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {2}})
      )
    )
    test.socket.zwave:__expect_send(
    zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchBinary:Get({}, {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {2}})
      )
    )
  end
)
test.register_coroutine_test(
  "Receiving the off command from siren2 should generate the correct commands",
  function()
    test.socket.zwave:__set_channel_ordering("relaxed")
    test.socket.capability:__queue_receive({
      mock_device.id,
      {capability = "alarm", command = "off", component = "siren2", args = {}}
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Basic:Set({value = 0}, {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {3}})
      )
    )
    test.socket.zwave:__expect_send(
    zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchBinary:Get({}, {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {3}})
      )
    )
  end
)
test.register_coroutine_test(
  "Receiving the off command from siren3 should generate the correct commands",
  function()
    test.socket.zwave:__set_channel_ordering("relaxed")
    test.socket.capability:__queue_receive({
      mock_device.id,
      {capability = "alarm", command = "off", component = "siren3", args = {}}
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Basic:Set({value = 0}, {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {4}})
      )
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchBinary:Get({}, {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {4}})
      )
    )
  end
)

test.run_registered_tests()
