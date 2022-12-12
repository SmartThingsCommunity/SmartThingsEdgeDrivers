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
local Basic = (require "st.zwave.CommandClass.Basic")({ version = 1 })
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version = 1 })
local Meter = (require "st.zwave.CommandClass.Meter")({ version = 3 })
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({ version = 2 })
local t_utils = require "integration_test.utils"

local multi_switch_endpoints = {
  {
    command_classes = {
      {value = zw.BASIC},
      {value = zw.METER},
      {value = zw.SWITCH_BINARY}
    }
  },
  {
    command_classes = {
      {value = zw.BASIC},
      {value = zw.METER},
      {value = zw.SWITCH_BINARY}
    }
  },
  {
    command_classes = {
      {value = zw.BASIC},
      {value = zw.METER},
      {value = zw.SWITCH_BINARY}
    }
  },
  {
    command_classes = {
      {value = zw.BASIC},
      {value = zw.METER},
      {value = zw.SWITCH_BINARY}
    }
  },
  {
    command_classes = {
      {value = zw.BASIC},
      {value = zw.METER},
      {value = zw.SWITCH_BINARY}
    }
  }
}

local mock_metering_switch = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("metering-switch-5.yml"),
  zwave_endpoints = multi_switch_endpoints,
  zwave_manufacturer_id = 0x0086,
  zwave_product_type = 0x0003,
  zwave_product_id = 0x000B
})

local function test_init()
  test.mock_device.add_test_device(mock_metering_switch)
end
test.set_test_init_function(test_init)

test.register_message_test(
  "Basic Report 0x00 to channel 0 received, make all component to off and check the metering value",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_metering_switch.id, "init" }
    },
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_metering_switch.id,
        zw_test_utils.zwave_test_build_receive_command(
          Basic:Report(
            {
              value = 0x00
            },
            {
              encap = zw.ENCAP.AUTO,
              src_channel = 0,
              dst_channels = {0}
            }
          )
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_metering_switch:generate_test_message("main", capabilities.switch.switch.off())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_metering_switch:generate_test_message("switch1", capabilities.switch.switch.off())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_metering_switch:generate_test_message("switch2", capabilities.switch.switch.off())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_metering_switch:generate_test_message("switch3", capabilities.switch.switch.off())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_metering_switch:generate_test_message("switch4", capabilities.switch.switch.off())
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_metering_switch,
        Meter:Get({scale = Meter.scale.electric_meter.KILOVOLT_AMPERE_HOURS},
          {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {3}})
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_metering_switch,
        Meter:Get({scale = Meter.scale.electric_meter.KILOVOLT_AMPERE_HOURS},
          {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {4}})
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_metering_switch,
        Meter:Get({scale = Meter.scale.electric_meter.KILOVOLT_AMPERE_HOURS},
          {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {5}})
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_metering_switch,
        Meter:Get({scale = Meter.scale.electric_meter.KILOVOLT_AMPERE_HOURS},
          {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {6}})
      )
    }
  }
)

test.register_message_test(
  "Basic Report 0xFF to channel 0 received, make all component to on and check the metering value",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_metering_switch.id,
        zw_test_utils.zwave_test_build_receive_command(
          Basic:Report(
            {
              value = 0xFF
            },
            {
              encap = zw.ENCAP.AUTO,
              src_channel = 0,
              dst_channels = {0}
            }
          )
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_metering_switch:generate_test_message("main", capabilities.switch.switch.on())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_metering_switch:generate_test_message("switch1", capabilities.switch.switch.on())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_metering_switch:generate_test_message("switch2", capabilities.switch.switch.on())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_metering_switch:generate_test_message("switch3", capabilities.switch.switch.on())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_metering_switch:generate_test_message("switch4", capabilities.switch.switch.on())
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_metering_switch,
        Meter:Get({scale = Meter.scale.electric_meter.KILOVOLT_AMPERE_HOURS},
          {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {3}})
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_metering_switch,
        Meter:Get({scale = Meter.scale.electric_meter.KILOVOLT_AMPERE_HOURS},
          {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {4}})
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_metering_switch,
        Meter:Get({scale = Meter.scale.electric_meter.KILOVOLT_AMPERE_HOURS},
          {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {5}})
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_metering_switch,
        Meter:Get({scale = Meter.scale.electric_meter.KILOVOLT_AMPERE_HOURS},
          {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {6}})
      )
    }
  }
)

