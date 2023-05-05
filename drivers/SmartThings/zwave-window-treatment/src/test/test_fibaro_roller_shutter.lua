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
local Basic = (require "st.zwave.CommandClass.Basic")({ version=1 })
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

local mock_fibaro_roller_shutter = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("fibaro-roller-shutter.yml"),
  zwave_endpoints = fibaro_roller_shutter_endpoints,
  zwave_manufacturer_id = 0x010F,
  zwave_product_type = 0x1D01,
  zwave_product_id = 0x1000,
})

local mock_fibaro_roller_shutter_venetian = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("fibaro-roller-shutter-venetian.yml"),
  zwave_endpoints = fibaro_roller_shutter_endpoints,
  zwave_manufacturer_id = 0x010F,
  zwave_product_type = 0x1D01,
  zwave_product_id = 0x1000,
})

local function test_init()
  test.mock_device.add_test_device(mock_fibaro_roller_shutter)
  test.mock_device.add_test_device(mock_fibaro_roller_shutter_venetian)
end
test.set_test_init_function(test_init)

test.register_message_test(
    "Basic report 0 should be handled as window shade closed",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_fibaro_roller_shutter.id,
          zw_test_utils.zwave_test_build_receive_command(Basic:Report({ value = 0 })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_fibaro_roller_shutter:generate_test_message("main", capabilities.windowShade.windowShade.closed())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_fibaro_roller_shutter:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(0))
      }
    }
)

test.register_message_test(
    "Basic report 1 ~ 98 should be handled as window shade partially open",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_fibaro_roller_shutter.id,
          zw_test_utils.zwave_test_build_receive_command(Basic:Report({ value = 50 })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_fibaro_roller_shutter:generate_test_message("main", capabilities.windowShade.windowShade.partially_open())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_fibaro_roller_shutter:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(50))
      }
    }
)

test.register_message_test(
    "Basic report 99 should be handled as window shade open",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_fibaro_roller_shutter.id,
          zw_test_utils.zwave_test_build_receive_command(Basic:Report({ value = 99 })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_fibaro_roller_shutter:generate_test_message("main", capabilities.windowShade.windowShade.open())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_fibaro_roller_shutter:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(100))
      }
    }
)

test.register_message_test(
  "Switch multilevel report 0 should be handled as window shade closed",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_fibaro_roller_shutter.id,
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
      message = mock_fibaro_roller_shutter:generate_test_message("main", capabilities.windowShade.windowShade.closed())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_fibaro_roller_shutter:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(0))
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
        mock_fibaro_roller_shutter.id,
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
      message = mock_fibaro_roller_shutter:generate_test_message("main", capabilities.windowShade.windowShade.partially_open())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_fibaro_roller_shutter:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(50))
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
        mock_fibaro_roller_shutter.id,
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
      message = mock_fibaro_roller_shutter:generate_test_message("main", capabilities.windowShade.windowShade.open())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_fibaro_roller_shutter:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(100))
    }
  }
)

