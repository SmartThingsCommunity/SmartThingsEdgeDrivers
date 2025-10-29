-- Copyright 2025 SmartThings
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
local SwitchMultilevel = (require "st.zwave.CommandClass.SwitchMultilevel")({version=4})
local Basic = (require "st.zwave.CommandClass.Basic")({version=1})
local CentralScene = (require "st.zwave.CommandClass.CentralScene")({version=3})
local Association = (require "st.zwave.CommandClass.Association")({version=1})
local SensorMultilevel = (require "st.zwave.CommandClass.SensorMultilevel")({version=7})
local Meter = (require "st.zwave.CommandClass.Meter")({version=3})
local Notification = (require "st.zwave.CommandClass.Notification")({version=3})
local t_utils = require "integration_test.utils"

-- Inovelli VZW32-SN device identifiers
local INOVELLI_MANUFACTURER_ID = 0x031E
local INOVELLI_VZW32_SN_PRODUCT_TYPE = 0x0017
local INOVELLI_VZW32_SN_PRODUCT_ID = 0x0001

-- Device endpoints with supported command classes
local inovelli_vzw32_sn_endpoints = {
  {
    command_classes = {
      {value = zw.SWITCH_BINARY},
      {value = zw.SWITCH_MULTILEVEL},
      {value = zw.BASIC},
      {value = zw.CONFIGURATION},
      {value = zw.CENTRAL_SCENE},
      {value = zw.ASSOCIATION},
      {value = zw.SENSOR_MULTILEVEL},
      {value = zw.METER},
      {value = zw.NOTIFICATION},
    }
  }
}

-- Create mock device
local mock_inovelli_vzw32_sn = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("inovelli-mmwave-dimmer-vzw32-sn.yml"),
  zwave_endpoints = inovelli_vzw32_sn_endpoints,
  zwave_manufacturer_id = INOVELLI_MANUFACTURER_ID,
  zwave_product_type = INOVELLI_VZW32_SN_PRODUCT_TYPE,
  zwave_product_id = INOVELLI_VZW32_SN_PRODUCT_ID
})

local function test_init()
  test.mock_device.add_test_device(mock_inovelli_vzw32_sn)
end
test.set_test_init_function(test_init)

-- Test device initialization
test.register_message_test(
  "Device should initialize properly on added lifecycle event",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_inovelli_vzw32_sn.id, "added" },
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_inovelli_vzw32_sn,
        Association:Set({
          grouping_identifier = 1,
          node_ids = {}, -- Mock hub Z-Wave ID
          payload = "\x01", -- Should contain grouping_identifier = 1
        })
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_inovelli_vzw32_sn,
        SwitchMultilevel:Get({})
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_inovelli_vzw32_sn,
        SensorMultilevel:Get({sensor_type = SensorMultilevel.sensor_type.ILLUMINANCE})
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_inovelli_vzw32_sn,
        Meter:Get({ scale = Meter.scale.electric_meter.WATTS })
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_inovelli_vzw32_sn,
        Meter:Get({ scale = Meter.scale.electric_meter.KILOWATT_HOURS })
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_inovelli_vzw32_sn,
        Notification:Get({notification_type = Notification.notification_type.HOME_SECURITY, event = Notification.event.home_security.MOTION_DETECTION})
      )
    },
  },
  {
    inner_block_ordering = "relaxed"
  }
)

-- Test switch on command
test.register_coroutine_test(
  "Switch on command should send Basic Set with ON value",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(3, "oneshot")
    test.socket.capability:__queue_receive({
      mock_inovelli_vzw32_sn.id,
      { capability = "switch", command = "on", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_inovelli_vzw32_sn,
        Basic:Set({ value = SwitchBinary.value.ON_ENABLE })
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(3)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_inovelli_vzw32_sn,
        SwitchMultilevel:Get({})
      )
    )
  end
)

-- Test switch off command
test.register_coroutine_test(
  "Switch off command should send Basic Set with OFF value",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(3, "oneshot")
    test.socket.capability:__queue_receive({
      mock_inovelli_vzw32_sn.id,
      { capability = "switch", command = "off", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_inovelli_vzw32_sn,
        Basic:Set({ value = SwitchBinary.value.OFF_DISABLE })
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(3)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_inovelli_vzw32_sn,
        SwitchMultilevel:Get({})
      )
    )
  end
)

-- Test switch level command
test.register_coroutine_test(
  "Switch level command should send SwitchMultilevel Set",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(3, "oneshot")

    test.socket.capability:__queue_receive({
      mock_inovelli_vzw32_sn.id,
      { capability = "switchLevel", command = "setLevel", args = { 50 } }
    })

    local expected_command = SwitchMultilevel:Set({ value = 50, duration = "default" })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_inovelli_vzw32_sn,
        expected_command
      )
    )

    test.wait_for_events()
    test.mock_time.advance_time(3)

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_inovelli_vzw32_sn,
        SwitchMultilevel:Get({})
      )
    )
  end
)

-- Test central scene notifications
test.register_message_test(
  "Central scene notification should emit button events",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_inovelli_vzw32_sn.id, zw_test_utils.zwave_test_build_receive_command(CentralScene:Notification({
        scene_number = 1,
        key_attributes=CentralScene.key_attributes.KEY_PRESSED_1_TIME
      })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_inovelli_vzw32_sn:generate_test_message("button1", capabilities.button.button.pushed({
        state_change = true
      }))
    },
  },
  {
    inner_block_ordering = "relaxed"
  }
)

-- Test central scene notifications - button2 pressed 4 times
test.register_message_test(
  "Central scene notification button2 pressed 4 times should emit button events",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_inovelli_vzw32_sn.id, zw_test_utils.zwave_test_build_receive_command(CentralScene:Notification({
        scene_number = 2,
        key_attributes=CentralScene.key_attributes.KEY_PRESSED_4_TIMES
      })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_inovelli_vzw32_sn:generate_test_message("button2", capabilities.button.button.pushed_4x({
        state_change = true
      }))
    },
  },
  {
    inner_block_ordering = "relaxed"
  }
)

-- Test refresh capability
test.register_message_test(
  "Refresh capability should request switch level",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_inovelli_vzw32_sn.id,
        { capability = "refresh", command = "refresh", args = {} }
      }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_inovelli_vzw32_sn,
        SwitchMultilevel:Get({})
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_inovelli_vzw32_sn,
        SensorMultilevel:Get({sensor_type = SensorMultilevel.sensor_type.ILLUMINANCE})
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_inovelli_vzw32_sn,
        Meter:Get({ scale = Meter.scale.electric_meter.WATTS })
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_inovelli_vzw32_sn,
        Meter:Get({ scale = Meter.scale.electric_meter.KILOWATT_HOURS })
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_inovelli_vzw32_sn,
        Notification:Get({notification_type = Notification.notification_type.HOME_SECURITY, event = Notification.event.home_security.MOTION_DETECTION})
      )
    },
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.run_registered_tests()
