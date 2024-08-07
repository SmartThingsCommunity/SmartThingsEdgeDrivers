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
local t_utils = require "integration_test.utils"
local zw = require "st.zwave"
local zw_test_utils = require "integration_test.zwave_test_utils"

local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({ version=1 })
local Basic = (require "st.zwave.CommandClass.Basic")({ version=1 })
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version=4 })
local Meter = (require "st.zwave.CommandClass.Meter")({ version = 3 })

local LAST_REPORT_TIME = "LAST_REPORT_TIME"

local aeotec_smart_switch_7_endpoints = {
  {
    command_classes = {
      { value = zw.BASIC },
      { value = zw.SWITCH_BINARY },
      { value = zw.METER }
    }
  }
}

local mock_device = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("aeotec-smart-switch-7-us.yml"),
  zwave_endpoints = aeotec_smart_switch_7_endpoints,
  zwave_manufacturer_id = 0x0371,
  zwave_product_type = 0x0103,
  zwave_product_id = 0x0017
})

local function test_init()
  test.mock_device.add_test_device(mock_device)
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Device should be configured",
  function()
    test.socket.zwave:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({mock_device.id, "doConfigure"})
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_device,
      Configuration:Set({
        parameter_number = 21,
        size = 2,
        configuration_value = 2
      })
    ))
    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)

test.register_coroutine_test(
  "Device should use Basic SETs and GETs despite supporting Switch Multilevel (on)",
  function ()
    test.timer.__create_and_queue_test_time_advance_timer(3, "oneshot")
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "switch", command = "on", args = {}}
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Basic:Set({
          value = 0xFF
        })
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(3)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchBinary:Get({})
      )
    )
  end
)

test.register_coroutine_test(
  "Device should use Basic SETs and GETs despite supporting Switch Multilevel (off)",
  function ()
    test.timer.__create_and_queue_test_time_advance_timer(3, "oneshot")
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "switch", command = "off", args = {}}
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Basic:Set({
          value = 0x00
        })
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(3)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchBinary:Get({})
      )
    )
  end
)

test.register_message_test(
  "Power meter report should be handled by main component",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Meter:Report(
        {
          scale = Meter.scale.electric_meter.WATTS,
          meter_value = 55
        })
      )}
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.powerMeter.power({ value = 55, unit = "W" }))
    }
  }
)

test.register_message_test(
  "Energy meter report should be handled by main component",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Meter:Report(
        {
          scale = Meter.scale.electric_meter.KILOWATT_HOURS,
          meter_value = 5
        })
      )}
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.energyMeter.energy({ value = 5, unit = "kWh" }))
    }
  }
)

test.register_coroutine_test(
  "Report consumption and power consumption report after 15 minutes", function()

    local current_time = os.time() - 60 * 20
    mock_device:set_field(LAST_REPORT_TIME, current_time)

    test.socket.zwave:__queue_receive(
      {
        mock_device.id,
        zw_test_utils.zwave_test_build_receive_command(Meter:Report(
        {
          scale = Meter.scale.electric_meter.KILOWATT_HOURS,
          meter_value = 5
        }))
      }
    )

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.energyMeter.energy({ value = 5, unit = "kWh" }))
    )

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.powerConsumptionReport.powerConsumption({ deltaEnergy = 0.0, energy = 5000 }))
    )
  end
)

test.run_registered_tests()
