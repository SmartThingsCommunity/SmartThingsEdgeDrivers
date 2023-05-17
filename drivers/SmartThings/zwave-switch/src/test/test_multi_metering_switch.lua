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
local Meter = (require "st.zwave.CommandClass.Meter")({ version = 3 })
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({ version = 2 })
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version = 4 })
local t_utils = require "integration_test.utils"

local profile = t_utils.get_profile_definition("metering-switch.yml")

local AEOTEC_MANUFACTURER_ID = 0x0086
local AEOTEC_PRODUCT_TYPE = 0x0003
local AEOTEC_PRODUCT_ID = 0x0084

local switch_multicomponent_endpoints = {
  { -- ep 1 (parent)
    command_classes = {
      { value = zw.BASIC },
      { value = zw.SWITCH_BINARY },
      { value = zw.METER }
    }
  },
  { -- ep 2 (child)
    command_classes = {
      { value = zw.BASIC },
      { value = zw.SWITCH_BINARY },
      { value = zw.METER }
    }
  }
}

local mock_parent_device = test.mock_device.build_test_zwave_device({
  profile = profile,
  label = "Aeotec Switch 1",
  zwave_endpoints = switch_multicomponent_endpoints,
  zwave_manufacturer_id = AEOTEC_MANUFACTURER_ID,
  zwave_product_type = AEOTEC_PRODUCT_TYPE,
  zwave_product_id = AEOTEC_PRODUCT_ID
})

local mock_base_device = test.mock_device.build_test_zwave_device({
  profile = profile,
  label = "Aeotec Switch 1",
  zwave_endpoints = switch_multicomponent_endpoints,
  zwave_manufacturer_id = AEOTEC_MANUFACTURER_ID,
  zwave_product_type = AEOTEC_PRODUCT_TYPE,
  zwave_product_id = AEOTEC_PRODUCT_ID
})

local mock_child_device = test.mock_device.build_test_child_device({
  profile = profile,
  parent_device_id = mock_parent_device.id,
  parent_assigned_child_key = string.format("%02X", 2)
})

local function test_init()
  test.mock_device.add_test_device(mock_parent_device)
  test.mock_device.add_test_device(mock_base_device)
  test.mock_device.add_test_device(mock_child_device)
end
test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Added should create the correct number of children",
  function ()
    test.socket.device_lifecycle:__queue_receive({ mock_base_device.id, "added" })
    mock_base_device:expect_device_create({
      type = "EDGE_CHILD",
      label = "Aeotec Switch 2",
      profile = "metering-switch",
      parent_device_id = mock_base_device.id,
      parent_assigned_child_key = "02"
    })
    test.socket.zwave:__set_channel_ordering("relaxed")
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_base_device,
        SwitchBinary:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels = { 1 }
          }
        )
      )
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_base_device,
        Meter:Get(
          { scale = Meter.scale.electric_meter.KILOWATT_HOURS },
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels = { 1 }
          }
        )
      )
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
      mock_base_device,
        Meter:Get(
          { scale = Meter.scale.electric_meter.WATTS },
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels = { 1 }
          }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Refresh on parent device sends commands to 1 endpoint",
  function()
    test.socket.zwave:__set_channel_ordering("relaxed")
    test.socket.capability:__queue_receive({
      mock_parent_device.id,
      { capability = "refresh", component = "main", command = "refresh", args = { } }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_parent_device,
        SwitchBinary:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels = { 1 }
          }
        )
      )
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_parent_device,
        Meter:Get(
          { scale = Meter.scale.electric_meter.KILOWATT_HOURS },
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels = { 1 }
          }
        )
      )
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
      mock_parent_device,
        Meter:Get(
          { scale = Meter.scale.electric_meter.WATTS },
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels = { 1 }
          }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Refresh on child device sends commands to 2 endpoint",
  function()
    test.socket.zwave:__set_channel_ordering("relaxed")
    test.socket.capability:__queue_receive({
      mock_child_device.id,
      { capability = "refresh", component = "main", command = "refresh", args = { } }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_parent_device,
        SwitchBinary:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels = { 2 }
          }
        )
      )
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_parent_device,
        Meter:Get(
          { scale = Meter.scale.electric_meter.KILOWATT_HOURS },
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels = { 2 }
          }
        )
      )
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_parent_device,
        Meter:Get(
          { scale = Meter.scale.electric_meter.WATTS },
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels = { 2 }
          }
        )
      )
    )
  end
)

test.register_message_test(
  "Switch on/off capability command from parent device should be handled: on",
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
  "Switch on/off capability command from parent device should be handled: on",
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

test.register_coroutine_test(
    "doConfigure lifecycle event should generate proper configuration commands for aeotec switch",
    function ()
      test.socket.zwave:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle:__queue_receive({ mock_parent_device.id, "doConfigure"})
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_parent_device,
          Configuration:Set({parameter_number = 255, size = 1, configuration_value = 0})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_parent_device,
          Configuration:Set({parameter_number = 4, size = 1, configuration_value = 1})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_parent_device,
          Configuration:Set({parameter_number = 80, size = 1, configuration_value = 2})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_parent_device,
          Configuration:Set({parameter_number = 101, size = 4, configuration_value = 2048})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_parent_device,
          Configuration:Set({parameter_number = 111, size = 4, configuration_value = 600})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_parent_device,
          Configuration:Set({parameter_number = 102, size = 4, configuration_value = 4096})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_parent_device,
          Configuration:Set({parameter_number = 112, size = 4, configuration_value = 600})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_parent_device,
          Configuration:Set({parameter_number = 90, size = 1, configuration_value = 1})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_parent_device,
          Configuration:Set({parameter_number = 91, size = 2, configuration_value = 20})
      ))

      mock_parent_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    end
)

