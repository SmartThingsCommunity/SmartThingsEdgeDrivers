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
local Meter = (require "st.zwave.CommandClass.Meter")({version=3})
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({version=2})
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version=4 })
local t_utils = require "integration_test.utils"

local AEOTEC_MANUFACTURER_ID = 0x0086
local AEOTEC_PRODUCT_TYPE = 0x0003
local AEOTEC_PRODUCT_ID = 0x0084

local ZOOZ_MANUFACTURER_ID = 0x027A
local ZOOZ_PRODUCT_TYPE = 0xA000
local ZOOZ_PRODUCT_ID = 0xA003

local switch_multicomponent_endpoints = {
  {
    command_classes = {
      { value = zw.BASIC },
      { value = zw.SWITCH_BINARY },
      { value = zw.METER }
    }
  },
  {
    command_classes = {
      { value = zw.BASIC },
      { value = zw.SWITCH_BINARY },
      { value = zw.METER }
    }
  }
}

local mock_aeotec_switch_multicomponent = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("dual-metering-switch.yml"),
  zwave_endpoints = switch_multicomponent_endpoints,
  zwave_manufacturer_id = AEOTEC_MANUFACTURER_ID,
  zwave_product_type = AEOTEC_PRODUCT_TYPE,
  zwave_product_id = AEOTEC_PRODUCT_ID
})

local mock_zooz_switch_multicomponent = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("dual-metering-switch.yml"),
  zwave_endpoints = switch_multicomponent_endpoints,
  zwave_manufacturer_id = ZOOZ_MANUFACTURER_ID,
  zwave_product_type = ZOOZ_PRODUCT_TYPE,
  zwave_product_id = ZOOZ_PRODUCT_ID
})

local function test_init()
  test.mock_device.add_test_device(mock_aeotec_switch_multicomponent)
  test.mock_device.add_test_device(mock_zooz_switch_multicomponent)
end
test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Refresh sends commands to all components including base device",
  function()
    -- refresh commands for zwave devices do not have guaranteed ordering
    test.socket.zwave:__set_channel_ordering("relaxed")
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_aeotec_switch_multicomponent,
        SwitchBinary:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels = {1}
          })
      ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_aeotec_switch_multicomponent,
        SwitchBinary:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels = {}
          })
      ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_aeotec_switch_multicomponent,
        Meter:Get({scale = Meter.scale.electric_meter.KILOWATT_HOURS},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels = {}
          })
      ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_aeotec_switch_multicomponent,
        Meter:Get({scale = Meter.scale.electric_meter.WATTS},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels = {}
          })
      ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_aeotec_switch_multicomponent,
        Meter:Get({scale = Meter.scale.electric_meter.KILOWATT_HOURS},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels = {1}
          })
      ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_aeotec_switch_multicomponent,
        Meter:Get({scale = Meter.scale.electric_meter.WATTS},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels = {1}
          })
      ))
    test.socket.capability:__queue_receive({
      mock_aeotec_switch_multicomponent.id,
      { capability = "refresh", component = "main", command = "refresh", args = { } }
    })
  end
)

test.register_message_test(
  "Multichannel switch on/off capability command on from component 1 should be handled: on",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_aeotec_switch_multicomponent.id,
        { capability = "switch", command = "on", component = "switch1", args = {} }
      }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_aeotec_switch_multicomponent,
        SwitchBinary:Set({ target_value=0xFF },
          {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {1}})
      )
    }
  }
)

test.register_message_test(
  "Multichannel switch on/off capability command off from main component should be handled: off",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_aeotec_switch_multicomponent.id,
        { capability = "switch", command = "off", component = "main", args = {} }
      }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_aeotec_switch_multicomponent,
        SwitchBinary:Set({ target_value=0x00 })
      )
    }
  }
)

