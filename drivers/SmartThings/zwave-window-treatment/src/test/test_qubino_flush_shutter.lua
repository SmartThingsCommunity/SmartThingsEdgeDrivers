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
local constants = require "st.zwave.constants"
local zw = require "st.zwave"
local zw_test_utils = require "integration_test.zwave_test_utils"
local Association = (require "st.zwave.CommandClass.Association")({version=2})
local Meter = (require "st.zwave.CommandClass.Meter")({version=3})
local SwitchMultilevel = (require "st.zwave.CommandClass.SwitchMultilevel")({ version=4 })
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version=1 })
local t_utils = require "integration_test.utils"
local utils = require "st.utils"
local dkjson = require 'dkjson'

-- supported comand classes: SWITCH_MULTILEVEL
local fibaro_roller_shutter_endpoints = {
  {
    command_classes = {
      {value = zw.SWITCH_MULTILEVEL},
      {value = zw.METER}
    }
  }
}

local mock_qubino_flush_shutter = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("qubino-flush-shutter.yml"),
  zwave_endpoints = fibaro_roller_shutter_endpoints,
  zwave_manufacturer_id = 0x0159,
  zwave_product_type = 0x0003,
  zwave_product_id = 0x0052,
})

local mock_qubino_flush_shutter_venetian = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("qubino-flush-shutter-venetian.yml"),
  zwave_endpoints = fibaro_roller_shutter_endpoints,
  zwave_manufacturer_id = 0x0159,
  zwave_product_type = 0x0003,
  zwave_product_id = 0x0052,
})

local function test_init()
  test.mock_device.add_test_device(mock_qubino_flush_shutter)
  test.mock_device.add_test_device(mock_qubino_flush_shutter_venetian)
end
test.set_test_init_function(test_init)

test.register_message_test(
  "Switch multilevel report 0 should be handled as window shade closed",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_qubino_flush_shutter.id,
        zw_test_utils.zwave_test_build_receive_command(
            SwitchMultilevel:Report({
            target_value = 0,
            current_value = SwitchMultilevel.value.OFF_DISABLE,
            duration = 0
          })
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_qubino_flush_shutter:generate_test_message("main", capabilities.windowShade.windowShade.closed())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_qubino_flush_shutter:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(0))
    }
  }
)

test.register_message_test(
  "Switch multilevel report 1 ~ 98 should be handled as window shade partially open",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_qubino_flush_shutter.id,
        zw_test_utils.zwave_test_build_receive_command(
          SwitchMultilevel:Report({
            target_value = 0,
            current_value = 50,
            duration = 0
          })
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_qubino_flush_shutter:generate_test_message("main", capabilities.windowShade.windowShade.partially_open())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_qubino_flush_shutter:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(50))
    }
  }
)

test.register_message_test(
  "Switch multilevel report 99 should be handled as window shade open",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_qubino_flush_shutter.id,
        zw_test_utils.zwave_test_build_receive_command(
          SwitchMultilevel:Report({
            target_value = 0,
            current_value = 99,
            duration = 0
          })
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_qubino_flush_shutter:generate_test_message("main", capabilities.windowShade.windowShade.open())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_qubino_flush_shutter:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(100))
    }
  }
)

test.register_coroutine_test(
    "Setting window shade open should generate correct zwave messages",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(5, "oneshot")
      test.socket.capability:__queue_receive(
          {
            mock_qubino_flush_shutter.id,
            { capability = "windowShade", command = "open", args = {} }
          }
      )
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
            mock_qubino_flush_shutter,
            SwitchMultilevel:Set({
              value = 99
            })
          )
      )
      test.wait_for_events()

      test.mock_time.advance_time(5)
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
            mock_qubino_flush_shutter,
            SwitchMultilevel:Get({})
          )
      )
    end
)