test.register_coroutine_test(
    "Setting window shade open should generate correct zwave messages",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(5, "oneshot")
      test.socket.capability:__queue_receive(
          {
            mock_fibaro_roller_shutter.id,
            { capability = "windowShade", command = "open", args = {} }
          }
      )
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
            mock_fibaro_roller_shutter,
            SwitchMultilevel:Set({
              value = 99,
              duration = constants.DEFAULT_DIMMING_DURATION
            })
          )
      )
      test.wait_for_events()

      test.mock_time.advance_time(5)
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
            mock_fibaro_roller_shutter,
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
            mock_fibaro_roller_shutter.id,
            { capability = "windowShade", command = "close", args = {} }
          }
      )
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
            mock_fibaro_roller_shutter,
              SwitchMultilevel:Set({
              value = SwitchMultilevel.value.OFF_DISABLE,
              duration = constants.DEFAULT_DIMMING_DURATION
            })
          )
      )
      test.wait_for_events()

      test.mock_time.advance_time(5)
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
            mock_fibaro_roller_shutter,
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
            mock_fibaro_roller_shutter.id,
            { capability = "windowShade", command = "pause", args = {} }
          }
      )
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
            mock_fibaro_roller_shutter,
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
            mock_fibaro_roller_shutter.id,
            { capability = "windowShadePreset", command = "presetPosition", args = {} }
          }
      )
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
            mock_fibaro_roller_shutter,
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
            mock_fibaro_roller_shutter,
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
            mock_fibaro_roller_shutter.id,
            { capability = "windowShadeLevel", command = "setShadeLevel", args = { 33 }}
          }
      )
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
            mock_fibaro_roller_shutter,
            SwitchMultilevel:Set({
              value = 33,
              duration = constants.DEFAULT_DIMMING_DURATION
            })
          )
      )
      test.wait_for_events()

      test.mock_time.advance_time(5)
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
            mock_fibaro_roller_shutter,
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
        mock_fibaro_roller_shutter_venetian.id,
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
      message = mock_fibaro_roller_shutter_venetian:generate_test_message("venetianBlind", capabilities.windowShadeLevel.shadeLevel(50))
    }
  }
)

test.register_coroutine_test(
    "Configuration report should be handled",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(10, "oneshot")

      test.socket.zwave:__queue_receive({mock_fibaro_roller_shutter.id, Configuration:Report({ parameter_number = 150, configuration_value = 0 }) })
      test.wait_for_events()
      assert(mock_fibaro_roller_shutter:get_field("calibration") == "not_started", "Calibration should be not started")

      test.mock_time.advance_time(2)

      test.socket.zwave:__queue_receive({mock_fibaro_roller_shutter.id, Configuration:Report({ parameter_number = 150, configuration_value = 2 }) })
      test.wait_for_events()
      assert(mock_fibaro_roller_shutter:get_field("calibration") == "pending", "Calibration should be in progress")

      test.mock_time.advance_time(2)

      test.socket.zwave:__queue_receive({mock_fibaro_roller_shutter.id, Configuration:Report({ parameter_number = 150, configuration_value = 1 }) })
      test.wait_for_events()
      assert(mock_fibaro_roller_shutter:get_field("calibration") == "done", "Calibration should be done")
    end
)

do
  local new_param_value = 2
  test.register_coroutine_test(
    "Parameter ledFrameWhenMoving should be updated in the device configuration after change",
    function()
      local device_data = utils.deep_copy(mock_fibaro_roller_shutter.raw_st_data)
      device_data.preferences["ledFrameWhenMoving"] = new_param_value
      local device_data_json = dkjson.encode(device_data)
      test.socket.device_lifecycle:__queue_receive({ mock_fibaro_roller_shutter.id, "infoChanged", device_data_json })
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_fibaro_roller_shutter,
          Configuration:Set({
            parameter_number = 11,
            configuration_value = new_param_value,
            size = 1
          })
        )
      )
    end
  )
end

do
  local new_param_value = 3
  test.register_coroutine_test(
    "Parameter ledFrameWhenNotMoving should be updated in the device configuration after change",
    function()
      local device_data = utils.deep_copy(mock_fibaro_roller_shutter.raw_st_data)
      device_data.preferences["ledFrameWhenNotMoving"] = new_param_value
      local device_data_json = dkjson.encode(device_data)
      test.socket.device_lifecycle:__queue_receive({ mock_fibaro_roller_shutter.id, "infoChanged", device_data_json })
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_fibaro_roller_shutter,
          Configuration:Set({
            parameter_number = 12,
            configuration_value = new_param_value,
            size = 1
          })
        )
      )
    end
  )
end

do
  local new_param_value = 50
  test.register_coroutine_test(
    "Parameter ledFrameBrightness should be updated in the device configuration after change",
    function()
      local device_data = utils.deep_copy(mock_fibaro_roller_shutter.raw_st_data)
      device_data.preferences["ledFrameBrightness"] = new_param_value
      local device_data_json = dkjson.encode(device_data)
      test.socket.device_lifecycle:__queue_receive({ mock_fibaro_roller_shutter.id, "infoChanged", device_data_json })
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_fibaro_roller_shutter,
          Configuration:Set({
            parameter_number = 13,
            configuration_value = new_param_value,
            size = 1
          })
        )
      )
    end
  )
