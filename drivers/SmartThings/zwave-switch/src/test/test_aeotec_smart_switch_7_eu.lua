-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"
local zw = require "st.zwave"
local zw_test_utils = require "integration_test.zwave_test_utils"

local utils = require "st.utils"

local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({ version=1 })
local Basic = (require "st.zwave.CommandClass.Basic")({ version=1 })
local SwitchColor = (require "st.zwave.CommandClass.SwitchColor")({ version=3 })
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
  profile = t_utils.get_profile_definition("aeotec-smart-switch-7-eu.yml"),
  zwave_endpoints = aeotec_smart_switch_7_endpoints,
  zwave_manufacturer_id = 0x0371,
  zwave_product_type = 0x0003,
  zwave_product_id = 0x00AF
})

local function test_init()
  test.mock_device.add_test_device(mock_device)
end

test.set_test_init_function(test_init)

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
  end,
  {
     min_api_version = 19
  }
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
  end,
  {
     min_api_version = 19
  }
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
  },
  {
     min_api_version = 19
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
  },
  {
     min_api_version = 19
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
  end,
  {
     min_api_version = 19
  }
)

do
  local hue = math.random(0, 100)
  local sat = math.random(0, 100)
  local r, g, b = utils.hsl_to_rgb(hue, sat)
  test.register_coroutine_test(
    "Color Control capability setColor commands should evoke the correct Z-Wave SETs and GETs",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.capability:__queue_receive({
        mock_device.id,
        {
          capability = "colorControl",
          command = "setColor",
          args = {
            {
              hue = hue,
              saturation = sat
            }
          }
        }
      })
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_device,
          SwitchColor:Set({
            color_components = {
              { color_component_id = SwitchColor.color_component_id.RED, value = r },
              { color_component_id = SwitchColor.color_component_id.GREEN, value = g },
              { color_component_id = SwitchColor.color_component_id.BLUE, value = b },
            }
          })
        )
      )
      test.wait_for_events()
      test.mock_time.advance_time(1)
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_device,
          SwitchColor:Get({ color_component_id=SwitchColor.color_component_id.RED })
        )
      )
    end,
    {
       min_api_version = 19
    }

  )
end

test.run_registered_tests()