test.register_coroutine_test(
    "Setting window shade close should generate correct zwave messages",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(5, "oneshot")
      test.socket.capability:__queue_receive(
          {
            mock_qubino_flush_shutter.id,
            { capability = "windowShade", command = "close", args = {} }
          }
      )
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
            mock_qubino_flush_shutter,
              SwitchMultilevel:Set({
              value = SwitchMultilevel.value.OFF_DISABLE
            })
          )
      )
      test.wait_for_events()

      test.mock_time.advance_time(5)
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
            mock_qubino_flush_shutter,
            SwitchMultilevel:Get({})
          )
      )
    end
)

test.register_coroutine_test(
    "Setting window shade pause should generate correct zwave messages",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(5, "oneshot")
      test.socket.capability:__queue_receive(
          {
            mock_qubino_flush_shutter.id,
            { capability = "windowShade", command = "pause", args = {} }
          }
      )
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
            mock_qubino_flush_shutter,
            SwitchMultilevel:StopLevelChange({})
          )
      )
    end
)

test.register_coroutine_test(
    "Setting window shade preset generate correct zwave messages",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(5, "oneshot")
      test.socket.capability:__queue_receive(
          {
            mock_qubino_flush_shutter.id,
            { capability = "windowShadePreset", command = "presetPosition", args = {} }
          }
      )
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
            mock_qubino_flush_shutter,
            SwitchMultilevel:Set({
              value = 50,
              duration = constants.DEFAULT_DIMMING_DURATION
            })
          )
      )
      test.wait_for_events()

      test.mock_time.advance_time(5)
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
            mock_qubino_flush_shutter,
            SwitchMultilevel:Get({})
          )
      )
    end
)

test.register_coroutine_test(
    "Setting window shade level generate correct zwave messages",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(5, "oneshot")
      test.socket.capability:__queue_receive(
          {
            mock_qubino_flush_shutter.id,
            { capability = "windowShadeLevel", command = "setShadeLevel", args = { 33 }}
          }
      )
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
            mock_qubino_flush_shutter,
            SwitchMultilevel:Set({
              value = 33
            })
          )
      )
      test.wait_for_events()

      test.mock_time.advance_time(5)
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
            mock_qubino_flush_shutter,
            SwitchMultilevel:Get({})
          )
      )
    end
)

test.register_message_test(
  "Switch multilevel report from endpoint 2 should be correctly interpreted",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_qubino_flush_shutter_venetian.id,
        zw_test_utils.zwave_test_build_receive_command(
          SwitchMultilevel:Report({
            target_value = 0,
            current_value = 50,
            duration = 0
          },{encap = zw.ENCAP.AUTO, src_channel = 2, dst_channels = {0}})
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_qubino_flush_shutter_venetian:generate_test_message("venetianBlind", capabilities.windowShadeLevel.shadeLevel(50))
    }
  }
)

test.register_coroutine_test(
    "Setting venetianBlinds position should generate correct zwave messages",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(5, "oneshot")
      test.socket.capability:__queue_receive(
          {
            mock_qubino_flush_shutter_venetian.id,
            { capability = "windowShadeLevel", command = "setShadeLevel", args = { 33 }, component = "venetianBlind" }
          }
      )
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
            mock_qubino_flush_shutter_venetian,
            SwitchMultilevel:Set({
              value = 33
            },{encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {2}})
          )
      )
      test.wait_for_events()

      test.mock_time.advance_time(5)
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
            mock_qubino_flush_shutter_venetian,
            SwitchMultilevel:Get({}, {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {2}})
          )
      )
    end
)

do
  local new_param_value = 1
  test.register_coroutine_test(
    "Parameter operatingModes should be updated in the device configuration after change",
    function()
      local device_data = utils.deep_copy(mock_qubino_flush_shutter.raw_st_data)
      device_data.preferences["operatingModes"] = new_param_value
      local device_data_json = dkjson.encode(device_data)
      test.socket.device_lifecycle:__queue_receive({ mock_qubino_flush_shutter.id, "infoChanged", device_data_json })
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_qubino_flush_shutter,
          Configuration:Set({
            parameter_number = 71,
            configuration_value = new_param_value,
            size = 1
          })
        )
      )
    end
  )
end

