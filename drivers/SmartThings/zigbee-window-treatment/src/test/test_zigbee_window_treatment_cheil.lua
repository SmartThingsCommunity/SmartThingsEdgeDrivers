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
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"

local TY_CLUSTER = 0xEF00
local FRAME_CTRL_RX = 0x19
local FRAME_CTRL_TX = 0x01
local MFG_CODE = 0x110A
local PROFILE_ID = 0x104


local TY_DATA_REQUEST = 0x00	--The gateway sends a data request to the Zigbee device.
local TY_DATA_RESPONE = 0x01    --The Zigbee device responds to the gateway

local SeqNum = 0

local mock_device = test.mock_device.build_test_zigbee_device(
  { profile = t_utils.get_profile_definition("window-treatment-reverse.yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "_TZE204_xznyn2od",
        model = "jsMotor01",
        server_clusters = {0x0000, 0x0102, TY_CLUSTER}
      }
    }
  }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device)
  zigbee_test_utils.init_noop_health_check_timer()
end

test.set_test_init_function(test_init)

local function build_rx_message(device, payload)
  local strSeqNum = string.pack(">I2", SeqNum)
  local message = zigbee_test_utils.build_custom_command_id(
    device,
    TY_CLUSTER,
    TY_DATA_RESPONE,
    MFG_CODE,
    strSeqNum .. payload,
    0x00
  )
  message.body.zcl_header.frame_ctrl.value = FRAME_CTRL_RX
  message.address_header.profile.value = PROFILE_ID
  return message
end

local function build_tx_message(device, payload)
  SeqNum = SeqNum + 1
  local strSeqNum = string.pack(">I2", SeqNum)
  local message = zigbee_test_utils.build_tx_custom_command_id(
    device,
    TY_CLUSTER,
    TY_DATA_REQUEST,
    MFG_CODE,
    strSeqNum .. payload,
    0x00
  )
  message.body.zcl_header.frame_ctrl.value = FRAME_CTRL_TX
  message.address_header.profile.value = PROFILE_ID
  return message
end

local PL_AUTO_CAL = "\x65\x01\x00\x01\x01"
local PL_SET_0_PERCENT = "\x03\x02\x00\x04\x00\x00\x00\x00"
local PL_SET_50_PERCENT = "\x03\x02\x00\x04\x00\x00\x00\x32"
local PL_SET_30_PERCENT = "\x03\x02\x00\x04\x00\x00\x00\x1E"
local PL_RX_0_PERCENT = "\x01\x02\x00\x04\x00\x00\x00\x00"
local PL_RX_100_PERCENT = "\x01\x02\x00\x04\x00\x00\x00\x64"
local PL_CLOSE = "\x02\x04\x00\x01\x02"
local PL_OPEN = "\x02\x04\x00\x01\x00"
local PL_PASUE = "\x02\x04\x00\x01\x01"

local function expect_snd(payload)
  test.socket.zigbee:__expect_send({
    mock_device.id,
    build_tx_message(mock_device, payload)
  })
end

local function expect_rx(payload)
  test.socket.zigbee:__queue_receive({
    mock_device.id,
    build_rx_message(mock_device, payload)
  })
end

local function init_to_closed_state()
  expect_rx(PL_RX_0_PERCENT)
  test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(0)))
  test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.windowShade.windowShade.closed()))
end

local function init_to_open_state()
  expect_rx(PL_RX_100_PERCENT)
  test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(100)))
  test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.windowShade.windowShade.open()))
end

local function open_event()
  test.socket.capability:__queue_receive(
    {
      mock_device.id,
      { capability = "windowShade", component = "main", command = "open", args = {} }
    }
  )
  test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.windowShade.windowShade.opening()))
end

local function close_event()
  test.socket.capability:__queue_receive(
    {
      mock_device.id,
      { capability = "windowShade", component = "main", command = "close", args = {} }
    }
  )
  test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.windowShade.windowShade.closing()))
end

local function pause_event()
  test.socket.capability:__queue_receive(
    {
      mock_device.id,
      { capability = "windowShade", component = "main", command = "pause", args = {} }
    }
  )
end

