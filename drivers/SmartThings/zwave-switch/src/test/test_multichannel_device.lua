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
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({ version = 2, strict = true })
local SwitchMultilevel = (require "st.zwave.CommandClass.SwitchMultilevel")({ version = 4, strict = true })
local SensorAlarm = (require "st.zwave.CommandClass.SensorAlarm")({ version = 1 })
local SensorBinary = (require "st.zwave.CommandClass.SensorBinary")({ version = 2 })
local SensorMultilevel = (require "st.zwave.CommandClass.SensorMultilevel")({ version = 5 })
local Notification = (require "st.zwave.CommandClass.Notification")({ version = 7 })
local Meter = (require "st.zwave.CommandClass.Meter")({ version = 3 })
local MultiChannel = (require "st.zwave.CommandClass.MultiChannel")({ version = 3 })
local t_utils = require "integration_test.utils"

-- supported command classes
local switch_endpoints = {
  {
    command_classes = {
      { value = zw.BASIC },
      { value = zw.SWITCH_BINARY },
      { value = zw.SWITCH_MULTILEVEL },
      { value = zw.SENSOR_BINARY },
      { value = zw.SENSOR_MULTILEVEL },
      { value = zw.SENSOR_ALARM },
      { value = zw.NOTIFICATION },
      { value = zw.BATTERY },
      { value = zw.METER },
      { value = zw.MULTI_CHANNEL }
    }
  },
  {
    command_classes = {
      { value = zw.BASIC },
      { value = zw.SWITCH_BINARY },
      { value = zw.MULTI_CHANNEL }
    }
  },
  {
    command_classes = {
      { value = zw.BASIC },
      { value = zw.SWITCH_BINARY },
      { value = zw.MULTI_CHANNEL }
    }
  },
  {
    command_classes = {
      { value = zw.BASIC },
      { value = zw.SWITCH_BINARY },
      { value = zw.SWITCH_MULTILEVEL },
      { value = zw.MULTI_CHANNEL }
    }
  },
  {
    command_classes = {
      { value = zw.BASIC },
      { value = zw.SENSOR_BINARY },
      { value = zw.SENSOR_ALARM },
      { value = zw.NOTIFICATION },
      { value = zw.MULTI_CHANNEL }
    }
  },
  {
    command_classes = {
      { value = zw.BASIC },
      { value = zw.SENSOR_MULTILEVEL },
      { value = zw.MULTI_CHANNEL }
    }
  }
}

local function prepare_metadata(device, endpoint, profile)
  local name = string.format("%s %d", device.label, endpoint)
  return {
    type = "EDGE_CHILD",
    label = name,
    profile = profile,
    parent_device_id = device.id,
    parent_assigned_child_key = string.format("%02X", endpoint)
  }
end

local base_parent = test.mock_device.build_test_zwave_device({
  label = "Z-Wave Switch Multichannel",
  profile = t_utils.get_profile_definition("multichannel-switch-level.yml"),
  zwave_endpoints = switch_endpoints
})

local mock_parent = test.mock_device.build_test_zwave_device({
  label = "Z-Wave Switch Multichannel",
  profile = t_utils.get_profile_definition("multichannel-switch-level.yml"),
  zwave_endpoints = switch_endpoints
})

local mock_child = test.mock_device.build_test_child_device({
  profile = t_utils.get_profile_definition("metering-switch.yml"),
  parent_device_id = mock_parent.id,
  parent_assigned_child_key = string.format("%02X", 1)
})

local mock_child_2 = test.mock_device.build_test_child_device({
  profile = t_utils.get_profile_definition("metering-switch.yml"),
  parent_device_id = mock_parent.id,
  parent_assigned_child_key = string.format("%02X", 2)
})

local mock_child_3 = test.mock_device.build_test_child_device({
  profile = t_utils.get_profile_definition("metering-dimmer.yml"),
  parent_device_id = mock_parent.id,
  parent_assigned_child_key = string.format("%02X", 3)
})