do
  local new_param_value = 200
  test.register_coroutine_test(
    "Parameter slatsTurnTime should be updated in the device configuration after change",
    function()
      local device_data = utils.deep_copy(mock_qubino_flush_shutter.raw_st_data)
      device_data.preferences["slatsTurnTime"] = new_param_value
      local device_data_json = dkjson.encode(device_data)
      test.socket.device_lifecycle:__queue_receive({ mock_qubino_flush_shutter.id, "infoChanged", device_data_json })
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_qubino_flush_shutter,
          Configuration:Set({
            parameter_number = 72,
            configuration_value = new_param_value,
            size = 2
          })
        )
      )
    end
  )
end

do
  local new_param_value = 1
  test.register_coroutine_test(
    "Parameter slatsPosition should be updated in the device configuration after change",
    function()
      local device_data = utils.deep_copy(mock_qubino_flush_shutter.raw_st_data)
      device_data.preferences["slatsPosition"] = new_param_value
      local device_data_json = dkjson.encode(device_data)
      test.socket.device_lifecycle:__queue_receive({ mock_qubino_flush_shutter.id, "infoChanged", device_data_json })
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_qubino_flush_shutter,
          Configuration:Set({
            parameter_number = 73,
            configuration_value = new_param_value,
            size = 1
          })
        )
      )
    end
  )
end

do
  local new_param_value = 300
  test.register_coroutine_test(
    "Parameter motorUpDownTime should be updated in the device configuration after change",
    function()
      local device_data = utils.deep_copy(mock_qubino_flush_shutter.raw_st_data)
      device_data.preferences["motorUpDownTime"] = new_param_value
      local device_data_json = dkjson.encode(device_data)
      test.socket.device_lifecycle:__queue_receive({ mock_qubino_flush_shutter.id, "infoChanged", device_data_json })
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_qubino_flush_shutter,
          Configuration:Set({
            parameter_number = 74,
            configuration_value = new_param_value,
            size = 2
          })
        )
      )
    end
  )
end

do
  local new_param_value = 50
  test.register_coroutine_test(
    "Parameter motorOperationDetection should be updated in the device configuration after change",
    function()
      local device_data = utils.deep_copy(mock_qubino_flush_shutter.raw_st_data)
      device_data.preferences["motorOperationDetection"] = new_param_value
      local device_data_json = dkjson.encode(device_data)
      test.socket.device_lifecycle:__queue_receive({ mock_qubino_flush_shutter.id, "infoChanged", device_data_json })
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_qubino_flush_shutter,
          Configuration:Set({
            parameter_number = 76,
            configuration_value = new_param_value,
            size = 1
          })
        )
      )
    end
  )
end

do
  local new_param_value = 1
  test.register_coroutine_test(
    "Parameter forcedCalibration should be updated in the device configuration after change",
    function()
      local device_data = utils.deep_copy(mock_qubino_flush_shutter.raw_st_data)
      device_data.preferences["forcedCalibration"] = new_param_value
      local device_data_json = dkjson.encode(device_data)
      test.socket.device_lifecycle:__queue_receive({ mock_qubino_flush_shutter.id, "infoChanged", device_data_json })
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_qubino_flush_shutter,
          Configuration:Set({
            parameter_number = 78,
            configuration_value = new_param_value,
            size = 1
          })
        )
      )
    end
  )
end

test.register_coroutine_test(
  "Device should be configured when added",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({ mock_qubino_flush_shutter.id, "added" })

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_qubino_flush_shutter,
        Association:Set({grouping_identifier = 7, node_ids = {}})
      )
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_qubino_flush_shutter,
        Configuration:Set({parameter_number = 40, size = 1, configuration_value = 1})
      )
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_qubino_flush_shutter,
        Configuration:Set({parameter_number = 71, size = 1, configuration_value = 0})
      )
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_qubino_flush_shutter,
        SwitchMultilevel:Get({})
      )
    )
    test.socket.capability:__expect_send(
      mock_qubino_flush_shutter:generate_test_message(
        "main",
        capabilities.windowShade.supportedWindowShadeCommands({"open", "close", "pause"}, { visibility = { displayed = false }})
      )
    )
  end
)

