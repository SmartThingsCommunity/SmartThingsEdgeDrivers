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
local capabilities = require "st.capabilities"
test.add_package_capability("lockAlarm.yml")
local clusters = require "st.matter.clusters"
local t_utils = require "integration_test.utils"
local uint32 = require "st.matter.data_types.Uint32"

local DoorLock = clusters.DoorLock

local mock_device = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("lock.yml"),
  manufacturer_info = {
    vendor_id = 0x147F,
    product_id = 0x0001,
  },
  endpoints = {
    {
      endpoint_id = 0,
      clusters = {
        { cluster_id = clusters.Basic.ID, cluster_type = "SERVER" },
      },
      device_types = {
        { device_type_id = 0x0016, device_type_revision = 1 } -- RootNode
      }
    },
    {
      endpoint_id = 1,
      clusters = {
        {
          cluster_id = DoorLock.ID,
          cluster_type = "SERVER",
          cluster_revision = 1,
          feature_map = 0x0,
        },
        {
          cluster_id = clusters.PowerSource.ID,
          cluster_type = "SERVER",
          feature_map = 10
        },
      },
      device_types = {
        { device_type_id = 0x000A, device_type_revision = 1 } -- Door Lock
      }
    }
  }
})

local mock_device_unlatch = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("lock-unlatch.yml"),
  manufacturer_info = {
    vendor_id = 0x147F,
    product_id = 0x0001,
  },
  endpoints = {
    {
      endpoint_id = 0,
      clusters = {
        { cluster_id = clusters.Basic.ID, cluster_type = "SERVER" },
      },
      device_types = {
        { device_type_id = 0x0016, device_type_revision = 1 } -- RootNode
      }
    },
    {
      endpoint_id = 1,
      clusters = {
        {
          cluster_id = DoorLock.ID,
          cluster_type = "SERVER",
          cluster_revision = 1,
          feature_map = 0x1000, -- UNLATCH
        },
        {
          cluster_id = clusters.PowerSource.ID,
          cluster_type = "SERVER",
          feature_map = 10
        },
      },
      device_types = {
        { device_type_id = 0x000A, device_type_revision = 1 } -- Door Lock
      }
    }
  }
})

local mock_device_user_pin = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("lock-user-pin.yml"),
  manufacturer_info = {
    vendor_id = 0x147F,
    product_id = 0x0001,
  },
  endpoints = {
    {
      endpoint_id = 0,
      clusters = {
        { cluster_id = clusters.Basic.ID, cluster_type = "SERVER" },
      },
      device_types = {
        { device_type_id = 0x0016, device_type_revision = 1 } -- RootNode
      }
    },
    {
      endpoint_id = 1,
      clusters = {
        {
          cluster_id = DoorLock.ID,
          cluster_type = "SERVER",
          cluster_revision = 1,
          feature_map = 0x0181, -- PIN & USR & COTA
        },
        {
          cluster_id = clusters.PowerSource.ID,
          cluster_type = "SERVER",
          feature_map = 10
        },
      },
      device_types = {
        { device_type_id = 0x000A, device_type_revision = 1 } -- Door Lock
      }
    }
  }
})

local mock_device_user_pin_schedule_unlatch = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("lock-user-pin-schedule-unlatch.yml"),
  manufacturer_info = {
    vendor_id = 0x147F,
    product_id = 0x0001,
  },
  endpoints = {
    {
      endpoint_id = 0,
      clusters = {
        { cluster_id = clusters.Basic.ID, cluster_type = "SERVER" },
      },
      device_types = {
        { device_type_id = 0x0016, device_type_revision = 1 } -- RootNode
      }
    },
    {
      endpoint_id = 1,
      clusters = {
        {
          cluster_id = DoorLock.ID,
          cluster_type = "SERVER",
          cluster_revision = 1,
          feature_map = 0x1591, -- PIN & USR & COTA & WDSCH & YDSCH & UNLATCH
        },
        {
          cluster_id = clusters.PowerSource.ID,
          cluster_type = "SERVER",
          feature_map = 10
        },
      },
      device_types = {
        { device_type_id = 0x000A, device_type_revision = 1 } -- Door Lock
      }
    }
  }
})