local mock_child_4 = test.mock_device.build_test_child_device({
  profile = t_utils.get_profile_definition("generic-sensor.yml"),
  parent_device_id = mock_parent.id,
  parent_assigned_child_key = string.format("%02X", 4)
})

local mock_child_5 = test.mock_device.build_test_child_device({
  profile = t_utils.get_profile_definition("generic-multi-sensor.yml"),
  parent_device_id = mock_parent.id,
  parent_assigned_child_key = string.format("%02X", 5)
})

local function test_init()
  test.mock_device.add_test_device(base_parent)
  test.mock_device.add_test_device(mock_parent)
  test.mock_device.add_test_device(mock_child)
  test.mock_device.add_test_device(mock_child_2)
  test.mock_device.add_test_device(mock_child_3)
  test.mock_device.add_test_device(mock_child_4)
  test.mock_device.add_test_device(mock_child_5)
end

test.set_test_init_function(test_init)

test.register_message_test(
    "Basic report (0x00) should be handled by parent device",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_parent.id, "init" }
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Basic:Report({ value = 0x00 }, { src_channel = 0 })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.switch.switch.off())
      }
    }
)

test.register_message_test(
    "Basic report (0x00) should be handled by child device",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_parent.id, "init" }
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Basic:Report({ value = 0x00 }, { src_channel = 1 })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.switch.switch.off())
      }
    }
)

test.register_message_test(
    "Basic report (0x00) should be handled by child 2 device",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_parent.id, "init" }
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Basic:Report({ value = 0x00 }, { src_channel = 2 })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_2:generate_test_message("main", capabilities.switch.switch.off())
      }
    }
)

test.register_message_test(
    "Basic report (0x00) should be handled by child 3 device",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_parent.id, "init" }
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Basic:Report({ value = 0x00 }, { src_channel = 3 })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_3:generate_test_message("main", capabilities.switch.switch.off())
      }
    }
)

test.register_message_test(
    "Basic report (0xFF) should be handled by parent device",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_parent.id, "init" }
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Basic:Report({ value = 0xFF }, { src_channel = 0 })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.switch.switch.on())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.switchLevel.level(100))
      }
    }
)

test.register_message_test(
    "Basic report (0xFF) should be handled by child device",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_parent.id, "init" }
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Basic:Report({ value = 0xFF }, { src_channel = 1 })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.switch.switch.on())
      }
    }
)

test.register_message_test(
    "Basic report (0xFF) should be handled by child 2 device",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_parent.id, "init" }
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Basic:Report({ value = 0xFF }, { src_channel = 2 })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_2:generate_test_message("main", capabilities.switch.switch.on())
      }
    }
)

test.register_message_test(
    "Basic report (0xFF) should be handled by child 3 device",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_parent.id, "init" }
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Basic:Report({ value = 0xFF }, { src_channel = 3 })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_3:generate_test_message("main", capabilities.switch.switch.on())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_3:generate_test_message("main", capabilities.switchLevel.level(100))
      }
    }
)

test.register_message_test(
    "Basic report (0x32) should be handled by parent device",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_parent.id, "init" }
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Basic:Report({ value = 0x32 }, { src_channel = 0 })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.switch.switch.on())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.switchLevel.level(50))
      }
    }
)

test.register_message_test(
    "Basic report (0x32) should be handled by child device",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_parent.id, "init" }
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Basic:Report({ value = 0x32 }, { src_channel = 1 })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.switch.switch.on())
      }
    }
)

test.register_message_test(
    "Basic report (0x32) should be handled by child 2 device",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_parent.id, "init" }
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Basic:Report({ value = 0x32 }, { src_channel = 2 })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_2:generate_test_message("main", capabilities.switch.switch.on())
      }
    }
)

test.register_message_test(
    "Basic report (0x32) should be handled by child 3 device",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_parent.id, "init" }
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Basic:Report({ value = 0x32 }, { src_channel = 3 })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_3:generate_test_message("main", capabilities.switch.switch.on())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_3:generate_test_message("main", capabilities.switchLevel.level(50))
      }
    }
)