test.register_message_test(
  "Basic Report 0x00 to multi channel message should generate proper capability to proper component and check the metering value",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_metering_switch.id,
        zw_test_utils.zwave_test_build_receive_command(
          Basic:Report(
            {
              value = 0x00
            },
            {
              encap = zw.ENCAP.AUTO,
              src_channel = 1,
              dst_channels = {0}
            }
          )
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_metering_switch:generate_test_message("switch1", capabilities.switch.switch.off())
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_metering_switch,
        Meter:Get({scale = Meter.scale.electric_meter.KILOWATT_HOURS},
          {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {3}})
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_metering_switch,
        Meter:Get({scale = Meter.scale.electric_meter.KILOVOLT_AMPERE_HOURS},
          {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {3}})
      )
    }
  }
)

test.register_message_test(
  "Basic Report 0xFF to multi channel message should generate proper capability to proper component and check the metering value",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_metering_switch.id,
        zw_test_utils.zwave_test_build_receive_command(
          Basic:Report(
            {
              value = 0xFF
            },
            {
              encap = zw.ENCAP.AUTO,
              src_channel = 2,
              dst_channels = {0}
            }
          )
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_metering_switch:generate_test_message("switch2", capabilities.switch.switch.on())
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_metering_switch,
        Meter:Get({scale = Meter.scale.electric_meter.KILOWATT_HOURS},
          {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {4}})
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_metering_switch,
        Meter:Get({scale = Meter.scale.electric_meter.KILOVOLT_AMPERE_HOURS},
          {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {4}})
      )
    }
  }
)

test.register_message_test(
  "Meter report for KILOWATT_HOURS to multi channel message should generate proper capability to proper components",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_metering_switch.id,
        zw_test_utils.zwave_test_build_receive_command(
          Meter:Report(
            {
              scale = Meter.scale.electric_meter.KILOWATT_HOURS,
              meter_value = 50.0
            },
            {
              encap = zw.ENCAP.AUTO,
              src_channel = 3,
              dst_channels = {0}
            }
          )
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_metering_switch:generate_test_message("switch1", capabilities.energyMeter.energy({ value = 50.0, unit = "kWh" }))
    }
  }
)

test.register_message_test(
  "Meter report for KILOVOLT_AMPERE_HOURS to multi channel message should generate proper capability to proper components",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_metering_switch.id,
        zw_test_utils.zwave_test_build_receive_command(
          Meter:Report(
            {
              scale = Meter.scale.electric_meter.KILOVOLT_AMPERE_HOURS,
              meter_value = 50.0
            },
            {
              encap = zw.ENCAP.AUTO,
              src_channel = 4,
              dst_channels = {0}
            }
          )
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_metering_switch:generate_test_message("switch2", capabilities.energyMeter.energy({ value = 50.0, unit = "kVAh" }))
    }
  }
)

test.register_message_test(
  "Meter report for WATTS to multi channel message should generate proper capability to proper component and check the metering value",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_metering_switch.id,
        zw_test_utils.zwave_test_build_receive_command(
          Meter:Report(
            {
              scale = Meter.scale.electric_meter.WATTS,
              meter_value = 50
            },
            {
              encap = zw.ENCAP.AUTO,
              src_channel = 5,
              dst_channels = {0}
            }
          )
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_metering_switch:generate_test_message("switch3", capabilities.powerMeter.power({ value = 50, unit = "W" }))
    }
  }
)

test.register_message_test(
  "Meter reports for multi channel 0 message should generate proper capability and get metering value for each component",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_metering_switch.id,
        zw_test_utils.zwave_test_build_receive_command(
          Meter:Report(
            {
              scale = Meter.scale.electric_meter.KILOWATT_HOURS,
              meter_value = 50.0
            },
            {
              encap = zw.ENCAP.AUTO,
              src_channel = 0,
              dst_channels = {0}
            }
          )
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_metering_switch:generate_test_message("main", capabilities.energyMeter.energy({ value = 50.0, unit = "kWh" }))
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_metering_switch,
        Meter:Get({scale = Meter.scale.electric_meter.KILOWATT_HOURS},
          {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {3}})
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_metering_switch,
        Meter:Get({scale = Meter.scale.electric_meter.KILOWATT_HOURS},
          {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {4}})
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_metering_switch,
        Meter:Get({scale = Meter.scale.electric_meter.KILOWATT_HOURS},
          {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {5}})
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_metering_switch,
        Meter:Get({scale = Meter.scale.electric_meter.KILOWATT_HOURS},
          {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {6}})
      )
    }
  }
)

