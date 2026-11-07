-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local t_utils = require "integration_test.utils"
local capabilities = require "st.capabilities"
local zw = require "st.zwave"
local Alarm = (require "st.zwave.CommandClass.Alarm")({ version = 1 })
local DoorLock = (require "st.zwave.CommandClass.DoorLock")({ version = 1 })
local constants = require "lock_utils.constants"

local YALE_MFR = 0x0129
local CONEXIS_PRODUCT_TYPE = 0x6600
local CONEXIS_PRODUCT_ID = 0x0002
local OTHER_MFR = 0x003B

test.disable_startup_messages()

local zwave_lock_endpoints = {
  {
    command_classes = {
      { value = zw.BATTERY },
      { value = zw.DOOR_LOCK },
      { value = zw.USER_CODE },
      { value = zw.ALARM },
    }
  }
}

local function build_lock(manufacturer_id, product_type, product_id)
  return test.mock_device.build_test_zwave_device({
    profile = t_utils.get_profile_definition("base-lock-tamper.yml"),
    zwave_endpoints = zwave_lock_endpoints,
    zwave_manufacturer_id = manufacturer_id,
    zwave_product_type = product_type,
    zwave_product_id = product_id,
  })
end

local mock_conexis = build_lock(YALE_MFR, CONEXIS_PRODUCT_TYPE, CONEXIS_PRODUCT_ID)
local mock_other_yale = build_lock(YALE_MFR, 0x8002, 0x0600)
local mock_other_mfr = build_lock(OTHER_MFR, 0x0001, 0x0001)

local function test_init()
  test.mock_device.add_test_device(mock_conexis)
  test.mock_device.add_test_device(mock_other_yale)
  test.mock_device.add_test_device(mock_other_mfr)
end
test.set_test_init_function(test_init)

test.register_message_test(
  "Yale tag unlock (alarm 144) is reported as an rfid unlock with the tag slot (legacy handlers)",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_conexis.id, Alarm:Report({ alarm_type = 144, alarm_level = 3 }) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_conexis:generate_test_message("main",
        capabilities.lock.lock.unlocked({ data = { codeId = "3", method = "rfid" } }))
    }
  },
  { min_api_version = 14 }
)

test.register_coroutine_test(
  "Yale tag unlock (alarm 144) is reported as an rfid unlock with the tag slot (migrated device)",
  function()
    mock_conexis:set_field(constants.DRIVER_STATE.SLGA_MIGRATED, true, { persist = true })
    test.socket.zwave:__queue_receive({ mock_conexis.id, Alarm:Report({ alarm_type = 144, alarm_level = 3 }) })
    test.socket.capability:__expect_send(mock_conexis:generate_test_message("main",
      capabilities.lock.lock.unlocked({ data = { codeId = "3", method = "rfid" } })))
  end,
  { min_api_version = 14 }
)

test.register_coroutine_test(
  "Alarm 144 from another manufacturer is ignored",
  function()
    test.socket.zwave:__queue_receive({ mock_other_mfr.id, Alarm:Report({ alarm_type = 144, alarm_level = 3 }) })
    test.wait_for_events()
  end,
  { min_api_version = 14 }
)

test.register_message_test(
  "Conexis alarm 21 level 1 (handle lifted) is a manual lock",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_conexis.id, Alarm:Report({ alarm_type = 21, alarm_level = 1 }) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_conexis:generate_test_message("main",
        capabilities.lock.lock.locked({ data = { method = "manual" } }))
    }
  },
  { min_api_version = 14 }
)

test.register_message_test(
  "Other Yale locks keep alarm 21 level 1 as a keypad lock",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_other_yale.id, Alarm:Report({ alarm_type = 21, alarm_level = 1 }) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_other_yale:generate_test_message("main",
        capabilities.lock.lock.locked({ data = { method = "keypad" } }))
    }
  },
  { min_api_version = 14 }
)

test.register_coroutine_test(
  "Once the gap is learned, the held Operation Report is replaced by the detailed alarm event",
  function()
    -- the lock is known to report Operation Report then alarm ~1s later
    mock_conexis:set_field(constants.DELAY_LOCK_EVENT, 1, {})
    test.timer.__create_and_queue_test_time_advance_timer(1.5, "oneshot")
    test.socket.zwave:__queue_receive({ mock_conexis.id,
      DoorLock:OperationReport({ door_lock_mode = DoorLock.door_lock_mode.DOOR_UNSECURED }) })
    test.wait_for_events()
    test.socket.zwave:__queue_receive({ mock_conexis.id, Alarm:Report({ alarm_type = 144, alarm_level = 3 }) })
    test.socket.capability:__expect_send(mock_conexis:generate_test_message("main",
      capabilities.lock.lock.unlocked({ data = { codeId = "3", method = "rfid" } })))
    test.wait_for_events()
    -- the held plain event must not be sent when its timer would have fired
    test.mock_time.advance_time(1.5)
  end,
  { min_api_version = 14 }
)

test.run_registered_tests()