test.register_coroutine_test(
    "doConfigure lifecycle event should generate proper configuration commands for aeotec switch",
    function ()
      test.socket.zwave:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle:__queue_receive({ mock_aeotec_switch_multicomponent.id, "doConfigure"})
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_aeotec_switch_multicomponent,
          Configuration:Set({parameter_number = 255, size = 1, configuration_value = 0})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_aeotec_switch_multicomponent,
          Configuration:Set({parameter_number = 4, size = 1, configuration_value = 1})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_aeotec_switch_multicomponent,
          Configuration:Set({parameter_number = 80, size = 1, configuration_value = 2})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_aeotec_switch_multicomponent,
          Configuration:Set({parameter_number = 101, size = 4, configuration_value = 2048})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_aeotec_switch_multicomponent,
          Configuration:Set({parameter_number = 111, size = 4, configuration_value = 600})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_aeotec_switch_multicomponent,
          Configuration:Set({parameter_number = 102, size = 4, configuration_value = 4096})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_aeotec_switch_multicomponent,
          Configuration:Set({parameter_number = 112, size = 4, configuration_value = 600})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_aeotec_switch_multicomponent,
          Configuration:Set({parameter_number = 90, size = 1, configuration_value = 1})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_aeotec_switch_multicomponent,
          Configuration:Set({parameter_number = 91, size = 2, configuration_value = 20})
      ))

      mock_aeotec_switch_multicomponent:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    end
)

test.register_message_test(
  "Binary switch on/off report from channel 1 should be handled: on",
  {
    {
    channel = "device_lifecycle",
    direction = "receive",
    message = { mock_aeotec_switch_multicomponent.id, "init" },
    },
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_aeotec_switch_multicomponent.id,
                  zw_test_utils.zwave_test_build_receive_command(SwitchBinary:Report({ current_value=0xFF },
                  {encap = zw.ENCAP.AUTO, src_channel = 1, dst_channels = {0}}))}
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_aeotec_switch_multicomponent:generate_test_message("switch1", capabilities.switch.switch.on())
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_aeotec_switch_multicomponent,
        Meter:Get({scale = Meter.scale.electric_meter.WATTS},
        {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {1}})
      )
    }
  }
)

test.register_message_test(
  "Z-Wave SwitchBinary reports with value-off should evoke Switch capability off events",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_aeotec_switch_multicomponent.id, "init" },
    },
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_aeotec_switch_multicomponent.id,
        zw_test_utils.zwave_test_build_receive_command(
          SwitchBinary:Report({ current_value=0x00 })
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_aeotec_switch_multicomponent:generate_test_message("main", capabilities.switch.switch.off())
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_aeotec_switch_multicomponent,
        Meter:Get({scale = Meter.scale.electric_meter.WATTS})
      )
    }
  }
)


do
  local energy = 5
  test.register_message_test(
    "Energy meter report should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_aeotec_switch_multicomponent.id, zw_test_utils.zwave_test_build_receive_command(Meter:Report({
          scale = Meter.scale.electric_meter.KILOWATT_HOURS,
          meter_value = energy})
        )}
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_aeotec_switch_multicomponent:generate_test_message("main", capabilities.energyMeter.energy({ value = energy, unit = "kWh" }))
      }
    }
  )
end

do
  local energy = 5
  test.register_message_test(
    "Energy meter report from multicomponent should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_aeotec_switch_multicomponent.id, zw_test_utils.zwave_test_build_receive_command(Meter:Report({
          scale = Meter.scale.electric_meter.KILOWATT_HOURS,
          meter_value = energy},
          { encap = zw.ENCAP.AUTO, src_channel = 1, dst_channels = {0} })
        )}
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_aeotec_switch_multicomponent:generate_test_message("switch1", capabilities.energyMeter.energy({ value = energy, unit = "kWh" }))
      }
    }
  )
end