test.register_message_test(
    "SwitchBinary report (OFF_DISABLE) should be handled by child device",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_parent.id, "init" }
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SwitchBinary:Report({
                current_value = SwitchBinary.value.OFF_DISABLE,
                target_value = SwitchBinary.value.OFF_DISABLE,
                duration = 0
              }, {
                src_channel = 1
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.switch.switch.off())
      }
    }
)

test.register_message_test(
    "SwitchBinary report (OFF_DISABLE) should be handled by child 3 device",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_parent.id, "init" }
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SwitchBinary:Report({
                current_value = SwitchBinary.value.OFF_DISABLE,
                target_value = SwitchBinary.value.OFF_DISABLE,
                duration = 0
              }, {
                src_channel = 3
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_3:generate_test_message("main", capabilities.switch.switch.off())
      }
    }
)

test.register_message_test(
    "SwitchBinary report (ON_ENABLE) should be handled by child device",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_parent.id, "init" }
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SwitchBinary:Report({
                current_value = SwitchBinary.value.ON_ENABLE,
                target_value = SwitchBinary.value.ON_ENABLE,
                duration = 0
              }, {
                src_channel = 1
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.switch.switch.on())
      }
    }
)

test.register_message_test(
    "SwitchBinary report (ON_ENABLE) should be handled by child 3 device",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_parent.id, "init" }
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SwitchBinary:Report({
                current_value = SwitchBinary.value.ON_ENABLE,
                target_value = SwitchBinary.value.ON_ENABLE,
                duration = 0
              }, {
                src_channel = 3
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_3:generate_test_message("main", capabilities.switch.switch.on())
      }
    }
)

test.register_message_test(
    "SwitchMultilevel report (ON_ENABLE) should be handled by child 3 device",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_parent.id, "init" }
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SwitchMultilevel:Report({
                current_value = SwitchBinary.value.ON_ENABLE,
                target_value = SwitchBinary.value.ON_ENABLE,
                duration = 0
              }, {
                src_channel = 3
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_3:generate_test_message("main", capabilities.switch.switch.on())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_3:generate_test_message("main", capabilities.switchLevel.level(100))
      }
    }
)

test.register_message_test(
    "SwitchMultilevel report (OFF_DISABLE) should be handled by child 3 device",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_parent.id, "init" }
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SwitchMultilevel:Report({
                current_value = SwitchBinary.value.OFF_DISABLE,
                target_value = SwitchBinary.value.OFF_DISABLE,
                duration = 0
              }, {
                src_channel = 3
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_3:generate_test_message("main", capabilities.switch.switch.off())
      }
    }
)

test.register_message_test(
    "SwitchMultilevel report (0x32) should be handled by child 3 device",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_parent.id, "init" }
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SwitchMultilevel:Report({
                current_value = 50,
                target_value = 0,
                duration = 0
              }, {
                src_channel = 3
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_3:generate_test_message("main", capabilities.switch.switch.on())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_3:generate_test_message("main", capabilities.switchLevel.level(50))
      }
    }
)