do
  test.register_coroutine_test(
    "Mode should be changed to venetian blinds after receiving configuration report with value 1",
    function()
      test.wait_for_events()
      test.socket.zwave:__queue_receive({
        mock_qubino_flush_shutter.id,
        Configuration:Report({
          parameter_number = 71,
          size = 1,
          configuration_value = 1
      })
    })
    mock_qubino_flush_shutter:expect_metadata_update({ profile = "qubino-flush-shutter-venetian" })
    end
  )
end

do
  test.register_coroutine_test(
    "Mode should be changed to shutter after receiving configuration report with value 0",
    function()
      test.wait_for_events()
      test.socket.zwave:__queue_receive({
        mock_qubino_flush_shutter.id,
        Configuration:Report({
          parameter_number = 71,
          size = 1,
          configuration_value = 0
        })
      })
      mock_qubino_flush_shutter:expect_metadata_update({ profile = "qubino-flush-shutter" })
    end
  )
end

do
  test.register_coroutine_test(
    "SwitchMultilevel:Set() should be correctly interpreted by the driver",
    function()
      local targetValue = 50
      test.wait_for_events()
      test.socket.zwave:__queue_receive({
        mock_qubino_flush_shutter.id,
        SwitchMultilevel:Set({
          value = targetValue
        })
      })
      local expectedCachedEvent = utils.stringify_table(capabilities.windowShade.windowShade.opening())
      test.wait_for_events()
      local actualCachedEvent = utils.stringify_table(mock_qubino_flush_shutter.transient_store.blinds_last_command)
      assert(expectedCachedEvent == actualCachedEvent, "driver should cache 'opening' event when targetLevel > currentLevel")
      assert(targetValue == mock_qubino_flush_shutter.transient_store.shade_target, "driver should chache correct level value")
    end
  )
end

do
  test.register_coroutine_test(
    "Meter:Report() with meter_value > 0 should be correctly interpreted by the driver",
    function()
      local cachedShadesEvent = capabilities.windowShade.windowShade.opening()
      local targetValue = 50
      mock_qubino_flush_shutter:set_field("blinds_last_command", cachedShadesEvent)
      mock_qubino_flush_shutter:set_field("shade_target", targetValue)
      test.wait_for_events()
      test.socket.zwave:__queue_receive({
        mock_qubino_flush_shutter.id,
        Meter:Report({
          scale = Meter.scale.electric_meter.WATTS,
          meter_value = 10
        })
      })
      test.socket.capability:__expect_send(
        mock_qubino_flush_shutter:generate_test_message("main", cachedShadesEvent)
      )
      test.socket.capability:__expect_send(
        mock_qubino_flush_shutter:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(targetValue))
      )
      test.socket.capability:__expect_send(
        mock_qubino_flush_shutter:generate_test_message("main", capabilities.powerMeter.power({value = 10, unit = "W"}))
      )
    end
  )
end

do
  test.register_coroutine_test(
    "Meter:Report() with meter_value == 0 should be correctly interpreted by the driver",
    function()
      test.wait_for_events()
      test.socket.zwave:__queue_receive({
        mock_qubino_flush_shutter.id,
        Meter:Report({
          scale = Meter.scale.electric_meter.WATTS,
          meter_value = 0
        })
      })
      test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_qubino_flush_shutter,
        SwitchMultilevel:Get({})
        )
      )
      test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_qubino_flush_shutter,
        Meter:Get({scale = Meter.scale.electric_meter.KILOWATT_HOURS})
        )
      )
      test.socket.capability:__expect_send(
        mock_qubino_flush_shutter:generate_test_message("main", capabilities.powerMeter.power({value = 0, unit = "W"}))
      )
    end
  )
end

test.register_message_test(
  "Energy meter reports should be generating events",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_qubino_flush_shutter.id,
        zw_test_utils.zwave_test_build_receive_command(
          Meter:Report({
            scale = Meter.scale.electric_meter.KILOWATT_HOURS,
            meter_value = 50
          })
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_qubino_flush_shutter:generate_test_message("main", capabilities.energyMeter.energy({value = 50, unit = "kWh"}))
    }
  }
)

test.run_registered_tests()