local function test_init()
  test.disable_startup_messages()
  test.mock_device.add_test_device(mock_device)
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
  test.socket.capability:__expect_send(
    mock_device:generate_test_message("main", capabilities.lockAlarm.alarm.clear({state_change = true}))
  )
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "init" })
  local subscribe_request = DoorLock.attributes.LockState:subscribe(mock_device)
  subscribe_request:merge(DoorLock.attributes.OperatingMode:subscribe(mock_device))
  subscribe_request:merge(DoorLock.events.LockOperation:subscribe(mock_device))
  subscribe_request:merge(DoorLock.events.DoorLockAlarm:subscribe(mock_device))
  test.socket["matter"]:__expect_send({mock_device.id, subscribe_request})
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
  test.socket.capability:__expect_send(
    mock_device:generate_test_message("main", capabilities.lock.supportedLockCommands({"lock", "unlock"}, {visibility = {displayed = false}}))
  )
  test.socket.matter:__expect_send({mock_device.id, clusters.PowerSource.attributes.AttributeList:read()})
  mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
end

local function test_init_unlatch()
  test.disable_startup_messages()
  test.mock_device.add_test_device(mock_device_unlatch)
  test.socket.device_lifecycle:__queue_receive({ mock_device_unlatch.id, "added" })
  test.socket.capability:__expect_send(
    mock_device_unlatch:generate_test_message("main", capabilities.lockAlarm.alarm.clear({state_change = true}))
  )
  test.socket.device_lifecycle:__queue_receive({ mock_device_unlatch.id, "init" })
  local subscribe_request = DoorLock.attributes.LockState:subscribe(mock_device_unlatch)
  subscribe_request:merge(DoorLock.attributes.OperatingMode:subscribe(mock_device_unlatch))
  subscribe_request:merge(DoorLock.events.LockOperation:subscribe(mock_device_unlatch))
  subscribe_request:merge(DoorLock.events.DoorLockAlarm:subscribe(mock_device_unlatch))
  test.socket["matter"]:__expect_send({mock_device_unlatch.id, subscribe_request})
  test.socket.device_lifecycle:__queue_receive({ mock_device_unlatch.id, "doConfigure" })
  test.socket.capability:__expect_send(
    mock_device_unlatch:generate_test_message("main", capabilities.lock.supportedLockCommands({"lock", "unlock", "unlatch"}, {visibility = {displayed = false}}))
  )
  test.socket.matter:__expect_send({mock_device_unlatch.id, clusters.PowerSource.attributes.AttributeList:read()})
  mock_device_unlatch:expect_metadata_update({ provisioning_state = "PROVISIONED" })
end

local function test_init_user_pin()
  test.disable_startup_messages()
  test.mock_device.add_test_device(mock_device_user_pin)
  test.socket.device_lifecycle:__queue_receive({ mock_device_user_pin.id, "added" })
  test.socket.capability:__expect_send(
    mock_device_user_pin:generate_test_message("main", capabilities.lockAlarm.alarm.clear({state_change = true}))
  )
  test.socket.device_lifecycle:__queue_receive({ mock_device_user_pin.id, "init" })
  local subscribe_request = DoorLock.attributes.LockState:subscribe(mock_device_user_pin)
  subscribe_request:merge(DoorLock.attributes.OperatingMode:subscribe(mock_device_user_pin))
  subscribe_request:merge(DoorLock.attributes.NumberOfTotalUsersSupported:subscribe(mock_device_user_pin))
  subscribe_request:merge(DoorLock.attributes.NumberOfPINUsersSupported:subscribe(mock_device_user_pin))
  subscribe_request:merge(DoorLock.attributes.MaxPINCodeLength:subscribe(mock_device_user_pin))
  subscribe_request:merge(DoorLock.attributes.MinPINCodeLength:subscribe(mock_device_user_pin))
  subscribe_request:merge(DoorLock.attributes.RequirePINforRemoteOperation:subscribe(mock_device_user_pin))
  subscribe_request:merge(DoorLock.events.LockOperation:subscribe(mock_device_user_pin))
  subscribe_request:merge(DoorLock.events.DoorLockAlarm:subscribe(mock_device_user_pin))
  subscribe_request:merge(DoorLock.events.LockUserChange:subscribe(mock_device_user_pin))
  test.socket["matter"]:__expect_send({mock_device_user_pin.id, subscribe_request})
  test.socket.device_lifecycle:__queue_receive({ mock_device_user_pin.id, "doConfigure" })
  test.socket.capability:__expect_send(
    mock_device_user_pin:generate_test_message("main", capabilities.lock.supportedLockCommands({"lock", "unlock"}, {visibility = {displayed = false}}))
  )
  test.socket.matter:__expect_send({mock_device_user_pin.id, clusters.PowerSource.attributes.AttributeList:read()})
  mock_device_user_pin:expect_metadata_update({ provisioning_state = "PROVISIONED" })