test.register_message_test(
    "Refresh command for parent device should send correct GETs",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_parent.id, "init" }
      },
      {
        channel = "capability",
        direction = "receive",
        message = {
          mock_parent.id,
          { capability = "refresh", command = "refresh", args = {} }
        }
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SwitchMultilevel:Get({}, { dst_channels = {} })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SwitchMultilevel:Get({}, { dst_channels = { 1 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SwitchMultilevel:Get({}, { dst_channels = { 2 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SwitchMultilevel:Get({}, { dst_channels = { 3 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SwitchMultilevel:Get({}, { dst_channels = { 4 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SwitchMultilevel:Get({}, { dst_channels = { 5 } })
        )
      },
    }
)

test.register_message_test(
    "Refresh command for child 1 device should send correct GETs",
    {
      {
        channel = "capability",
        direction = "receive",
        message = {
          mock_child.id,
          { capability = "refresh", command = "refresh", args = {} }
        }
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SwitchBinary:Get({}, { dst_channels = { 1 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            Meter:Get({ scale = Meter.scale.electric_meter.KILOWATT_HOURS }, { dst_channels = { 1 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            Meter:Get({ scale = Meter.scale.electric_meter.WATTS }, { dst_channels = { 1 } })
        )
      }
    },
    {
      inner_block_ordering = "relaxed"
    }
)

test.register_message_test(
    "Refresh command for child 2 device should send correct GETs",
    {
      {
        channel = "capability",
        direction = "receive",
        message = {
          mock_child_2.id,
          { capability = "refresh", command = "refresh", args = {} }
        }
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SwitchBinary:Get({}, { dst_channels = { 2 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            Meter:Get({ scale = Meter.scale.electric_meter.KILOWATT_HOURS }, { dst_channels = { 2 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            Meter:Get({ scale = Meter.scale.electric_meter.WATTS }, { dst_channels = { 2 } })
        )
      }
    },
    {
      inner_block_ordering = "relaxed"
    }
)

test.register_message_test(
    "Refresh command for child 3 device should send correct GETs",
    {
      {
        channel = "capability",
        direction = "receive",
        message = {
          mock_child_3.id,
          { capability = "refresh", command = "refresh", args = {} }
        }
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SwitchMultilevel:Get({}, { dst_channels = { 3 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            Meter:Get({ scale = Meter.scale.electric_meter.KILOWATT_HOURS }, { dst_channels = { 3 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            Meter:Get({ scale = Meter.scale.electric_meter.WATTS }, { dst_channels = { 3 } })
        )
      }
    },
    {
      inner_block_ordering = "relaxed"
    }
)

test.register_message_test(
    "Basic report (child 4) 0x00 should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Basic:Report({
                value = 0x00
              }, {
                src_channel = 4
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_4:generate_test_message("main", capabilities.contactSensor.contact.closed())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_4:generate_test_message("main", capabilities.waterSensor.water.dry())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_4:generate_test_message("main", capabilities.motionSensor.motion.inactive())
      }
    },
    {
      inner_block_ordering = "relaxed"
    }
)

test.register_message_test(
    "Basic report (child 4) 0xFF should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Basic:Report({
                value = 0xFF
              }, {
                src_channel = 4
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_4:generate_test_message("main", capabilities.contactSensor.contact.open())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_4:generate_test_message("main", capabilities.waterSensor.water.wet())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_4:generate_test_message("main", capabilities.motionSensor.motion.active())
      }
    },
    {
      inner_block_ordering = "relaxed"
    }
)

test.register_message_test(
    "SensorBinary report (child 4) DOOR_WINDOW - DETECTED_AN_EVENT should be handled as contact open",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SensorBinary:Report({
                sensor_type = SensorBinary.sensor_type.DOOR_WINDOW,
                sensor_value = SensorBinary.sensor_value.DETECTED_AN_EVENT
              }, {
                src_channel = 4
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_4:generate_test_message("main", capabilities.contactSensor.contact.open())
      }
    }
)

test.register_message_test(
    "SensorBinary report (child 4) DOOR_WINDOW - IDLE should be handled as contact closed",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SensorBinary:Report({
                sensor_type = SensorBinary.sensor_type.DOOR_WINDOW,
                sensor_value = SensorBinary.sensor_value.IDLE
              }, {
                src_channel = 4
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_4:generate_test_message("main", capabilities.contactSensor.contact.closed())
      }
    }
)

test.register_message_test(
    "SensorAlarm report (child 4) GENERAL_PURPOSE_ALARM - ALARM should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SensorAlarm:Report({
                sensor_type = SensorAlarm.sensor_type.GENERAL_PURPOSE_ALARM,
                sensor_state = SensorAlarm.sensor_state.ALARM
              }, {
                src_channel = 4
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_4:generate_test_message("main", capabilities.contactSensor.contact.open())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_4:generate_test_message("main", capabilities.motionSensor.motion.active())
      }
    }
)

test.register_message_test(
    "SensorAlarm report (child 4) GENERAL_PURPOSE_ALARM - NO_ALARM should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SensorAlarm:Report({
                sensor_type = SensorAlarm.sensor_type.GENERAL_PURPOSE_ALARM,
                sensor_state = SensorAlarm.sensor_state.NO_ALARM
              }, {
                src_channel = 4
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_4:generate_test_message("main", capabilities.contactSensor.contact.closed())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_4:generate_test_message("main", capabilities.motionSensor.motion.inactive())
      }
    }
)

test.register_message_test(
    "Notification reports (child 4) for home_security and access_control events (contactSensor) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.HOME_SECURITY,
                event = Notification.event.home_security.INTRUSION_LOCATION_PROVIDED
              }, {
                src_channel = 4
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_4:generate_test_message("main", capabilities.contactSensor.contact.open())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_4:generate_test_message("main", capabilities.motionSensor.motion.active())
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.HOME_SECURITY,
                event = Notification.event.home_security.INTRUSION
              }, {
                src_channel = 4
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_4:generate_test_message("main", capabilities.contactSensor.contact.open())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_4:generate_test_message("main", capabilities.motionSensor.motion.active())
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.HOME_SECURITY,
                event = Notification.event.home_security.STATE_IDLE
              }, {
                src_channel = 4
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_4:generate_test_message("main", capabilities.contactSensor.contact.closed())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_4:generate_test_message("main", capabilities.motionSensor.motion.inactive())
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.ACCESS_CONTROL,
                event = Notification.event.access_control.WINDOW_DOOR_IS_OPEN
              }, {
                src_channel = 4
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_4:generate_test_message("main", capabilities.contactSensor.contact.open())
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.ACCESS_CONTROL,
                event = Notification.event.access_control.WINDOW_DOOR_IS_CLOSED
              }, {
                src_channel = 4
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_4:generate_test_message("main", capabilities.contactSensor.contact.closed())
      }
    }
)

test.register_message_test(
    "Notification reports (child 4) for home_security events (motionSensor) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.HOME_SECURITY,
                event = Notification.event.home_security.INTRUSION_LOCATION_PROVIDED
              }, {
                src_channel = 4
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_4:generate_test_message("main", capabilities.contactSensor.contact.open())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_4:generate_test_message("main", capabilities.motionSensor.motion.active())
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.HOME_SECURITY,
                event = Notification.event.home_security.INTRUSION
              }, {
                src_channel = 4
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_4:generate_test_message("main", capabilities.contactSensor.contact.open())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_4:generate_test_message("main", capabilities.motionSensor.motion.active())
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.HOME_SECURITY,
                event = Notification.event.home_security.MOTION_DETECTION_LOCATION_PROVIDED
              }, {
                src_channel = 4
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_4:generate_test_message("main", capabilities.motionSensor.motion.active())
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.HOME_SECURITY,
                event = Notification.event.home_security.MOTION_DETECTION
              }, {
                src_channel = 4
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_4:generate_test_message("main", capabilities.motionSensor.motion.active())
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.HOME_SECURITY,
                event = Notification.event.home_security.STATE_IDLE
              }, {
                src_channel = 4
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_4:generate_test_message("main", capabilities.contactSensor.contact.closed())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_4:generate_test_message("main", capabilities.motionSensor.motion.inactive())
      }
    }
)

test.register_message_test(
    "Notification reports (child 4) for SMOKE events (smokeDetector) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.SMOKE,
                event = Notification.event.smoke.DETECTED
              }, {
                src_channel = 4
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_4:generate_test_message("main", capabilities.smokeDetector.smoke.detected())
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.SMOKE,
                event = Notification.event.smoke.DETECTED_LOCATION_PROVIDED
              }, {
                src_channel = 4
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_4:generate_test_message("main", capabilities.smokeDetector.smoke.detected())
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.SMOKE,
                event = Notification.event.smoke.ALARM_TEST
              }, {
                src_channel = 4
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_4:generate_test_message("main", capabilities.smokeDetector.smoke.tested())
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.SMOKE,
                event = Notification.event.smoke.STATE_IDLE
              }, {
                src_channel = 4
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_4:generate_test_message("main", capabilities.smokeDetector.smoke.clear())
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.SMOKE,
                event = Notification.event.smoke.ALARM_SILENCED
              }, {
                src_channel = 4
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_4:generate_test_message("main", capabilities.smokeDetector.smoke.clear())
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.SMOKE,
                event = Notification.event.smoke.UNKNOWN_EVENT_STATE
              }, {
                src_channel = 4
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_4:generate_test_message("main", capabilities.smokeDetector.smoke.clear())
      }
    }
)

test.register_message_test(
    "SensorBinary SMOKE report (child 4) DETECTED_AN_EVENT should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SensorBinary:Report({
                sensor_type = SensorBinary.sensor_type.SMOKE,
                sensor_value = SensorBinary.sensor_value.DETECTED_AN_EVENT
              }, {
                src_channel = 4
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_4:generate_test_message("main", capabilities.smokeDetector.smoke.detected())
      }
    }
)

test.register_message_test(
    "SensorBinary SMOKE report (child 4) IDLE should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SensorBinary:Report({
                sensor_type = SensorBinary.sensor_type.SMOKE,
                sensor_value = SensorBinary.sensor_value.IDLE
              }, {
                src_channel = 4
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_4:generate_test_message("main", capabilities.smokeDetector.smoke.clear())
      }
    }
)

test.register_message_test(
    "SensorAlarm SMOKE report (child 4) ALARM should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SensorAlarm:Report({
                sensor_type = SensorAlarm.sensor_type.SMOKE_ALARM,
                sensor_state = SensorAlarm.sensor_state.ALARM
              }, {
                src_channel = 4
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_4:generate_test_message("main", capabilities.smokeDetector.smoke.detected())
      }
    }
)

test.register_message_test(
    "SensorAlarm SMOKE report (child 4) NO_ALARM should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SensorAlarm:Report({
                sensor_type = SensorAlarm.sensor_type.SMOKE_ALARM,
                sensor_state = SensorAlarm.sensor_state.NO_ALARM
              }, {
                src_channel = 4
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_4:generate_test_message("main", capabilities.smokeDetector.smoke.clear())
      }
    }
)

test.register_message_test(
    "Notification reports (child 4) for WATER events (waterSensor) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.WATER,
                event = Notification.event.water.LEAK_DETECTED_LOCATION_PROVIDED
              }, {
                src_channel = 4
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_4:generate_test_message("main", capabilities.waterSensor.water.wet())
      }
    }
)