do
  local power = 89
  test.register_message_test(
    "Power meter report should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_aeotec_switch_multicomponent.id, zw_test_utils.zwave_test_build_receive_command(Meter:Report({
          scale = Meter.scale.electric_meter.WATTS,
          meter_value = power})
        )}
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_aeotec_switch_multicomponent:generate_test_message("main", capabilities.powerMeter.power({ value = power, unit = "W" }))
      }
    }
  )
end

do
  local power = 89
  test.register_message_test(
    "Power meter report from multicomponent should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_aeotec_switch_multicomponent.id, zw_test_utils.zwave_test_build_receive_command(Meter:Report({
          scale = Meter.scale.electric_meter.WATTS,
          meter_value = power},
          { encap = zw.ENCAP.AUTO, src_channel = 1, dst_channels = {0} })
        )}
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_aeotec_switch_multicomponent:generate_test_message("switch1", capabilities.powerMeter.power({ value = power, unit = "W" }))
      }
    }
  )
end

test.register_coroutine_test(
  "Switch capability off commands should evoke the correct Z-Wave SETs and GETs",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_aeotec_switch_multicomponent.id,
      { capability = "switch", command = "off", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_aeotec_switch_multicomponent,
        SwitchBinary:Set({
          target_value = SwitchBinary.value.OFF_DISABLE
        })
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_aeotec_switch_multicomponent,
        SwitchBinary:Get({})
      )
    )
  end
)

test.register_coroutine_test(
  "Switch capability off commands from multicomponent should evoke the correct Z-Wave SETs and GETs",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_aeotec_switch_multicomponent.id,
      { capability = "switch", command = "off", component = "switch1", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_aeotec_switch_multicomponent,
        SwitchBinary:Set({
          target_value = SwitchBinary.value.OFF_DISABLE
        }, { encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {1} }
        )
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_aeotec_switch_multicomponent,
        SwitchBinary:Get({}, { encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {1} })
      )
    )
  end
)

test.register_coroutine_test(
  "Zooz - doConfigure lifecycle event should generate proper configuration commands for zooz switch",
  function ()
    test.socket.zwave:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({ mock_zooz_switch_multicomponent.id, "doConfigure" })
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
            mock_zooz_switch_multicomponent,
            Configuration:Set({parameter_number = 2, size = 4, configuration_value = 10})
    ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
            mock_zooz_switch_multicomponent,
            Configuration:Set({parameter_number = 3, size = 4, configuration_value = 600})
    ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
            mock_zooz_switch_multicomponent,
            Configuration:Set({parameter_number = 4, size = 4, configuration_value = 600})
    ))
    test.socket.zwave:__set_channel_ordering("relaxed")
    mock_zooz_switch_multicomponent:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)

test.register_coroutine_test(
  "Zooz - Refresh sends commands to all components including base device",
  function()
    -- refresh commands for zwave devices do not have guaranteed ordering
    test.socket.zwave:__set_channel_ordering("relaxed")
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_zooz_switch_multicomponent,
        SwitchBinary:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels = {1}
          })
      ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_zooz_switch_multicomponent,
        SwitchBinary:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels = {2}
          })
      ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_zooz_switch_multicomponent,
        Meter:Get({scale = Meter.scale.electric_meter.KILOWATT_HOURS},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels = {1}
          })
      ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_zooz_switch_multicomponent,
        Meter:Get({scale = Meter.scale.electric_meter.WATTS},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels = {1}
          })
      ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_zooz_switch_multicomponent,
        Meter:Get({scale = Meter.scale.electric_meter.KILOWATT_HOURS},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels = {2}
          })
      ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_zooz_switch_multicomponent,
        Meter:Get({scale = Meter.scale.electric_meter.WATTS},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels = {2}
          })
      ))
    test.socket.capability:__queue_receive({
      mock_zooz_switch_multicomponent.id,
      { capability = "refresh", component = "main", command = "refresh", args = { } }
    })
  end
)