end

do
  local new_param_value = 2
  test.register_coroutine_test(
    "Parameter calibration should be updated in the device configuration after change",
    function()
      local device_data = utils.deep_copy(mock_fibaro_roller_shutter.raw_st_data)
      device_data.preferences["calibration"] = new_param_value
      local device_data_json = dkjson.encode(device_data)
      test.socket.device_lifecycle:__queue_receive({ mock_fibaro_roller_shutter.id, "infoChanged", device_data_json })
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_fibaro_roller_shutter,
          Configuration:Set({
            parameter_number = 150,
            configuration_value = new_param_value,
            size = 1
          })
        )
      )
    end
  )
end

do
  local new_param_value = 6
  test.register_coroutine_test(
    "Parameter operatingMode should be updated in the device configuration after change",
    function()
      local device_data = utils.deep_copy(mock_fibaro_roller_shutter.raw_st_data)
      device_data.preferences["operatingMode"] = new_param_value
      local device_data_json = dkjson.encode(device_data)
      test.socket.device_lifecycle:__queue_receive({ mock_fibaro_roller_shutter.id, "infoChanged", device_data_json })
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_fibaro_roller_shutter,
          Configuration:Set({
            parameter_number = 151,
            configuration_value = new_param_value,
            size = 1
          })
        )
      )
    end
  )
end

do
  local new_param_value = 15
  test.register_coroutine_test(
    "Parameter delayAtEndSwitch should be updated in the device configuration after change",
    function()
      local device_data = utils.deep_copy(mock_fibaro_roller_shutter.raw_st_data)
      device_data.preferences["delayAtEndSwitch"] = new_param_value
      local device_data_json = dkjson.encode(device_data)
      test.socket.device_lifecycle:__queue_receive({ mock_fibaro_roller_shutter.id, "infoChanged", device_data_json })
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_fibaro_roller_shutter,
          Configuration:Set({
            parameter_number = 154,
            configuration_value = new_param_value,
            size = 2
          })
        )
      )
    end
  )
end