test.register_message_test(
    "Notification reports (child 4) for WATER events (waterSensor) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.WATER,
                event = Notification.event.water.LEAK_DETECTED
              }, {
                src_channel = 4
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_4:generate_test_message("main", capabilities.waterSensor.water.wet())
      }
    }
)

test.register_message_test(
    "Notification reports (child 4) for WATER events (waterSensor) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.WATER,
                event = Notification.event.water.STATE_IDLE
              }, {
                src_channel = 4
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_4:generate_test_message("main", capabilities.waterSensor.water.dry())
      }
    }
)

test.register_message_test(
    "Notification reports (child 4) for WATER events (waterSensor) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.WATER,
                event = Notification.event.water.UNKNOWN_EVENT_STATE
              }, {
                src_channel = 4
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_4:generate_test_message("main", capabilities.waterSensor.water.dry())
      }
    }
)

test.register_message_test(
    "SensorBinary WATER report (child 4) DETECTED_AN_EVENT should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SensorBinary:Report({
                sensor_type = SensorBinary.sensor_type.WATER,
                sensor_value = SensorBinary.sensor_value.DETECTED_AN_EVENT
              }, {
                src_channel = 4
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_4:generate_test_message("main", capabilities.waterSensor.water.wet())
      }
    }
)

test.register_message_test(
    "SensorBinary WATER report (child 4) IDLE should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SensorBinary:Report({
                sensor_type = SensorBinary.sensor_type.WATER,
                sensor_value = SensorBinary.sensor_value.IDLE
              }, {
                src_channel = 4
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_4:generate_test_message("main", capabilities.waterSensor.water.dry())
      }
    }
)