test.register_message_test(
  "Multichannel switch on/off capability command on from component 1 should be handled: on",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_zooz_switch_multicomponent.id,
        { capability = "switch", command = "on", component = "main", args = {} }
      }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_zooz_switch_multicomponent,
        SwitchBinary:Set({ target_value=0xFF },
          {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {1}}
        )
      )
    }
  }
)

test.register_message_test(
  "Zooz - Multichannel switch on/off capability command on from component 2 should be handled: on",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_zooz_switch_multicomponent.id,
        { capability = "switch", command = "on", component = "switch1", args = {} }
      }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_zooz_switch_multicomponent,
        SwitchBinary:Set({ target_value=0xFF },
          {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {2}}
        )
      )
    }
  }
)

test.register_message_test(
  "Zooz - Multichannel switch on/off capability command off from main component should be handled: off",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_zooz_switch_multicomponent.id,
        { capability = "switch", command = "off", component = "main", args = {} }
      }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_zooz_switch_multicomponent,
        SwitchBinary:Set(
          { target_value=0x00 },
          { encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {1} }
        )
      )
    }
  }
)

test.register_message_test(
  "Zooz - Multichannel switch on/off capability command off from switch1 component should be handled: off",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_zooz_switch_multicomponent.id,
        { capability = "switch", command = "off", component = "switch1", args = {} }
      }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_zooz_switch_multicomponent,
        SwitchBinary:Set(
          { target_value=0x00 },
          { encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {2} }
        )
      )
    }
  }
)

test.register_message_test(
  "Zooz - Binary switch on/off report from channel 1 should be handled: on",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_zooz_switch_multicomponent.id, "init" },
    },
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_zooz_switch_multicomponent.id,
                  zw_test_utils.zwave_test_build_receive_command(SwitchBinary:Report({ current_value=0xFF },
                          {encap = zw.ENCAP.AUTO, src_channel = 1, dst_channels = {0}}))}
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_zooz_switch_multicomponent:generate_test_message("main", capabilities.switch.switch.on())
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
              mock_zooz_switch_multicomponent,
              Meter:Get({scale = Meter.scale.electric_meter.WATTS},
                      {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {1}})
      )
    }
  }
)

test.register_message_test(
  "Zooz - Binary switch on/off report from channel 2 should be handled: on",
  {
    {
    channel = "device_lifecycle",
    direction = "receive",
    message = { mock_zooz_switch_multicomponent.id, "init" },
    },
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_zooz_switch_multicomponent.id,
                  zw_test_utils.zwave_test_build_receive_command(SwitchBinary:Report({ current_value=0xFF },
                  {encap = zw.ENCAP.AUTO, src_channel = 2, dst_channels = {0}}))}
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_zooz_switch_multicomponent:generate_test_message("switch1", capabilities.switch.switch.on())
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_zooz_switch_multicomponent,
        Meter:Get({scale = Meter.scale.electric_meter.WATTS},
        {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {2}})
      )
    }
  }
)

test.register_message_test(
  "Zooz - SwitchBinary reports with value-off from endpoint 1 should evoke Switch capability off events",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_zooz_switch_multicomponent.id, "init" },
    },
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_zooz_switch_multicomponent.id,
        zw_test_utils.zwave_test_build_receive_command(
          SwitchBinary:Report(
            { current_value=0x00 },
            { encap = zw.ENCAP.AUTO, src_channel = 1, dst_channels = {0} })
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_zooz_switch_multicomponent:generate_test_message("main", capabilities.switch.switch.off())
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_zooz_switch_multicomponent,
        Meter:Get(
          {scale = Meter.scale.electric_meter.WATTS},
          { encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {1} }
        )
      )
    }
  }
)