do
  local new_param_value = 15
  test.register_coroutine_test(
    "Parameter motorEndMoveDetection should be updated in the device configuration after change",
    function()
      local device_data = utils.deep_copy(mock_fibaro_roller_shutter.raw_st_data)
      device_data.preferences["motorEndMoveDetection"] = new_param_value
      local device_data_json = dkjson.encode(device_data)
      test.socket.device_lifecycle:__queue_receive({ mock_fibaro_roller_shutter.id, "infoChanged", device_data_json })
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_fibaro_roller_shutter,
          Configuration:Set({
            parameter_number = 155,
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
    "Parameter buttonsOrientation should be updated in the device configuration after change",
    function()
      local device_data = utils.deep_copy(mock_fibaro_roller_shutter.raw_st_data)
      device_data.preferences["buttonsOrientation"] = new_param_value
      local device_data_json = dkjson.encode(device_data)
      test.socket.device_lifecycle:__queue_receive({ mock_fibaro_roller_shutter.id, "infoChanged", device_data_json })
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_fibaro_roller_shutter,
          Configuration:Set({
            parameter_number = 24,
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
    "Parameter outputsOrientation should be updated in the device configuration after change",
    function()
      local device_data = utils.deep_copy(mock_fibaro_roller_shutter.raw_st_data)
      device_data.preferences["outputsOrientation"] = new_param_value
      local device_data_json = dkjson.encode(device_data)
      test.socket.device_lifecycle:__queue_receive({ mock_fibaro_roller_shutter.id, "infoChanged", device_data_json })
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_fibaro_roller_shutter,
          Configuration:Set({
            parameter_number = 25,
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
    "Parameter powerWithSelfConsumption should be updated in the device configuration after change",
    function()
      local device_data = utils.deep_copy(mock_fibaro_roller_shutter.raw_st_data)
      device_data.preferences["powerWithSelfConsumption"] = new_param_value
      local device_data_json = dkjson.encode(device_data)
      test.socket.device_lifecycle:__queue_receive({ mock_fibaro_roller_shutter.id, "infoChanged", device_data_json })
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_fibaro_roller_shutter,
          Configuration:Set({
            parameter_number = 60,
            configuration_value = new_param_value,
            size = 1
          })
        )
      )
    end
  )
end

do
  local new_param_value = 100
  test.register_coroutine_test(
    "Parameter powerReportsOnChange should be updated in the device configuration after change",
    function()
      local device_data = utils.deep_copy(mock_fibaro_roller_shutter.raw_st_data)
      device_data.preferences["powerReportsOnChange"] = new_param_value
      local device_data_json = dkjson.encode(device_data)
      test.socket.device_lifecycle:__queue_receive({ mock_fibaro_roller_shutter.id, "infoChanged", device_data_json })
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_fibaro_roller_shutter,
          Configuration:Set({
            parameter_number = 61,
            configuration_value = new_param_value,
            size = 2
          })
        )
      )
    end
  )
end

do
  local new_param_value = 600
  test.register_coroutine_test(
    "Parameter powerReportsPeriodic should be updated in the device configuration after change",
    function()
      local device_data = utils.deep_copy(mock_fibaro_roller_shutter.raw_st_data)
      device_data.preferences["powerReportsPeriodic"] = new_param_value
      local device_data_json = dkjson.encode(device_data)
      test.socket.device_lifecycle:__queue_receive({ mock_fibaro_roller_shutter.id, "infoChanged", device_data_json })
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_fibaro_roller_shutter,
          Configuration:Set({
            parameter_number = 62,
            configuration_value = new_param_value,
            size = 2
          })
        )
      )
    end
  )
end

do
  local new_param_value = 100
  test.register_coroutine_test(
    "Parameter energyReportsOnChange should be updated in the device configuration after change",
    function()
      local device_data = utils.deep_copy(mock_fibaro_roller_shutter.raw_st_data)
      device_data.preferences["energyReportsOnChange"] = new_param_value
      local device_data_json = dkjson.encode(device_data)
      test.socket.device_lifecycle:__queue_receive({ mock_fibaro_roller_shutter.id, "infoChanged", device_data_json })
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_fibaro_roller_shutter,
          Configuration:Set({
            parameter_number = 65,
            configuration_value = new_param_value,
            size = 2
          })
        )
      )
    end
  )
end

do
  local new_param_value = 600
  test.register_coroutine_test(
    "Parameter energyReportsPeriodic should be updated in the device configuration after change",
    function()
      local device_data = utils.deep_copy(mock_fibaro_roller_shutter.raw_st_data)
      device_data.preferences["energyReportsPeriodic"] = new_param_value
      local device_data_json = dkjson.encode(device_data)
      test.socket.device_lifecycle:__queue_receive({ mock_fibaro_roller_shutter.id, "infoChanged", device_data_json })
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_fibaro_roller_shutter,
          Configuration:Set({
            parameter_number = 66,
            configuration_value = new_param_value,
            size = 2
          })
        )
      )
    end
  )
end

do
  local new_param_value = 300
  test.register_coroutine_test(
    "Parameter venetianBlindTurnTime should be updated in the device configuration after change",
    function()
      local device_data = utils.deep_copy(mock_fibaro_roller_shutter_venetian.raw_st_data)
      device_data.preferences["venetianBlindTurnTime"] = new_param_value
      local device_data_json = dkjson.encode(device_data)
      test.socket.device_lifecycle:__queue_receive({ mock_fibaro_roller_shutter_venetian.id, "infoChanged", device_data_json })
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_fibaro_roller_shutter_venetian,
          Configuration:Set({
            parameter_number = 152,
            configuration_value = new_param_value,
            size = 4
          })
        )
      )
    end
  )
end
test.run_registered_tests()