test.register_message_test(
    "SensorAlarm WATER_LEAK_ALARM report (child 4) ALARM should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SensorAlarm:Report({
                sensor_type = SensorAlarm.sensor_type.WATER_LEAK_ALARM,
                sensor_state = SensorAlarm.sensor_state.ALARM
              }, {
                src_channel = 4
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_4:generate_test_message("main", capabilities.waterSensor.water.wet())
      }
    }
)

test.register_message_test(
    "SensorAlarm WATER_LEAK_ALARM report (child 4) NO_ALARM should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SensorAlarm:Report({
                sensor_type = SensorAlarm.sensor_type.WATER_LEAK_ALARM,
                sensor_state = SensorAlarm.sensor_state.NO_ALARM
              }, {
                src_channel = 4
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_4:generate_test_message("main", capabilities.waterSensor.water.dry())
      }
    }
)

test.register_message_test(
    "SensorMultilevel TEMPERATURE report (child 5) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SensorMultilevel:Report({
                sensor_type = SensorMultilevel.sensor_type.TEMPERATURE,
                sensor_value = 20,
                scale = SensorMultilevel.scale.temperature.CELSIUS
              }, {
                src_channel = 5
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_5:generate_test_message("main", capabilities.temperatureMeasurement.temperature({ value = 20, unit = "C" }))
      }
    }
)

