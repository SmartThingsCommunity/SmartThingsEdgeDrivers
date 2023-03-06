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
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({ version = 2 })
local Meter = (require "st.zwave.CommandClass.Meter")({ version = 3 })
local Configuration = (require "st.zwave.CommandClass.Configuration")({version=1})
local t_utils = require "integration_test.utils"

-- supported comand classes
local sensor_endpoints = {
  {
    command_classes = {
      {value = zw.METER},
      {value = zw.SWITCH_BINARY},
    }
  },
  {
    command_classes = {
      {value = zw.METER},
    }
  }
}

local mock_device = test.mock_device.build_test_zwave_device({
    profile = t_utils.get_profile_definition("smartplug-1.yml"),
    zwave_endpoints = sensor_endpoints,
    zwave_manufacturer_id = 0x010F,
    zwave_product_type = 0x1401,
    zwave_product_id = 0x1001
})

local function  test_init()
  test.mock_device.add_test_device(mock_device)
end
test.set_test_init_function(test_init)

test.register_message_test(
  "Switch Binary report ON_ENABLE should be handled by main componet",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_device.id, "init" }
    },
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
        zw_test_utils.zwave_test_build_receive_command(
          SwitchBinary:Report({current_value=SwitchBinary.value.ON_ENABLE})
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switch.switch.on())
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Meter:Get({scale = Meter.scale.electric_meter.WATTS}, {dst_channels = {1}})
      )
    },
  }
)

test.register_message_test(
  "Switch Binary report OFF_DISABLE should be handled by main componet",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_device.id, "init" }
    },
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
        zw_test_utils.zwave_test_build_receive_command(
          SwitchBinary:Report({current_value=SwitchBinary.value.OFF_DISABLE})
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switch.switch.off())
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Meter:Get({scale = Meter.scale.electric_meter.WATTS}, {dst_channels = {1}})
      )
    },
  }
)

test.register_message_test(
  "Power meter report should be handled by main component",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_device.id, "init" }
    },
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Meter:Report(
        {
          scale = Meter.scale.electric_meter.WATTS,
          meter_value = 55
        },
        {
          encap = zw.ENCAP.AUTO,
          src_channel = 1,
          dst_channels={}
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
  "Power meter report should be handled by smartplug1 component",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_device.id, "init" }
    },
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Meter:Report(
        {
          scale = Meter.scale.electric_meter.WATTS,
          meter_value = 89
        },
        {
          encap = zw.ENCAP.AUTO,
          src_channel = 2,
          dst_channels={}
        })
      )}
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("smartplug1",  capabilities.powerMeter.power({ value = 89, unit = "W" }))
    }
  }
)

test.register_message_test(
  "Energy meter report should be handled by main component",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_device.id, "init" }
    },
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Meter:Report(
        {
          scale = Meter.scale.electric_meter.KILOWATT_HOURS,
          meter_value = 5
        },
        {
          encap = zw.ENCAP.AUTO,
          src_channel = 1,
          dst_channels={}
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

test.register_message_test(
  "Energy meter report should be handled by smartplug1 component",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_device.id, "init" }
    },
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Meter:Report(
        {
          scale = Meter.scale.electric_meter.KILOWATT_HOURS,
          meter_value = 5
        },
        {
          encap = zw.ENCAP.AUTO,
          src_channel = 2,
          dst_channels={}
        })
      )}
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("smartplug1",  capabilities.energyMeter.energy({ value = 5, unit = "kWh" }))
    }
  }
)

test.register_coroutine_test(
  "Turning device on should send appropriate meter gets",
  function()
    test.socket.capability:__queue_receive({ mock_device.id, { capability = "switch", component = "main", command = "on", args = {} } })
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_device,
      SwitchBinary:Set({target_value=0xFF},{dst_channels={1}})
    ))
  end
)

test.register_coroutine_test(
    "infoChanged() should send the SET command for Configuation value",
    function()
      test.socket.zwave:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle():__queue_receive({mock_device.id, "init"})
      test.socket.device_lifecycle():__queue_receive(mock_device:generate_info_changed(
          {
              preferences = {
                restoreState = 1,
                overloadSafety = 500,
                standardPowerReports = 50,
                energyReportingThreshold = 250,
                periodicPowerReporting = 6000,
                periodicReports = 5000,
                ringColorOn = 4,
                ringColorOff = 5
              }
          }
      ))

      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_device,
              Configuration:Set({parameter_number=2, size=1, configuration_value=1})
          )
      )

      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_device,
              Configuration:Set({parameter_number=3, size=2, configuration_value=500})
          )
      )

      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_device,
              Configuration:Set({parameter_number=11, size=1, configuration_value=50})
          )
      )

      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_device,
              Configuration:Set({parameter_number=12, size=2, configuration_value=250})
          )
      )

      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_device,
              Configuration:Set({parameter_number=13, size=2, configuration_value=6000})
          )
      )

      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_device,
              Configuration:Set({parameter_number=14, size=2, configuration_value=5000})
          )
      )

      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_device,
              Configuration:Set({parameter_number=41, size=1, configuration_value=4})
          )
      )

      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_device,
              Configuration:Set({parameter_number=42, size=1, configuration_value=5})
          )
      )

    end
)

test.run_registered_tests()
