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
local t_utils = require "integration_test.utils"
local zw = require "st.zwave"
local zw_test_utils = require "integration_test.zwave_test_utils"
local capabilities = require "st.capabilities"
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version=4 })
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({ version = 2 })
local Meter = (require "st.zwave.CommandClass.Meter")({ version = 3 })

local zooz_switch_endpoints = {
  {
    command_classes = {
      { value = zw.BASIC },
      { value = zw.SWITCH_BINARY },
      { value = zw.METER }
    }
  }
}

local mock_parent = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("metering-switch.yml"),
  zwave_endpoints = zooz_switch_endpoints,
  zwave_manufacturer_id = 0x027A,
  zwave_product_type = 0xA000,
  zwave_product_id = 0xA003
})

local mock_child = test.mock_device.build_test_child_device({
  profile = t_utils.get_profile_definition("metering-switch.yml"),
  parent_device_id = mock_parent.id,
  parent_assigned_child_key = string.format("%02X", 2)
})

local function test_init()
  test.mock_device.add_test_device(mock_parent)
  test.mock_device.add_test_device(mock_child)
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Device should be configured",
  function()
    test.socket.zwave:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({ mock_parent.id, "doConfigure"})
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_parent,
      Configuration:Set({
        parameter_number = 2,
        size = 4,
        configuration_value = 10
      })
    ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_parent,
      Configuration:Set({
        parameter_number = 3,
        size = 4,
        configuration_value = 600
      })
    ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_parent,
      Configuration:Set({
        parameter_number = 4,
        size = 4,
        configuration_value = 600
      })
    ))
    mock_parent:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)

test.register_coroutine_test(
  "Parent device - refresh capability should evoke the correct Z-Wave GETs",
  function()
    test.socket.zwave:__set_channel_ordering('relaxed')
    test.socket.capability:__queue_receive({
      mock_parent.id,
      { capability = "refresh", component = "main", command = "refresh", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_parent,
        SwitchBinary:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={1}
          })
      )
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_parent,
        Meter:Get(
          { scale = Meter.scale.electric_meter.KILOWATT_HOURS },
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={1}
          }
        )
      )
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_parent,
        Meter:Get(
          { scale = Meter.scale.electric_meter.WATTS },
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={1}
          }
        )
      )
     )
  end
)

test.register_coroutine_test(
  "Child device - refresh capability should evoke the correct Z-Wave GETs",
  function()
    test.socket.zwave:__set_channel_ordering('relaxed')
    test.socket.capability:__queue_receive({
      mock_child.id,
      { capability = "refresh", component = "main", command = "refresh", args = {} }
    })

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_parent,
        SwitchBinary:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={2}
          })
      )
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_parent,
        Meter:Get({scale = Meter.scale.electric_meter.KILOWATT_HOURS},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={2}
          }
        )
      )
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_parent,
        Meter:Get(
          { scale = Meter.scale.electric_meter.WATTS },
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={2}
          })
      )
    )
  end
)

test.register_message_test(
  "Parent device - switch capability command on from main should be handled: on",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_parent.id,
        { capability = "switch", command = "on", component = "switch1", args = {} }
      }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_parent,
        SwitchBinary:Set({ target_value=0xFF },
          { encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {1} }
        )
      )
    }
  }
)

test.register_message_test(
  "Parent device - switch capability command off from main should be handled: off",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_parent.id,
        { capability = "switch", command = "off", component = "main", args = {} }
      }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_parent,
        SwitchBinary:Set(
          { target_value=0x00 },
          { encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {1} }
        )
      )
    }
  }
)

test.register_message_test(
  "Child device - switch capability command on from main should be handled: on",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_child.id,
        { capability = "switch", command = "on", component = "switch1", args = {} }
      }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_parent,
        SwitchBinary:Set({ target_value=0xFF },
          { encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {2} }
        )
      )
    }
  }
)

test.register_message_test(
  "Child device - switch capability command off from main should be handled: off",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_child.id,
        { capability = "switch", command = "off", component = "main", args = {} }
      }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_parent,
        SwitchBinary:Set(
          { target_value=0x00 },
          { encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {2} }
        )
      )
    }
  }
)