test.register_message_test(
    "SensorMultilevel TEMPERATURE report (child 5) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SensorMultilevel:Report({
                sensor_type = SensorMultilevel.sensor_type.RELATIVE_HUMIDITY,
                sensor_value = 70
              }, {
                src_channel = 5
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_5:generate_test_message("main", capabilities.relativeHumidityMeasurement.humidity({ value = 70 }))
      }
    }
)

test.register_message_test(
    "SensorMultilevel TEMPERATURE report (child 5) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SensorMultilevel:Report({
                sensor_type = SensorMultilevel.sensor_type.LUMINANCE,
                sensor_value = 400,
                scale = SensorMultilevel.scale.luminance.LUX
              }, {
                src_channel = 5
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_5:generate_test_message("main", capabilities.illuminanceMeasurement.illuminance({ value = 400, unit = "lux" }))
      }
    }
)

test.register_message_test(
    "Refresh capability command should refresh device",
    {
      {
        channel = "capability",
        direction = "receive",
        message = {
          mock_child_4.id,
          { capability = "refresh", command = "refresh", args = {} }
        }
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SensorBinary:Get({ sensor_type = SensorBinary.sensor_type.SMOKE }, { dst_channels = { 4 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SensorBinary:Get({ sensor_type = SensorBinary.sensor_type.MOTION }, { dst_channels = { 4 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SensorBinary:Get({ sensor_type = SensorBinary.sensor_type.WATER }, { dst_channels = { 4 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SensorBinary:Get({ sensor_type = SensorBinary.sensor_type.DOOR_WINDOW }, { dst_channels = { 4 } })
        )
      }
    },
    {
      inner_block_ordering = "relaxed"
    }
)

test.register_message_test(
    "Refresh capability command should refresh device",
    {
      {
        channel = "capability",
        direction = "receive",
        message = {
          mock_child_5.id,
          { capability = "refresh", command = "refresh", args = {} }
        }
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SensorMultilevel:Get({
              sensor_type = SensorMultilevel.sensor_type.TEMPERATURE,
              scale = SensorMultilevel.scale.temperature.CELSIUS
            }, {
              dst_channels = { 5 }
            })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SensorMultilevel:Get({
              sensor_type = SensorMultilevel.sensor_type.RELATIVE_HUMIDITY
            }, {
              dst_channels = { 5 }
            })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SensorMultilevel:Get({
              sensor_type = SensorMultilevel.sensor_type.LUMINANCE,
              scale = SensorMultilevel.scale.luminance.LUX
            }, {
              dst_channels = { 5 }
            })
        )
      }
    },
    {
      inner_block_ordering = "relaxed"
    }
)

test.register_message_test(
    "Added lifecycle event for parent device should evoke correct GETs",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_parent.id, "init" }
      },
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_parent.id, "added" }
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            MultiChannel:CapabilityGet({
              end_point = 1
            })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            MultiChannel:CapabilityGet({
              end_point = 2
            })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            MultiChannel:CapabilityGet({
              end_point = 3
            })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            MultiChannel:CapabilityGet({
              end_point = 4
            })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            MultiChannel:CapabilityGet({
              end_point = 5
            })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            MultiChannel:CapabilityGet({
              end_point = 6
            })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SwitchMultilevel:Get({}, { dst_channels = {} })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SwitchMultilevel:Get({}, { dst_channels = { 1 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SwitchMultilevel:Get({}, { dst_channels = { 2 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SwitchMultilevel:Get({}, { dst_channels = { 3 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SwitchMultilevel:Get({}, { dst_channels = { 4 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SwitchMultilevel:Get({}, { dst_channels = { 5 } })
        )
      }
    },
    {
      inner_block_ordering = "relaxed"
    }
)

test.register_message_test(
    "Added lifecycle event for child device should refresh device only",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_child.id, "init" }
      },
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_child.id, "added" }
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SwitchBinary:Get({}, { dst_channels = { 1 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            Meter:Get({ scale = Meter.scale.electric_meter.WATTS }, { dst_channels = { 1 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            Meter:Get({ scale = Meter.scale.electric_meter.KILOWATT_HOURS }, { dst_channels = { 1 } })
        )
      }
    },
    {
      inner_block_ordering = "relaxed"
    }
)

test.register_message_test(
    "MultiChannel capability report should not create device if it has child with ep 1",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              MultiChannel:CapabilityReport({
                end_point = 1,
                generic_device_class = 0x10
              })
          )
        }
      }
    }
)

test.register_coroutine_test(
    "MultiChannel capability report should create device if it doesn't have child with ep 1",
    function()
      test.socket.zwave:__queue_receive({
        base_parent.id,
        MultiChannel:CapabilityReport({
          end_point = 1,
          generic_device_class = 0x10
        })
      })
      base_parent:expect_device_create(
          prepare_metadata(base_parent, 1, "metering-switch")
      )
    end
)

test.register_message_test(
    "MultiChannel capability report should not create device if it has child with ep 3",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              MultiChannel:CapabilityReport({
                end_point = 3,
                generic_device_class = 0x11
              })
          )
        }
      }
    }
)

test.register_coroutine_test(
    "MultiChannel capability report should create device if it doesn't have child with ep 3",
    function()
      test.socket.zwave:__queue_receive({
        base_parent.id,
        MultiChannel:CapabilityReport({
          end_point = 3,
          generic_device_class = 0x11
        })
      })
      base_parent:expect_device_create(
          prepare_metadata(base_parent, 3, "metering-dimmer")
      )
    end
)

test.register_message_test(
    "MultiChannel capability report should not create device if it has child with ep 4",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              MultiChannel:CapabilityReport({
                end_point = 4,
                generic_device_class = 0x20
              })
          )
        }
      }
    }
)

test.register_coroutine_test(
    "MultiChannel capability report should create device if it doesn't have child with ep 4",
    function()
      test.socket.zwave:__queue_receive({
        base_parent.id,
        MultiChannel:CapabilityReport({
          end_point = 4,
          generic_device_class = 0x20
        })
      })
      base_parent:expect_device_create(
          prepare_metadata(base_parent, 4, "generic-sensor")
      )
    end
)

test.register_message_test(
    "MultiChannel capability report should not create device if it has child with ep 5",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              MultiChannel:CapabilityReport({
                end_point = 5,
                generic_device_class = 0x08
              })
          )
        }
      }
    }
)

test.register_coroutine_test(
    "MultiChannel capability report should create device if it doesn't have child with ep 5",
    function()
      test.socket.zwave:__queue_receive({
        base_parent.id,
        MultiChannel:CapabilityReport({
          end_point = 5,
          generic_device_class = 0x08
        })
      })
      base_parent:expect_device_create(
          prepare_metadata(base_parent, 5, "generic-multi-sensor")
      )
    end
)

test.run_registered_tests()