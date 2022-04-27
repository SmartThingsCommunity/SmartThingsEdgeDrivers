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
local t_utils = require "integration_test.utils"

local meter_endpoints = {
  {
    command_classes = {
      {value = zw.METER}
    }
  }
}


local mock_meter = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("base-electric-meter.yml"),
  zwave_endpoints = meter_endpoints
})


local function test_init()
  test.mock_device.add_test_device(mock_meter)
end
test.set_test_init_function(test_init)

test.register_message_test(
    "Power meter report should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_meter.id, zw_test_utils.zwave_test_build_receive_command(Meter:Report({
          scale = Meter.scale.electric_meter.WATTS,
          meter_value = 27})
        )}
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_meter:generate_test_message("main", capabilities.powerMeter.power({ value = 27, unit = "W" }))
      }
    }
)

test.register_message_test(
    "Energy meter report should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_meter.id, zw_test_utils.zwave_test_build_receive_command(Meter:Report({
          scale = Meter.scale.electric_meter.KILOWATT_HOURS,
          meter_value = 5})
        )}
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_meter:generate_test_message("main", capabilities.energyMeter.energy({ value = 5, unit = "kWh" }))
      }
    }
)

test.register_message_test(
    "Device should be polled at inclusion",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_meter.id, "added" },
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
          mock_meter,
          Meter:Get({scale = Meter.scale.electric_meter.WATTS})
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
          mock_meter,
          Meter:Get({scale = Meter.scale.electric_meter.KILOWATT_HOURS})
        )
      },
    },
    {
      inner_block_ordering = "relaxed"
    }
)

test.run_registered_tests()