test.register_message_test(
  "Binary switch on/off report from channel 1 should be handled: on",
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
            { target_value = SwitchBinary.value.ON_ENABLE, current_value = SwitchBinary.value.ON_ENABLE },
            { encap = zw.ENCAP.AUTO, src_channel = 1, dst_channels = { 0 } }
          )
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_parent_device:generate_test_message("main", capabilities.switch.switch.on())
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_parent_device,
        Meter:Get(
          { scale = Meter.scale.electric_meter.WATTS },
          { encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = { 1 } }
        )
      )
    }
  }
)

test.register_message_test(
  "Binary switch on/off report from channel 2 should be handled: on",
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
            { target_value = SwitchBinary.value.ON_ENABLE, current_value = SwitchBinary.value.ON_ENABLE },
            { encap = zw.ENCAP.AUTO, src_channel = 2, dst_channels = { 0 } }
          )
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_child_device:generate_test_message("main", capabilities.switch.switch.on())
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_parent_device,
        Meter:Get(
          { scale = Meter.scale.electric_meter.WATTS },
          { encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = { 2 } }
        )
      )
    }
  }
)

do
  local energy = 5
  test.register_message_test(
    "Energy meter report from parent device should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent_device.id,
          zw_test_utils.zwave_test_build_receive_command(
            Meter:Report(
              { scale = Meter.scale.electric_meter.KILOWATT_HOURS, meter_value = energy},
              { encap = zw.ENCAP.AUTO, src_channel = 1, dst_channels = {0} }
            )
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent_device:generate_test_message(
          "main", capabilities.energyMeter.energy({ value = energy, unit = "kWh" }))
      }
    }
  )
end


do
  local energy = 5
  test.register_message_test(
    "Energy meter report from child device should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_child_device.id,
          zw_test_utils.zwave_test_build_receive_command(
            Meter:Report(
              { scale = Meter.scale.electric_meter.KILOWATT_HOURS, meter_value = energy },
              { encap = zw.ENCAP.AUTO, src_channel = 2, dst_channels = {0} }
            )
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_device:generate_test_message(
          "main", capabilities.energyMeter.energy({ value = energy, unit = "kWh" })
        )
      }
    }
  )
end

do
  local power = 89
  test.register_message_test(
    "Power meter report from parent device should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent_device.id,
          zw_test_utils.zwave_test_build_receive_command(
            Meter:Report(
              { scale = Meter.scale.electric_meter.WATTS, meter_value = power},
              { encap = zw.ENCAP.AUTO, src_channel = 1, dst_channels = {0} }
            )
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent_device:generate_test_message(
          "main", capabilities.powerMeter.power({ value = power, unit = "W" }))
      }
    }
  )
end

do
  local power = 89
  test.register_message_test(
    "Power meter report from child device should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_child_device.id,
          zw_test_utils.zwave_test_build_receive_command(
            Meter:Report(
              { scale = Meter.scale.electric_meter.WATTS, meter_value = power},
              { encap = zw.ENCAP.AUTO, src_channel = 2, dst_channels = {0} }
            )
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_device:generate_test_message(
          "main", capabilities.powerMeter.power({ value = power, unit = "W" }))
      }
    }
  )
end

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

do
  local power = 89
  test.register_coroutine_test(
    "Power meter report from root node device should refresh all devices",
    function ()
      test.socket.zwave:__queue_receive({
        mock_parent_device.id,
        Meter:Report({
          scale = Meter.scale.electric_meter.WATTS, meter_value = power
        })
      })
      test.socket.zwave:__set_channel_ordering("relaxed")
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_parent_device,
          SwitchBinary:Get({},
            {
              encap = zw.ENCAP.AUTO,
              src_channel = 0,
              dst_channels = { 1 }
            }
          )
        )
      )
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_parent_device,
          Meter:Get(
            { scale = Meter.scale.electric_meter.KILOWATT_HOURS },
            {
              encap = zw.ENCAP.AUTO,
              src_channel = 0,
              dst_channels = { 1 }
            }
          )
        )
      )
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
        mock_parent_device,
          Meter:Get(
            { scale = Meter.scale.electric_meter.WATTS },
            {
              encap = zw.ENCAP.AUTO,
              src_channel = 0,
              dst_channels = { 1 }
            }
          )
        )
      )
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_parent_device,
          SwitchBinary:Get({},
            {
              encap = zw.ENCAP.AUTO,
              src_channel = 0,
              dst_channels = { 2 }
            }
          )
        )
      )
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_parent_device,
          Meter:Get(
            { scale = Meter.scale.electric_meter.KILOWATT_HOURS },
            {
              encap = zw.ENCAP.AUTO,
              src_channel = 0,
              dst_channels = { 2 }
            }
          )
        )
      )
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
        mock_parent_device,
          Meter:Get(
            { scale = Meter.scale.electric_meter.WATTS },
            {
              encap = zw.ENCAP.AUTO,
              src_channel = 0,
              dst_channels = { 2 }
            }
          )
        )
      )
    end
  )
end

test.register_coroutine_test(
  "Switch Binary report from root node device should be ignored",
  function ()
    test.socket.zwave:__queue_receive({
      mock_parent_device.id,
      SwitchBinary:Report({
        current_value = 0xFF
      })
    })
  end
)

test.run_registered_tests()