end

local function test_init_user_pin_schedule_unlatch()
  test.disable_startup_messages()
  test.mock_device.add_test_device(mock_device_user_pin_schedule_unlatch)
  test.socket.device_lifecycle:__queue_receive({ mock_device_user_pin_schedule_unlatch.id, "added" })
  test.socket.capability:__expect_send(
    mock_device_user_pin_schedule_unlatch:generate_test_message("main", capabilities.lockAlarm.alarm.clear({state_change = true}))
  )
  test.socket.device_lifecycle:__queue_receive({ mock_device_user_pin_schedule_unlatch.id, "init" })
  local subscribe_request = DoorLock.attributes.LockState:subscribe(mock_device_user_pin_schedule_unlatch)
  subscribe_request:merge(DoorLock.attributes.OperatingMode:subscribe(mock_device_user_pin_schedule_unlatch))
  subscribe_request:merge(DoorLock.attributes.NumberOfTotalUsersSupported:subscribe(mock_device_user_pin_schedule_unlatch))
  subscribe_request:merge(DoorLock.attributes.NumberOfPINUsersSupported:subscribe(mock_device_user_pin_schedule_unlatch))
  subscribe_request:merge(DoorLock.attributes.MaxPINCodeLength:subscribe(mock_device_user_pin_schedule_unlatch))
  subscribe_request:merge(DoorLock.attributes.MinPINCodeLength:subscribe(mock_device_user_pin_schedule_unlatch))
  subscribe_request:merge(DoorLock.attributes.RequirePINforRemoteOperation:subscribe(mock_device_user_pin_schedule_unlatch))
  subscribe_request:merge(DoorLock.attributes.NumberOfWeekDaySchedulesSupportedPerUser:subscribe(mock_device_user_pin_schedule_unlatch))
  subscribe_request:merge(DoorLock.attributes.NumberOfYearDaySchedulesSupportedPerUser:subscribe(mock_device_user_pin_schedule_unlatch))
  subscribe_request:merge(DoorLock.events.LockOperation:subscribe(mock_device_user_pin_schedule_unlatch))
  subscribe_request:merge(DoorLock.events.DoorLockAlarm:subscribe(mock_device_user_pin_schedule_unlatch))
  subscribe_request:merge(DoorLock.events.LockUserChange:subscribe(mock_device_user_pin_schedule_unlatch))
  test.socket["matter"]:__expect_send({mock_device_user_pin_schedule_unlatch.id, subscribe_request})
  test.socket.device_lifecycle:__queue_receive({ mock_device_user_pin_schedule_unlatch.id, "doConfigure" })
  test.socket.capability:__expect_send(
    mock_device_user_pin_schedule_unlatch:generate_test_message("main", capabilities.lock.supportedLockCommands({"lock", "unlock", "unlatch"}, {visibility = {displayed = false}}))
  )
  test.socket.matter:__expect_send({mock_device_user_pin_schedule_unlatch.id, clusters.PowerSource.attributes.AttributeList:read()})
  mock_device_user_pin_schedule_unlatch:expect_metadata_update({ provisioning_state = "PROVISIONED" })
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Test lock profile change when attributes related to BAT feature is not available.",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        clusters.PowerSource.attributes.AttributeList:build_test_report_data(mock_device, 1,
          {
            uint32(0),
            uint32(1),
            uint32(2),
            uint32(31),
            uint32(65528),
            uint32(65529),
            uint32(65531),
            uint32(65532),
            uint32(65533),
          })
      }
    )
    mock_device:expect_metadata_update({ profile = "lock" })
  end
)

