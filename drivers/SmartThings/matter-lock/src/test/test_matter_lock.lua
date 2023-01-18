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
local t_utils = require "integration_test.utils"
local clusters = require "st.matter.clusters"
local im = require "st.matter.interaction_model"

local mock_device_record = {
  profile = t_utils.get_profile_definition("lock-without-codes.yml"),
  manufacturer_info = {vendor_id = 0x101D, product_id = 0x1},
  endpoints = {
    {
      endpoint_id = 1,
      clusters = {
        {cluster_id = clusters.DoorLock.ID, cluster_type = "SERVER", feature_map = 0x0000},
        {cluster_id = clusters.PowerSource.ID, cluster_type = "SERVER"},
      },
    },
  },
}
local mock_device = test.mock_device.build_test_matter_device(mock_device_record)

local function test_init()
  local subscribe_request = clusters.DoorLock.attributes.LockState:subscribe(mock_device)
  subscribe_request:merge(clusters.PowerSource.attributes.BatPercentRemaining:subscribe(mock_device))
  subscribe_request:merge(clusters.DoorLock.events.DoorLockAlarm:subscribe(mock_device))
  subscribe_request:merge(clusters.DoorLock.events.LockOperation:subscribe(mock_device))
  test.socket["matter"]:__expect_send({mock_device.id, subscribe_request})
  test.mock_device.add_test_device(mock_device)
end

test.set_test_init_function(test_init)

--TODO add tests for how we expect cota vs non cota devices
-- to function wrt lock/unlock commands

test.register_message_test(
  "Handle Lock command received from SmartThings.", {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        {capability = "lock", component = "main", command = "lock", args = {}},
      },
    },
    {
      channel = "matter",
      direction = "send",
      message = {mock_device.id, clusters.DoorLock.server.commands.LockDoor(mock_device, 1)},
    },
  }
)

test.register_message_test(
  "Handle Unlock command received from SmartThings.", {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        {capability = "lock", component = "main", command = "unlock", args = {}},
      },
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.DoorLock.server.commands.UnlockDoor(mock_device, 1),
      },
    },
  }
)

test.register_message_test(
  "Handle received Lock State from Matter device.", {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.DoorLock.attributes.LockState:build_test_report_data(
          mock_device, 1, clusters.DoorLock.attributes.LockState.LOCKED
        ),
      },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.lock.lock.locked()),
    },
  }
)

test.register_message_test(
  "Handle received BatPercentRemaining from device.", {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.PowerSource.attributes.BatPercentRemaining:build_test_report_data(
          mock_device, 1, 150
        ),
      },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message(
        "main", capabilities.battery.battery(math.floor(150 / 2.0 + 0.5))
      ),
    },
  }
)

local function refresh_commands(dev)
  local req = clusters.DoorLock.attributes.LockState:read(dev, 1)
  req:merge(clusters.PowerSource.attributes.BatPercentRemaining:read(dev, 1))
  return req
end

test.register_message_test(
  "Handle received refresh.", {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        {capability = "refresh", component = "main", command = "refresh", args = {}},
      },
    },
    {
      channel = "matter",
      direction = "send",
      message = {mock_device.id, refresh_commands(mock_device)},
    },
  }
)

local DlAlarmCode = clusters.DoorLock.types.DlAlarmCode
test.register_message_test(
  "Handle DoorLockAlarm event from Matter device.", {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.DoorLock.events.DoorLockAlarm:build_test_event_report(
          mock_device, 1, {alarm_code = DlAlarmCode.FRONT_ESCEUTCHEON_REMOVED}
        ),
      },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.tamperAlert.tamper.detected()),
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.DoorLock.events.DoorLockAlarm:build_test_event_report(
          mock_device, 1, {alarm_code = DlAlarmCode.WRONG_CODE_ENTRY_LIMIT}
        ),
      },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.tamperAlert.tamper.detected()),
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.DoorLock.events.DoorLockAlarm:build_test_event_report(
          mock_device, 1, {alarm_code = DlAlarmCode.FORCED_USER}
        ),
      },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.tamperAlert.tamper.detected()),
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.DoorLock.events.DoorLockAlarm:build_test_event_report(
          mock_device, 1, {alarm_code = DlAlarmCode.DOOR_FORCED_OPEN}
        ),
      },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.tamperAlert.tamper.detected()),
    },
  }
)

local lock_operation_event = {
  lock_operation_type = clusters.DoorLock.types.DlLockOperationType.UNLOCK,
  operation_source = clusters.DoorLock.types.DlOperationSource.MANUAL,
}
test.register_message_test(
  "Handle clear tamper alert detection.", {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.DoorLock.events.DoorLockAlarm:build_test_event_report(
          mock_device, 1, {alarm_code = DlAlarmCode.FRONT_ESCEUTCHEON_REMOVED}
        ),
      },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.tamperAlert.tamper.detected()),
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.DoorLock.events.LockOperation:build_test_event_report(mock_device, 1, lock_operation_event),
      },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.tamperAlert.tamper.clear()),
    },
  }
)

test.register_coroutine_test(
  "Added lifecycle event lock without codes",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })

    mock_device:expect_metadata_update({ profile = "lock-without-codes" })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.tamperAlert.tamper.clear())
    )
end
)

test.run_registered_tests()