test.register_message_test(
  "Meter reports for multi channel 0 message should generate proper capability",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_metering_switch.id,
        zw_test_utils.zwave_test_build_receive_command(
          Meter:Report(
            {
              scale = Meter.scale.electric_meter.WATTS,
              meter_value = 50
            },
            {
              encap = zw.ENCAP.AUTO,
              src_channel = 0,
              dst_channels = {0}
            }
          )
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_metering_switch:generate_test_message("main", capabilities.powerMeter.power({ value = 50, unit = "W" }))
    }
  }
)

test.register_coroutine_test(
    "doConfigure lifecycle event should generate proper configuration commands for zooz switch",
    function ()
      test.socket.zwave:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle:__queue_receive({ mock_metering_switch.id, "doConfigure" })
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_metering_switch,
          Configuration:Set({parameter_number = 4, size = 1, configuration_value = 1})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_metering_switch,
          Configuration:Set({parameter_number = 5, size = 2, configuration_value = 5})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_metering_switch,
          Configuration:Set({parameter_number = 8, size = 2, configuration_value = 5})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_metering_switch,
          Configuration:Set({parameter_number = 9, size = 2, configuration_value = 5})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_metering_switch,
          Configuration:Set({parameter_number = 10, size = 2, configuration_value = 5})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_metering_switch,
          Configuration:Set({parameter_number = 11, size = 2, configuration_value = 5})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_metering_switch,
          Configuration:Set({parameter_number = 12, size = 1, configuration_value = 50})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_metering_switch,
          Configuration:Set({parameter_number = 15, size = 1, configuration_value = 50})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_metering_switch,
          Configuration:Set({parameter_number = 16, size = 1, configuration_value = 50})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_metering_switch,
          Configuration:Set({parameter_number = 17, size = 1, configuration_value = 50})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_metering_switch,
          Configuration:Set({parameter_number = 18, size = 1, configuration_value = 50})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_metering_switch,
          Configuration:Set({parameter_number = 101, size = 4, configuration_value = 1})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_metering_switch,
          Configuration:Set({parameter_number = 102, size = 4, configuration_value = 30976})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_metering_switch,
          Configuration:Set({parameter_number = 111, size = 4, configuration_value = 900})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_metering_switch,
          Configuration:Set({parameter_number = 112, size = 4, configuration_value = 90})
      ))
      mock_metering_switch:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    end
)

