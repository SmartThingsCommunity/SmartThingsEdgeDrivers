-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local test = require "integration_test"
local capabilities = require "st.capabilities"
local constants = require "st.zwave.constants"
local zw_test_utils = require "integration_test.zwave_test_utils"
local cc = require "st.zwave.CommandClass"
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version=4 })
local SwitchColor = (require "st.zwave.CommandClass.SwitchColor")({ version=3 })
local SwitchMultilevel = (require "st.zwave.CommandClass.SwitchMultilevel")({ version=4 })
local t_utils = require "integration_test.utils"

local WARM_WHITE_CONFIG = 0x51
local COLD_WHITE_CONFIG = 0x52

-- supported comand classes
local zwave_bulb_endpoints = {
  {
    command_classes = {
      {value = cc.SWITCH_MULTILEVEL},
      {value = cc.SWITCH_COLOR}
    }
  }
}

local mock_aeotec_bulb = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("rgbw-bulb.yml"),
  zwave_endpoints = zwave_bulb_endpoints,
  zwave_manufacturer_id = 0x0371, -- Aeotec
  zwave_product_type = 0x0103,
  zwave_product_id = 0x0002,
})

local function test_init()
  test.mock_device.add_test_device(mock_aeotec_bulb)
end
test.set_test_init_function(test_init)

test.register_message_test(
  "Refresh capability refresh commands should evoke Z-Wave GETs to bootstrap state",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_aeotec_bulb.id, "added" }
    },
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_aeotec_bulb.id,
        { capability = "refresh", command = "refresh", args = {} }
      }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_aeotec_bulb,
        SwitchMultilevel:Get({})
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_aeotec_bulb,
        SwitchColor:Get({ color_component_id=SwitchColor.color_component_id.RED })
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_aeotec_bulb,
        SwitchColor:Get({ color_component_id=SwitchColor.color_component_id.GREEN })
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_aeotec_bulb,
        SwitchColor:Get({ color_component_id=SwitchColor.color_component_id.BLUE })
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_aeotec_bulb,
        Configuration:Get({ parameter_number=WARM_WHITE_CONFIG })
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_aeotec_bulb,
        Configuration:Get({ parameter_number=COLD_WHITE_CONFIG })
      )
    }
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.register_coroutine_test(
  "Color Tempurature capability set commands should evoke Aeotec-specific Z-Wave configuration SETs and GETs",
  function()
    local temp = math.random(2700, 6500)
    local ww = temp < 5000 and 255 or 0
    local cw = temp >= 5000 and 255 or 0
    local parameter_number = temp < 5000 and WARM_WHITE_CONFIG or COLD_WHITE_CONFIG
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_aeotec_bulb.id,
      {
        capability = "colorTemperature",
        command = "setColorTemperature",
        args = { temp }
      }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_aeotec_bulb,
        Configuration:Set({
          parameter_number=parameter_number,
          configuration_value=temp
        })
      )
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_aeotec_bulb,
        SwitchColor:Set({
          color_components = {
            { color_component_id = SwitchColor.color_component_id.RED, value = 0 },
            { color_component_id = SwitchColor.color_component_id.GREEN, value = 0 },
            { color_component_id = SwitchColor.color_component_id.BLUE, value = 0 },
            { color_component_id = SwitchColor.color_component_id.WARM_WHITE, value = ww },
            { color_component_id = SwitchColor.color_component_id.COLD_WHITE, value = cw },
          },
          duration = constants.DEFAULT_DIMMING_DURATION
        })
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_aeotec_bulb,
        Configuration:Get({ parameter_number=parameter_number })
      )
    )
  end
)

do
  local temp = math.random(2700, 6500)
  test.register_message_test(
    "Z-Wave Configuration reports with Aeotec-specific white-color temperature parameters should evoke Color Temperature capability events",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_aeotec_bulb.id,
          zw_test_utils.zwave_test_build_receive_command(
            Configuration:Report({
              parameter_number = temp < 5000 and WARM_WHITE_CONFIG or COLD_WHITE_CONFIG,
              configuration_value = temp,
            })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_aeotec_bulb:generate_test_message("main", capabilities.colorTemperature.colorTemperature(temp))
      }
    }
  )
end

test.run_registered_tests()