local function rx_opennig_status ()
  test.wait_for_events()
  expect_rx("\x07\x04\x00\x01\x00")
  test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.windowShade.windowShade.opening()))
end

local function rx_closing_status ()
  test.wait_for_events()
  expect_rx("\x07\x04\x00\x01\x01")
  test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.windowShade.windowShade.closing()))
end

local function rx_open_status ()
  test.wait_for_events()
  expect_rx("\x01\x02\x00\x04\x00\x00\x00\x64")
  test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(100)))
  test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.windowShade.windowShade.open()))
end

local function rx_closed_status ()
  test.wait_for_events()
  expect_rx("\x01\x02\x00\x04\x00\x00\x00\x00")
  test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(0)))
  test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.windowShade.windowShade.closed()))
end

local function close_procedure()
  close_event()
  expect_snd(PL_CLOSE)
  test.wait_for_events()
  expect_rx(PL_CLOSE)
end

local function open_procedure()
  open_event()
  expect_snd(PL_OPEN)
  test.wait_for_events()
  expect_rx(PL_OPEN)
end

test.register_coroutine_test(
  "Device Added ",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
    test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.windowShade.supportedWindowShadeCommands({ "open", "close", "pause" }))
      )
    expect_snd(PL_AUTO_CAL)
    test.mock_time.advance_time(3)
    expect_snd(PL_SET_0_PERCENT)
  end
)

test.register_coroutine_test(
  "Open handler",
  function()
    init_to_closed_state()
    open_procedure()
    rx_opennig_status()
    rx_open_status()
  end
)

test.register_coroutine_test(
  "Close handler",
  function()
    init_to_open_state()
    close_procedure()
    rx_closing_status()
    rx_closed_status()
  end
)

test.register_coroutine_test(
  "Pause handler",
  function()
    init_to_open_state()
    close_procedure()
    rx_closing_status()
    test.wait_for_events()
    pause_event()
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.windowShade.windowShade.closing()))
    expect_snd(PL_PASUE)
    test.wait_for_events()
    expect_rx("\x01\x02\x00\x04\x00\x00\x00\x32")
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(50)))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.windowShade.windowShade.partially_open()))
  end
)

test.register_coroutine_test(
  "Set Level handler",
  function()
    init_to_open_state()
    test.wait_for_events()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        { capability = "windowShadeLevel", component = "main", command = "setShadeLevel", args = { 50 }}
      }
    )
    expect_snd(PL_SET_50_PERCENT)
    test.wait_for_events()
    expect_rx(PL_SET_50_PERCENT)
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.windowShade.windowShade.closing()))
    rx_closing_status()
    test.wait_for_events()
    test.wait_for_events()
    expect_rx("\x01\x02\x00\x04\x00\x00\x00\x32")
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(50)))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.windowShade.windowShade.partially_open()))
  end
)

test.register_coroutine_test(
  "Preset position handler",
  function()
    test.socket.device_lifecycle():__queue_receive(mock_device:generate_info_changed({preferences = {presetPosition = 30}}))
    test.wait_for_events()
    init_to_open_state()
    test.wait_for_events()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        { capability = "windowShadePreset", component = "main", command = "presetPosition", args = {}}
      }
    )
    expect_snd(PL_SET_30_PERCENT)
    test.wait_for_events()
    expect_rx(PL_SET_30_PERCENT)
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.windowShade.windowShade.closing()))
    test.wait_for_events()
    rx_closing_status()
    test.wait_for_events()
    expect_rx("\x01\x02\x00\x04\x00\x00\x00\x1E")
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(30)))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.windowShade.windowShade.partially_open()))
  end
)

test.register_coroutine_test(
  "Information changed : Reverse",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    init_to_open_state()
    test.wait_for_events()
    test.socket.device_lifecycle():__queue_receive(mock_device:generate_info_changed({preferences = {reverse = true}}))
    expect_snd(PL_SET_50_PERCENT)
    test.wait_for_events()
    expect_rx("\x01\x02\x00\x04\x00\x00\x00\x32")
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(50)))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.windowShade.windowShade.partially_open()))
    test.mock_time.advance_time(2)
    expect_snd("\x05\x04\x00\x01\x01")
  end
)

test.run_registered_tests()