test.register_coroutine_test(
  "Setting switch on to main component should generate correct zwave messages",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_metering_switch.id,
      { capability = "switch", component = "main", command = "on", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_metering_switch,
        SwitchBinary:Set({
          target_value = SwitchBinary.value.ON_ENABLE,
          duration = 0
        },
        {
          encap = zw.ENCAP.AUTO,
          src_channel = 0,
          dst_channels={}
        })
      )
    )

    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_metering_switch,
        SwitchBinary:Get({
        },
        {
          encap = zw.ENCAP.AUTO,
          src_channel = 0,
          dst_channels={}
        })
      )
    )

    test.wait_for_events()
    test.socket.zwave:__queue_receive({
      mock_metering_switch.id,
      SwitchBinary:Report(
        {
          current_value = SwitchBinary.value.ON_ENABLE
        },
        {
          encap = zw.ENCAP.AUTO,
          src_channel = 0,
          dst_channels = {}
        }
      )
    })
    test.socket.capability:__expect_send(
      mock_metering_switch:generate_test_message("main", capabilities.switch.switch.on())
    )
    test.socket.capability:__expect_send(
      mock_metering_switch:generate_test_message("switch1", capabilities.switch.switch.on())
    )
    test.socket.capability:__expect_send(
      mock_metering_switch:generate_test_message("switch2", capabilities.switch.switch.on())
    )
    test.socket.capability:__expect_send(
      mock_metering_switch:generate_test_message("switch3", capabilities.switch.switch.on())
    )
    test.socket.capability:__expect_send(
      mock_metering_switch:generate_test_message("switch4", capabilities.switch.switch.on())
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_metering_switch,
        Meter:Get(
          {
            scale = Meter.scale.electric_meter.KILOVOLT_AMPERE_HOURS
          },
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={3}
          }
        )
      )
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_metering_switch,
        Meter:Get(
          {
            scale = Meter.scale.electric_meter.KILOVOLT_AMPERE_HOURS
          },
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={4}
          }
        )
      )
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_metering_switch,
        Meter:Get(
          {
            scale = Meter.scale.electric_meter.KILOVOLT_AMPERE_HOURS
          },
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={5}
          }
        )
      )
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_metering_switch,
        Meter:Get(
          {
            scale = Meter.scale.electric_meter.KILOVOLT_AMPERE_HOURS
          },
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={6}
          }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Setting switch off to main component should generate correct zwave messages",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_metering_switch.id,
      { capability = "switch", component = "main", command = "off", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_metering_switch,
        SwitchBinary:Set({
          target_value = SwitchBinary.value.OFF_DISABLE,
          duration = 0
        },
        {
          encap = zw.ENCAP.AUTO,
          src_channel = 0,
          dst_channels={}
        })
      )
    )

    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_metering_switch,
        SwitchBinary:Get({
        },
        {
          encap = zw.ENCAP.AUTO,
          src_channel = 0,
          dst_channels={}
        })
      )
    )

    test.wait_for_events()
    test.socket.zwave:__queue_receive({
      mock_metering_switch.id,
      SwitchBinary:Report(
        {
          current_value = SwitchBinary.value.OFF_DISABLE
        },
        {
          encap = zw.ENCAP.AUTO,
          src_channel = 0,
          dst_channels = {}
        }
      )
    })
    test.socket.capability:__expect_send(
      mock_metering_switch:generate_test_message("main", capabilities.switch.switch.off())
    )
    test.socket.capability:__expect_send(
      mock_metering_switch:generate_test_message("switch1", capabilities.switch.switch.off())
    )
    test.socket.capability:__expect_send(
      mock_metering_switch:generate_test_message("switch2", capabilities.switch.switch.off())
    )
    test.socket.capability:__expect_send(
      mock_metering_switch:generate_test_message("switch3", capabilities.switch.switch.off())
    )
    test.socket.capability:__expect_send(
      mock_metering_switch:generate_test_message("switch4", capabilities.switch.switch.off())
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_metering_switch,
        Meter:Get(
          {
            scale = Meter.scale.electric_meter.KILOVOLT_AMPERE_HOURS
          },
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={3}
          }
        )
      )
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_metering_switch,
        Meter:Get(
          {
            scale = Meter.scale.electric_meter.KILOVOLT_AMPERE_HOURS
          },
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={4}
          }
        )
      )
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_metering_switch,
        Meter:Get(
          {
            scale = Meter.scale.electric_meter.KILOVOLT_AMPERE_HOURS
          },
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={5}
          }
        )
      )
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_metering_switch,
        Meter:Get(
          {
            scale = Meter.scale.electric_meter.KILOVOLT_AMPERE_HOURS
          },
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={6}
          }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Setting switch on to switch1 component should generate correct zwave messages",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_metering_switch.id,
      { capability = "switch", component = "switch1", command = "on", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_metering_switch,
        SwitchBinary:Set({
          target_value = SwitchBinary.value.ON_ENABLE,
          duration = 0
        },
        {
          encap = zw.ENCAP.AUTO,
          src_channel = 0,
          dst_channels={1}
        })
      )
    )

    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_metering_switch,
        SwitchBinary:Get({
        },
        {
          encap = zw.ENCAP.AUTO,
          src_channel = 0,
          dst_channels={1}
        })
      )
    )

    test.wait_for_events()
    test.socket.zwave:__queue_receive({
      mock_metering_switch.id,
      SwitchBinary:Report(
        {
          current_value = SwitchBinary.value.ON_ENABLE
        },
        {
          encap = zw.ENCAP.AUTO,
          src_channel = 1,
          dst_channels = {0}
        }
      )
    })
    test.socket.capability:__expect_send(
      mock_metering_switch:generate_test_message("switch1", capabilities.switch.switch.on())
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_metering_switch,
        Meter:Get(
          {
            scale = Meter.scale.electric_meter.KILOWATT_HOURS
          },
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={3}
          }
        )
      )
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_metering_switch,
        Meter:Get(
          {
            scale = Meter.scale.electric_meter.KILOVOLT_AMPERE_HOURS
          },
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={3}
          }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Setting switch off to switch2 component should generate correct zwave messages",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_metering_switch.id,
      { capability = "switch", component = "switch2", command = "off", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_metering_switch,
        SwitchBinary:Set({
          target_value = SwitchBinary.value.OFF_DISABLE,
          duration = 0
        },
        {
          encap = zw.ENCAP.AUTO,
          src_channel = 0,
          dst_channels={2}
        })
      )
    )

    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_metering_switch,
        SwitchBinary:Get({
        },
        {
          encap = zw.ENCAP.AUTO,
          src_channel = 0,
          dst_channels={2}
        })
      )
    )

    test.wait_for_events()
    test.socket.zwave:__queue_receive({
      mock_metering_switch.id,
      SwitchBinary:Report(
        {
          current_value = SwitchBinary.value.OFF_DISABLE
        },
        {
          encap = zw.ENCAP.AUTO,
          src_channel = 2,
          dst_channels = {0}
        }
      )
    })
    test.socket.capability:__expect_send(
      mock_metering_switch:generate_test_message("switch2", capabilities.switch.switch.off())
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_metering_switch,
        Meter:Get(
          {
            scale = Meter.scale.electric_meter.KILOWATT_HOURS
          },
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={4}
          }
        )
      )
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_metering_switch,
        Meter:Get(
          {
            scale = Meter.scale.electric_meter.KILOVOLT_AMPERE_HOURS
          },
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={4}
          }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Setting switch on to switch3 component should generate correct zwave messages",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_metering_switch.id,
      { capability = "switch", component = "switch3", command = "on", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_metering_switch,
        SwitchBinary:Set({
          target_value = SwitchBinary.value.ON_ENABLE,
          duration = 0
        },
        {
          encap = zw.ENCAP.AUTO,
          src_channel = 0,
          dst_channels={3}
        })
      )
    )

    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_metering_switch,
        SwitchBinary:Get({
        },
        {
          encap = zw.ENCAP.AUTO,
          src_channel = 0,
          dst_channels={3}
        })
      )
    )

    test.wait_for_events()
    test.socket.zwave:__queue_receive({
      mock_metering_switch.id,
      SwitchBinary:Report(
        {
          current_value = SwitchBinary.value.ON_ENABLE
        },
        {
          encap = zw.ENCAP.AUTO,
          src_channel = 3,
          dst_channels = {0}
        }
      )
    })
    test.socket.capability:__expect_send(
      mock_metering_switch:generate_test_message("switch3", capabilities.switch.switch.on())
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_metering_switch,
        Meter:Get(
          {
            scale = Meter.scale.electric_meter.KILOWATT_HOURS
          },
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={5}
          }
        )
      )
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_metering_switch,
        Meter:Get(
          {
            scale = Meter.scale.electric_meter.KILOVOLT_AMPERE_HOURS
          },
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={5}
          }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Setting switch off to switch4 component should generate correct zwave messages",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_metering_switch.id,
      { capability = "switch", component = "switch4", command = "off", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_metering_switch,
        SwitchBinary:Set({
          target_value = SwitchBinary.value.OFF_DISABLE,
          duration = 0
        },
        {
          encap = zw.ENCAP.AUTO,
          src_channel = 0,
          dst_channels={4}
        })
      )
    )

    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_metering_switch,
        SwitchBinary:Get({
        },
        {
          encap = zw.ENCAP.AUTO,
          src_channel = 0,
          dst_channels={4}
        })
      )
    )

    test.wait_for_events()
    test.socket.zwave:__queue_receive({
      mock_metering_switch.id,
      SwitchBinary:Report(
        {
          current_value = SwitchBinary.value.OFF_DISABLE
        },
        {
          encap = zw.ENCAP.AUTO,
          src_channel = 4,
          dst_channels = {0}
        }
      )
    })
    test.socket.capability:__expect_send(
      mock_metering_switch:generate_test_message("switch4", capabilities.switch.switch.off())
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_metering_switch,
        Meter:Get(
          {
            scale = Meter.scale.electric_meter.KILOWATT_HOURS
          },
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={6}
          }
        )
      )
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_metering_switch,
        Meter:Get(
          {
            scale = Meter.scale.electric_meter.KILOVOLT_AMPERE_HOURS
          },
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={6}
          }
        )
      )
    )
  end
)

test.run_registered_tests()
