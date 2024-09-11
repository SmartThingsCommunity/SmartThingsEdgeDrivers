-- Copyright 2023 SmartThings
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

local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({ version = 2 })
local Meter = (require "st.zwave.CommandClass.Meter")({ version = 3 })
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version = 4 })

local LAST_REPORT_TIME = "LAST_REPORT_TIME"

local aeotec_smart_switch_endpoints = {
  {
    command_classes = {
      { value = zw.SWITCH_BINARY },
      { value = zw.METER },
      { value = zw.CONFIGURATION }
    }
  }
}

local mock_device = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("aeotec-heavy-duty.yml"),
  zwave_endpoints = aeotec_smart_switch_endpoints,
  zwave_manufacturer_id = 0x0086,
  zwave_product_type = 0x0003,
  zwave_product_id = 0x004E
})

local function test_init()
  test.mock_device.add_test_device(mock_device)
end

test.set_test_init_function(test_init)

test.register_message_test(
  "Power meter report should be ignored",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Meter:Report({
        scale = Meter.scale.electric_meter.WATTS,
        meter_value = 27
      })
      ) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",
        capabilities.powerMeter.power({ value = 27, unit = "W" }))
    }
  }
)

test.register_message_test(
  "Energy meter report should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Meter:Report({
        scale = Meter.scale.electric_meter.KILOWATT_HOURS,
        meter_value = 5
      })
      ) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",
        capabilities.energyMeter.energy({ value = 5, unit = "kWh" }))
    }
  }
)

test.register_message_test(
  "Refresh shall include only energy Meter:Get()",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "refresh", command = "refresh", args = {} }
      }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchBinary:Get({})
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Meter:Get({ scale = Meter.scale.electric_meter.WATTS })
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Meter:Get({ scale = Meter.scale.electric_meter.KILOWATT_HOURS })
      )
    }
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.register_coroutine_test(
  "Energy meter reset should send a reset command",
  function()
    test.socket.capability:__queue_receive({ mock_device.id, { capability = "energyMeter", component = "main", command = "resetEnergyMeter", args = {} } })
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(mock_device, Meter:Reset({})))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(mock_device,
      Meter:Get({ scale = Meter.scale.electric_meter.KILOWATT_HOURS })))
  end
)

test.register_coroutine_test(
  "Report consumption and power consumption report after 15 minutes", function()
    -- set time to trigger power consumption report
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

test.register_coroutine_test(
  "Setting switch (binary) off should generate correct zwave messages",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        { capability = "switch", command = "off", args = {} }
      }
    )
    mock_device:expect_native_cmd_handler_registration("switch", "off")

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchBinary:Set({
          target_value = SwitchBinary.value.OFF_ENABLE,
        })
      )
    )
  end
)

test.register_coroutine_test(
  "Setting switch (binary) on should generate correct zwave messages",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        { capability = "switch", command = "on", args = {} }
      }
    )
    mock_device:expect_native_cmd_handler_registration("switch", "on")

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchBinary:Set({
          target_value = SwitchBinary.value.ON_ENABLE,
        })
      )
    )
  end
)

test.register_coroutine_test(
  "Handle preference: overloadProtection in infoChanged",
  function()
    test.socket.device_lifecycle:__queue_receive(
      mock_device:generate_info_changed({
        preferences = {
          overloadProtection = 1
        }
      })
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Configuration:Set({
          parameter_number = 3,
          configuration_value = 1,
          size = 1
        })
      )
    )
  end
)

test.register_coroutine_test(
  "Handle preference: ledAfterPower in infoChanged",
  function()
    test.socket.device_lifecycle:__queue_receive(
      mock_device:generate_info_changed({
        preferences = {
          ledAfterPower = 1
        }
      })
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Configuration:Set({
          parameter_number = 20,
          configuration_value = 1,
          size = 1
        })
      )
    )
  end
)

test.register_coroutine_test(
  "Handle preference: autoReportType in infoChanged",
  function()
    test.socket.device_lifecycle:__queue_receive(
      mock_device:generate_info_changed({
        preferences = {
          autoReportType = 1
        }
      })
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Configuration:Set({
          parameter_number = 80,
          configuration_value = 1,
          size = 1
        })
      )
    )
  end
)

test.register_coroutine_test(
  "Handle preference: powerThreshold in infoChanged",
  function()
    test.socket.device_lifecycle:__queue_receive(
      mock_device:generate_info_changed({
        preferences = {
          powerThreshold = 1
        }
      })
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Configuration:Set({
          parameter_number = 90,
          configuration_value = 1,
          size = 1
        })
      )
    )
  end
)

test.register_coroutine_test(
  "Handle preference: group1Sensors in infoChanged",
  function()
    test.socket.device_lifecycle:__queue_receive(
      mock_device:generate_info_changed({
        preferences = {
          group1Sensors = 13
        }
      })
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Configuration:Set({
          parameter_number = 101,
          configuration_value = 13,
          size = 4
        })
      )
    )
  end
)

test.register_coroutine_test(
  "Handle preference: group2Sensors in infoChanged",
  function()
    test.socket.device_lifecycle:__queue_receive(
      mock_device:generate_info_changed({
        preferences = {
          group2Sensors = 5
        }
      })
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Configuration:Set({
          parameter_number = 102,
          configuration_value = 5,
          size = 4
        })
      )
    )
  end
)

test.register_coroutine_test(
  "Handle preference: group3Sensors in infoChanged",
  function()
    test.socket.device_lifecycle:__queue_receive(
      mock_device:generate_info_changed({
        preferences = {
          group3Sensors = 5
        }
      })
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Configuration:Set({
          parameter_number = 103,
          configuration_value = 5,
          size = 4
        })
      )
    )
  end
)

test.register_coroutine_test(
  "Handle preference: group1Time in infoChanged",
  function()
    test.socket.device_lifecycle:__queue_receive(
      mock_device:generate_info_changed({
        preferences = {
          group1Time = 400
        }
      })
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Configuration:Set({
          parameter_number = 111,
          configuration_value = 400,
          size = 4
        })
      )
    )
  end
)

test.register_coroutine_test(
  "Handle preference: group2Time in infoChanged",
  function()
    test.socket.device_lifecycle:__queue_receive(
      mock_device:generate_info_changed({
        preferences = {
          group2Time = 3500
        }
      })
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Configuration:Set({
          parameter_number = 112,
          configuration_value = 3500,
          size = 4
        })
      )
    )
  end
)

test.register_coroutine_test(
  "Handle preference: group3Time in infoChanged",
  function()
    test.socket.device_lifecycle:__queue_receive(
      mock_device:generate_info_changed({
        preferences = {
          group3Time = 3500
        }
      })
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Configuration:Set({
          parameter_number = 113,
          configuration_value = 3500,
          size = 4
        })
      )
    )
  end
)

test.register_coroutine_test(
  "Handle preference: group3Sensors in infoChanged",
  function()
    test.socket.device_lifecycle:__queue_receive(
      mock_device:generate_info_changed({
        preferences = {
          group3Sensors = 5
        }
      })
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Configuration:Set({
          parameter_number = 103,
          configuration_value = 5,
          size = 4
        })
      )
    )
  end
)

test.run_registered_tests()