test.register_message_test(
  "Parent device - Binary report 0xFF should be handled: switch ON",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_parent.id, "init" },
    },
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_parent.id,
        zw_test_utils.zwave_test_build_receive_command(
          SwitchBinary:Report(
            { target_value=0xFF, current_value=0xFF },
            { encap = zw.ENCAP.AUTO, src_channel = 1, dst_channels = {0} }
          )
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_parent:generate_test_message("main", capabilities.switch.switch.on())
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_parent,
        Meter:Get(
          {scale = Meter.scale.electric_meter.WATTS},
          {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {1}}
        )
      )
    }
  }
)

test.register_message_test(
  "Parent device - Binary report Ox00 should be handled: switch OFF",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_parent.id, "init" },
    },
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_parent.id,
        zw_test_utils.zwave_test_build_receive_command(
          SwitchBinary:Report(
            { target_value=0x00, current_value=0x00 },
            { encap = zw.ENCAP.AUTO, src_channel = 1, dst_channels = {0} }
          )
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_parent:generate_test_message("main", capabilities.switch.switch.off())
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_parent,
        Meter:Get(
          { scale = Meter.scale.electric_meter.WATTS },
          { encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {1} }
        )
      )
    }
  }
)

test.register_message_test(
  "Child device - Binary report 0xFF should be handled: switch ON",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_parent.id, "init" },
    },
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
            SwitchBinary:Report(
              { target_value=0xFF, current_value=0xFF },
              { encap = zw.ENCAP.AUTO, src_channel = 2, dst_channels = {0} }
            )
          )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_child:generate_test_message("main", capabilities.switch.switch.on())
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_parent,
        Meter:Get(
          {scale = Meter.scale.electric_meter.WATTS},
          {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {2}}
        )
      )
    }
  }
)

test.register_message_test(
  "Child device - Binary report Ox00 should be handled: switch OFF",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_parent.id, "init" },
    },
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_parent.id,
        zw_test_utils.zwave_test_build_receive_command(
          SwitchBinary:Report(
            { target_value=0x00, current_value=0x00 },
            { encap = zw.ENCAP.AUTO, src_channel = 2, dst_channels = {0} }
          )
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_child:generate_test_message("main", capabilities.switch.switch.off())
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_parent,
        Meter:Get(
          { scale = Meter.scale.electric_meter.WATTS },
          { encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {2} }
        )
      )
    }
  }
)

test.register_message_test(
  "Parent device - Energy meter report from endpoint 1 should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_parent.id, zw_test_utils.zwave_test_build_receive_command(
        Meter:Report(
          { scale = Meter.scale.electric_meter.KILOWATT_HOURS, meter_value = 5},
          { encap = zw.ENCAP.AUTO, src_channel = 1, dst_channels = {0} }
        )
      )}
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_parent:generate_test_message("main", capabilities.energyMeter.energy({ value = 5, unit = "kWh" }))
    }
  }
)

test.register_message_test(
  "Child device - Energy meter report from endpoint 2 should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_parent.id, zw_test_utils.zwave_test_build_receive_command(
        Meter:Report(
          { scale = Meter.scale.electric_meter.KILOWATT_HOURS, meter_value = 5},
          { encap = zw.ENCAP.AUTO, src_channel = 2, dst_channels = {0} }
        )
      )}
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_child:generate_test_message("main", capabilities.energyMeter.energy({ value = 5, unit = "kWh" }))
    }
  }
)

test.register_message_test(
  "Parent device - Power meter report from endpoint 1 should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_parent.id, zw_test_utils.zwave_test_build_receive_command(
        Meter:Report(
          { scale = Meter.scale.electric_meter.WATTS, meter_value = 89 },
          { encap = zw.ENCAP.AUTO, src_channel = 1, dst_channels = {0} }
        )
      )}
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_parent:generate_test_message("main", capabilities.powerMeter.power({ value = 89, unit = "W" }))
    }
  }
)

test.register_message_test(
  "Child device - Power meter report from endpoint 2 should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_parent.id, zw_test_utils.zwave_test_build_receive_command(
        Meter:Report(
          { scale = Meter.scale.electric_meter.WATTS, meter_value = 89 },
          { encap = zw.ENCAP.AUTO, src_channel = 1, dst_channels = {0} }
        )
      )}
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_parent:generate_test_message("main", capabilities.powerMeter.power({ value = 89, unit = "W" }))
    }
  }
)

test.run_registered_tests()