test.register_coroutine_test(
  "Test lock profile change when BatChargeLevel attribute is available",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        clusters.PowerSource.attributes.AttributeList:build_test_report_data(mock_device, 1,
          {
            uint32(0),
            uint32(1),
            uint32(2),
            uint32(14), -- BatChargeLevel
            uint32(31),
            uint32(65528),
            uint32(65529),
            uint32(65531),
            uint32(65532),
            uint32(65533),
          })
      }
    )
    mock_device:expect_metadata_update({ profile = "lock-batteryLevel" })
  end
)

test.register_coroutine_test(
  "Test lock profile change when BatChargeLevel and BatPercentRemaining attributes are available",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        clusters.PowerSource.attributes.AttributeList:build_test_report_data(mock_device, 1,
          {
            uint32(0),
            uint32(1),
            uint32(2),
            uint32(12), -- BatPercentRemaining
            uint32(14), -- BatChargeLevel
            uint32(31),
            uint32(65528),
            uint32(65529),
            uint32(65531),
            uint32(65532),
            uint32(65533),
          })
      }
    )
    mock_device:expect_metadata_update({ profile = "lock-battery" })
  end
)

test.register_coroutine_test(
  "Test lock-unlatch profile change when attributes related to BAT feature is not available.",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device_unlatch.id,
        clusters.PowerSource.attributes.AttributeList:build_test_report_data(mock_device_unlatch, 1,
          {
            uint32(0),
            uint32(1),
            uint32(2),
            uint32(31),
            uint32(65528),
            uint32(65529),
            uint32(65531),
            uint32(65532),
            uint32(65533),
          })
      }
    )
    mock_device_unlatch:expect_metadata_update({ profile = "lock-unlatch" })
  end,
  { test_init = test_init_unlatch }
)

test.register_coroutine_test(
  "Test lock-unlatch profile change when BatChargeLevel attribute is available",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device_unlatch.id,
        clusters.PowerSource.attributes.AttributeList:build_test_report_data(mock_device_unlatch, 1,
          {
            uint32(0),
            uint32(1),
            uint32(2),
            uint32(14), -- BatChargeLevel
            uint32(31),
            uint32(65528),
            uint32(65529),
            uint32(65531),
            uint32(65532),
            uint32(65533),
          })
      }
    )
    mock_device_unlatch:expect_metadata_update({ profile = "lock-unlatch-batteryLevel" })
  end,
  { test_init = test_init_unlatch }
)

test.register_coroutine_test(
  "Test lock-unlatch profile change when BatChargeLevel and BatPercentRemaining attributes are available",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device_unlatch.id,
        clusters.PowerSource.attributes.AttributeList:build_test_report_data(mock_device_unlatch, 1,
          {
            uint32(0),
            uint32(1),
            uint32(2),
            uint32(12), -- BatPercentRemaining
            uint32(14), -- BatChargeLevel
            uint32(31),
            uint32(65528),
            uint32(65529),
            uint32(65531),
            uint32(65532),
            uint32(65533),
          })
      }
    )
    mock_device_unlatch:expect_metadata_update({ profile = "lock-unlatch-battery" })
  end,
  { test_init = test_init_unlatch }
)

test.register_coroutine_test(
  "Test lock-user-pin profile change when attributes related to BAT feature is not available.",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device_user_pin.id,
        clusters.PowerSource.attributes.AttributeList:build_test_report_data(mock_device_user_pin, 1,
          {
            uint32(0),
            uint32(1),
            uint32(2),
            uint32(31),
            uint32(65528),
            uint32(65529),
            uint32(65531),
            uint32(65532),
            uint32(65533),
          })
      }
    )
    mock_device_user_pin:expect_metadata_update({ profile = "lock-user-pin" })
  end,
  { test_init = test_init_user_pin }
)

