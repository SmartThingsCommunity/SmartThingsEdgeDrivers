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
local Notification = (require "st.zwave.CommandClass.Notification")({ version = 3 })

local glentronics_water_leak_sensor_profile = {
  components = {
    main = {
      capabilities = {
        [capabilities.waterSensor.ID] = { id = capabilities.waterSensor.ID },
        [capabilities.battery.ID] = { id = capabilities.battery.ID },
        [capabilities.powerSource.ID] = { id = capabilities.powerSource.ID },
        [capabilities.refresh.ID] = { id = capabilities.refresh.ID }
      },
      id = "main"
    }
  }
}

local sensor_endpoints = {
  {
    command_classes =
    {
      {value = zw.NOTIFICATION}
    }
  }
}

local mock_device = test.mock_device.build_test_zwave_device({
  profile = glentronics_water_leak_sensor_profile,
  zwave_endpoints = sensor_endpoints,
  zwave_manufacturer_id = 0x0084,
  zwave_product_type = 0x0093,
  zwave_product_id = 0x0114,
})

local function test_init()
  test.mock_device.add_test_device(mock_device)
end

test.set_test_init_function(test_init)

test.register_message_test(
  "device_added should be handled",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = {mock_device.id, "added"}
    },
    -- {
    --   channel = "capability",
    --   direction = "send",
    --   message = mock_device:generate_test_message("main", capabilities.battery.battery(100))
    -- },
    -- {
    --   channel = "capability",
    --   direction = "send",
    --   message = mock_device:generate_test_message("main", capabilities.waterSensor.water.dry())
    -- },
    -- {
    --   channel = "capability",
    --   direction = "send",
    --   message = mock_device:generate_test_message("main", capabilities.powerSource.powerSource.mains())
    -- }
  }
)

test.register_message_test(
  "Notification report AC_MAINS_DISCONNECTED event should be handled as powerSource battery",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(
        Notification:Report(
        {
          notification_type = Notification.notification_type.POWER_MANAGEMENT,
          event = Notification.event.power_management.AC_MAINS_DISCONNECTED
        }))
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.powerSource.powerSource.battery())
    }
  }
)

test.register_message_test(
  "Notification report AC_MAINS_RE_CONNECTED event should be handled as powerSource mains",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(
        Notification:Report(
        {
          notification_type = Notification.notification_type.POWER_MANAGEMENT,
          event = Notification.event.power_management.AC_MAINS_RE_CONNECTED
        }))
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.powerSource.powerSource.mains())
    }
  }
)

test.register_message_test(
  "Notification report REPLACE_BATTERY_NOW event should be handled as battery(1)",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(
        Notification:Report(
        {
          notification_type = Notification.notification_type.POWER_MANAGEMENT,
          event = Notification.event.power_management.REPLACE_BATTERY_NOW
        }))
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.battery.battery(1))
    }
  }
)

test.register_message_test(
  "Notification report REPLACE_BATTERY_NOW event should be handled as battery(1)",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(
        Notification:Report(
        {
          notification_type = Notification.notification_type.POWER_MANAGEMENT,
          event = Notification.event.power_management.BATTERY_IS_FULLY_CHARGED
        }))
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.battery.battery(100))
    }
  }
)

test.register_message_test(
  "Notification report HARDWARE_FAILURE_MANUFACTURER_PROPRIETARY_FAILURE_CODE_PROVIDED event should be handled as battery(1)",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(
        Notification:Report(
        {
          notification_type = Notification.notification_type.SYSTEM,
          event = Notification.event.system.HARDWARE_FAILURE_MANUFACTURER_PROPRIETARY_FAILURE_CODE_PROVIDED,
          event_parameter = string.char(tonumber("0", 16))
        }))
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.waterSensor.water.dry())
    }
  }
)

test.register_message_test(
  "Notification report HARDWARE_FAILURE_MANUFACTURER_PROPRIETARY_FAILURE_CODE_PROVIDED event should be handled as battery(1)",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(
        Notification:Report(
        {
          notification_type = Notification.notification_type.SYSTEM,
          event = Notification.event.system.HARDWARE_FAILURE_MANUFACTURER_PROPRIETARY_FAILURE_CODE_PROVIDED,
          event_parameter = string.char(tonumber("2", 16))
        }))
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.waterSensor.water.wet())
    }
  }
)


test.run_registered_tests()
