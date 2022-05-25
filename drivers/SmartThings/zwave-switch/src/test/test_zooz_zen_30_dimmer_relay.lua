local test = require "integration_test"
local test_utils = require "integration_test.utils"
local capabilities = require "st.capabilities"
local constants = require "st.zwave.constants"
local zw = require "st.zwave"
local zw_test_utils = require "integration_test.zwave_test_utils"
local SwitchMultilevel = (require "st.zwave.CommandClass.SwitchMultilevel")({ version = 4 })
local CentralScene = (require "st.zwave.CommandClass.CentralScene")({version=1})
local Meter = (require "st.zwave.CommandClass.Meter")({version=3})

local zooz_zen_30_dimmer_relay_endpoints = {
  {
    command_classes = {
      { value = zw.BASIC },
      { value = zw.SWITCH_MULTILEVEL },
      { value = zw.METER },
      { value = zw.CENTRAL_SCENE }
    }
  }
}

local mock_zooz_zen_30_dimmer_relay = test.mock_device.build_test_zwave_device({
  profile = test_utils.get_profile_definition("zooz-zen-30-dimmer-relay.yml"),
  zwave_endpoints = zooz_zen_30_dimmer_relay_endpoints,
  zwave_manufacturer_id = 0x027A,
  zwave_product_type = 0xA000,
  zwave_product_id = 0xA008
})

local function test_init()
  test.mock_device.add_test_device(mock_zooz_zen_30_dimmer_relay)
end
test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Switch capability off commands should evoke the correct Z-Wave SETs and GETs",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_zooz_zen_30_dimmer_relay.id,
      { capability = "switch", command = "off", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_zooz_zen_30_dimmer_relay,
        SwitchMultilevel:Set({
          value = SwitchMultilevel.value.OFF_DISABLE,
          duration = constants.DEFAULT_DIMMING_DURATION
        })
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_zooz_zen_30_dimmer_relay,
        SwitchMultilevel:Get({})
      )
    )
  end
)

test.register_coroutine_test(
  "Switch capability on commands should evoke the correct Z-Wave SETs and GETs",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_zooz_zen_30_dimmer_relay.id,
      { capability = "switch", command = "on", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_zooz_zen_30_dimmer_relay,
        SwitchMultilevel:Set({
          value = SwitchMultilevel.value.ON_ENABLE,
          duration = constants.DEFAULT_DIMMING_DURATION
        })
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_zooz_zen_30_dimmer_relay,
        SwitchMultilevel:Get({})
      )
    )
  end
)

test.register_message_test(
  "Z-Wave SwitchMultilevel reports with value-off should evoke Switch capability off events",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_zooz_zen_30_dimmer_relay.id,
        zw_test_utils.zwave_test_build_receive_command(
          SwitchMultilevel:Report({
            current_value = 0,
            target_value = SwitchMultilevel.value.OFF_DISABLE,
            duration = 0
          })
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_zooz_zen_30_dimmer_relay:generate_test_message("main", capabilities.switch.switch.off())
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_zooz_zen_30_dimmer_relay,
        Meter:Get({scale = Meter.scale.electric_meter.WATTS})
      )
    }
  }
)

test.register_message_test(
  "Z-Wave SwitchMultilevel reports with value-on should evoke Switch and Switch Level capability on events",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_zooz_zen_30_dimmer_relay.id,
        zw_test_utils.zwave_test_build_receive_command(
          SwitchMultilevel:Report({
            current_value = SwitchMultilevel.value.OFF_DISABLE,
            target_value = SwitchMultilevel.value.ON_ENABLE,
            duration = 0
          })
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_zooz_zen_30_dimmer_relay:generate_test_message("main", capabilities.switch.switch.on())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_zooz_zen_30_dimmer_relay:generate_test_message("main", capabilities.switchLevel.level(100))
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_zooz_zen_30_dimmer_relay,
        Meter:Get({scale = Meter.scale.electric_meter.WATTS})
      )
    }
  }
)

test.register_message_test(
  "Central Scene notification Button 1 pushed should be handled",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_zooz_zen_30_dimmer_relay.id, "init" }
    },
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_zooz_zen_30_dimmer_relay.id,
                  zw_test_utils.zwave_test_build_receive_command(CentralScene:Notification({ key_attributes=CentralScene.key_attributes.KEY_PRESSED_1_TIME, scene_number = 1},
                    { encap = zw.ENCAP.AUTO, src_channel = 1, dst_channels = {0} }))
      }
    }
  }
)

do
  local energy = 5
  test.register_message_test(
    "Energy meter report should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_zooz_zen_30_dimmer_relay.id, zw_test_utils.zwave_test_build_receive_command(Meter:Report({
          scale = Meter.scale.electric_meter.KILOWATT_HOURS,
          meter_value = energy})
        )}
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_zooz_zen_30_dimmer_relay:generate_test_message("main", capabilities.energyMeter.energy({ value = energy, unit = "kWh" }))
      }
    }
  )
end

do
  local power = 89
  test.register_message_test(
    "Power meter report should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_zooz_zen_30_dimmer_relay.id, zw_test_utils.zwave_test_build_receive_command(Meter:Report({
          scale = Meter.scale.electric_meter.WATTS,
          meter_value = power})
        )}
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_zooz_zen_30_dimmer_relay:generate_test_message("main", capabilities.powerMeter.power({ value = power, unit = "W" }))
      }
    }
  )
end

test.register_message_test(
  "Refresh Capability Command should refresh device",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_zooz_zen_30_dimmer_relay.id,
        { capability = "refresh", command = "refresh", args = {} }
      }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_zooz_zen_30_dimmer_relay,
        SwitchMultilevel:Get({})
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_zooz_zen_30_dimmer_relay,
        Meter:Get({scale = Meter.scale.electric_meter.KILOWATT_HOURS})
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_zooz_zen_30_dimmer_relay,
        Meter:Get({scale = Meter.scale.electric_meter.WATTS})
      )
    }
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.run_registered_tests()

