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
local t_utils = require "integration_test.utils"

local metering_switch_endpoints = {
  {
    command_classes = {
      { value = zw.NOTIFICATION },
      { value = zw.METER },
      { value = zw.SWITCH_BINARY }
    }
  }
}

local mock_metering_switch = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("smartplug-switch-power-energy.yml"),
  zwave_endpoints = metering_switch_endpoints,
  zwave_manufacturer_id = 0x018C,
  zwave_product_type = 0x0042,
  zwave_product_id = 0x0005
})

local function test_init()
  test.mock_device.add_test_device(mock_metering_switch)
end
test.set_test_init_function(test_init)

test.register_message_test(
  "Notification report AC_MAINS_DISCONNECTED event should be handled as switch off",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_metering_switch.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
        notification_type = Notification.notification_type.POWER_MANAGEMENT,
        event = Notification.event.power_management.AC_MAINS_DISCONNECTED,
      })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_metering_switch:generate_test_message("main", capabilities.switch.switch.off())
    }
  }
)

test.register_message_test(
  "Notification report AC_MAINS_RE_CONNECTED event should be handled as switch on",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_metering_switch.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
        notification_type = Notification.notification_type.POWER_MANAGEMENT,
        event = Notification.event.power_management.AC_MAINS_RE_CONNECTED,
      })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_metering_switch:generate_test_message("main", capabilities.switch.switch.on())
    }
  }
)

test.run_registered_tests()