test.register_message_test(
    "Zooz - SwitchBinary reports with value-off from endpoint 2 should evoke Switch capability off events",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_zooz_switch_multicomponent.id, "init" },
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_zooz_switch_multicomponent.id,
          zw_test_utils.zwave_test_build_receive_command(
            SwitchBinary:Report(
              { current_value=0x00 },
              { encap = zw.ENCAP.AUTO, src_channel = 2, dst_channels = {0} })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_zooz_switch_multicomponent:generate_test_message("switch1", capabilities.switch.switch.off())
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
          mock_zooz_switch_multicomponent,
          Meter:Get(
            {scale = Meter.scale.electric_meter.WATTS},
            { encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {2} }
          )
        )
      }
    }
)

do
  local energy = 5
  test.register_message_test(
    "Zooz - Energy meter report from endpoint 1 should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_zooz_switch_multicomponent.id, zw_test_utils.zwave_test_build_receive_command(Meter:Report({
          scale = Meter.scale.electric_meter.KILOWATT_HOURS,
          meter_value = energy},
          { encap = zw.ENCAP.AUTO, src_channel = 1, dst_channels = {0} })
        )}
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_zooz_switch_multicomponent:generate_test_message("main", capabilities.energyMeter.energy({ value = energy, unit = "kWh" }))
      }
    }
  )
end

do
  local energy = 5
  test.register_message_test(
    "Zooz - Energy meter report from endpoint 2 should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_zooz_switch_multicomponent.id, zw_test_utils.zwave_test_build_receive_command(Meter:Report({
          scale = Meter.scale.electric_meter.KILOWATT_HOURS,
          meter_value = energy},
          {encap = zw.ENCAP.AUTO, src_channel = 2, dst_channels = {0}})
        )}
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_zooz_switch_multicomponent:generate_test_message("switch1", capabilities.energyMeter.energy({ value = energy, unit = "kWh" }))
      }
    }
  )
end

do
  local power = 89
  test.register_message_test(
    "Zooz - Power meter report from endpoint 1 should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_zooz_switch_multicomponent.id, zw_test_utils.zwave_test_build_receive_command(Meter:Report({
          scale = Meter.scale.electric_meter.WATTS,
          meter_value = power},
          {encap = zw.ENCAP.AUTO, src_channel = 1, dst_channels = {0}})
        )}
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_zooz_switch_multicomponent:generate_test_message("main", capabilities.powerMeter.power({ value = power, unit = "W" }))
      }
    }
  )
end

do
  local power = 89
  test.register_message_test(
    "Zooz - Power meter report from endpoint 2 should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_zooz_switch_multicomponent.id, zw_test_utils.zwave_test_build_receive_command(Meter:Report({
          scale = Meter.scale.electric_meter.WATTS,
          meter_value = power},
          {encap = zw.ENCAP.AUTO, src_channel = 2, dst_channels = {0}})
        )}
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_zooz_switch_multicomponent:generate_test_message("switch1", capabilities.powerMeter.power({ value = power, unit = "W" }))
      }
    }
  )
end

test.register_coroutine_test(
  "Zooz - Switch capability off commands from main component should evoke the correct Z-Wave SETs and GETs",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_zooz_switch_multicomponent.id,
        {capability = "switch", command = "off", component = "main", args = {}}
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_zooz_switch_multicomponent,
        SwitchBinary:Set({
          target_value = SwitchBinary.value.OFF_DISABLE
        }, { encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {1} }
        )
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_zooz_switch_multicomponent,
        SwitchBinary:Get({}, { encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {1} })
      )
    )
  end
)

test.register_coroutine_test(
  "Zooz - Switch capability off commands from switch1 component should evoke the correct Z-Wave SETs and GETs",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_zooz_switch_multicomponent.id,
      { capability = "switch", command = "off", component = "switch1", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_zooz_switch_multicomponent,
        SwitchBinary:Set({
          target_value = SwitchBinary.value.OFF_DISABLE
        }, { encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {2} }
        )
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_zooz_switch_multicomponent,
        SwitchBinary:Get({}, { encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {2} })
      )
    )
  end
)

test.run_registered_tests()