test.register_coroutine_test(
  "Test lock-user-pin profile change when BatChargeLevel attribute is available",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device_user_pin.id,
        clusters.PowerSource.attributes.AttributeList:build_test_report_data(mock_device_user_pin, 1,
          {
            uint32(0),
            uint32(1),
            uint32(2),
            uint32(14), -- BatChargeLevel
            uint32(31),
            uint32(65528),
            uint32(65529),
            uint32(65531),
            uint32(65532),
            uint32(65533),
          })
      }
    )
    mock_device_user_pin:expect_metadata_update({ profile = "lock-user-pin-batteryLevel" })
  end,
  { test_init = test_init_user_pin }
)

test.register_coroutine_test(
  "Test lock-user-pin profile change when BatChargeLevel and BatPercentRemaining attributes are available",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device_user_pin.id,
        clusters.PowerSource.attributes.AttributeList:build_test_report_data(mock_device_user_pin, 1,
          {
            uint32(0),
            uint32(1),
            uint32(2),
            uint32(12), -- BatPercentRemaining
            uint32(14), -- BatChargeLevel
            uint32(31),
            uint32(65528),
            uint32(65529),
            uint32(65531),
            uint32(65532),
            uint32(65533),
          })
      }
    )
    mock_device_user_pin:expect_metadata_update({ profile = "lock-user-pin-battery" })
  end,
  { test_init = test_init_user_pin }
)

test.register_coroutine_test(
  "Test lock-user-pin-schedule-unlatch profile change when attributes related to BAT feature is not available.",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device_user_pin_schedule_unlatch.id,
        clusters.PowerSource.attributes.AttributeList:build_test_report_data(mock_device_user_pin_schedule_unlatch, 1,
          {
            uint32(0),
            uint32(1),
            uint32(2),
            uint32(31),
            uint32(65528),
            uint32(65529),
            uint32(65531),
            uint32(65532),
            uint32(65533),
          })
      }
    )
    mock_device_user_pin_schedule_unlatch:expect_metadata_update({ profile = "lock-user-pin-schedule-unlatch" })
  end,
  { test_init = test_init_user_pin_schedule_unlatch }
)

test.register_coroutine_test(
  "Test lock-user-pin-schedule-unlatch profile change when BatChargeLevel attribute is available",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device_user_pin_schedule_unlatch.id,
        clusters.PowerSource.attributes.AttributeList:build_test_report_data(mock_device_user_pin_schedule_unlatch, 1,
          {
            uint32(0),
            uint32(1),
            uint32(2),
            uint32(14), -- BatChargeLevel
            uint32(31),
            uint32(65528),
            uint32(65529),
            uint32(65531),
            uint32(65532),
            uint32(65533),
          })
      }
    )
    mock_device_user_pin_schedule_unlatch:expect_metadata_update({ profile = "lock-user-pin-schedule-unlatch-batteryLevel" })
  end,
  { test_init = test_init_user_pin_schedule_unlatch }
)

test.register_coroutine_test(
  "Test lock-user-pin-schedule-unlatch profile change when BatChargeLevel and BatPercentRemaining attributes are available",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device_user_pin_schedule_unlatch.id,
        clusters.PowerSource.attributes.AttributeList:build_test_report_data(mock_device_user_pin_schedule_unlatch, 1,
          {
            uint32(0),
            uint32(1),
            uint32(2),
            uint32(12), -- BatPercentRemaining
            uint32(14), -- BatChargeLevel
            uint32(31),
            uint32(65528),
            uint32(65529),
            uint32(65531),
            uint32(65532),
            uint32(65533),
          })
      }
    )
    mock_device_user_pin_schedule_unlatch:expect_metadata_update({ profile = "lock-user-pin-schedule-unlatch-battery" })
  end,
  { test_init = test_init_user_pin_schedule_unlatch }
)

test.run_registered_tests()
