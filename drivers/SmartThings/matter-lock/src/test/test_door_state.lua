-- Copyright 2023 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local test = require "integration_test"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"
local clusters = require "st.matter.clusters"
local cluster_base = require "st.matter.cluster_base"
local DoorLock = clusters.DoorLock

local mock_device_door_state_disabled = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("lock-modular.yml"),
  manufacturer_info = {
    vendor_id = 0x115f,
    product_id = 0x2802,
  },
  endpoints = {
    {
      endpoint_id = 0,
      clusters = {
        { cluster_id = clusters.BasicInformation.ID, cluster_type = "SERVER" },
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
          feature_map = 0x20, -- DPS
        }
      },
      device_types = {
        { device_type_id = 0x000A, device_type_revision = 1 } -- Door Lock
      }
    }
  }
})

local enabled_optional_component_capability_pairs = {{ "main", {capabilities.doorState.ID} }}
local mock_device = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition(
    "lock-modular.yml",
    {enabled_optional_capabilities = enabled_optional_component_capability_pairs}
  ),
  manufacturer_info = {
    vendor_id = 0x115f,
    product_id = 0x2802,
  },
  endpoints = {
    {
      endpoint_id = 0,
      clusters = {
        { cluster_id = clusters.BasicInformation.ID, cluster_type = "SERVER" },
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
          feature_map = 0x20, -- DPS
        }
      },
      device_types = {
        { device_type_id = 0x000A, device_type_revision = 1 } -- Door Lock
      }
    }
  }
})

local DoorLockFeatureMapAttr = {ID = 0xFFFC, cluster = DoorLock.ID}
local function test_init()
  test.disable_startup_messages()
  local subscribe_request = DoorLock.attributes.LockState:subscribe(mock_device)
  subscribe_request:merge(DoorLock.attributes.DoorState:subscribe(mock_device))
  subscribe_request:merge(DoorLock.attributes.OperatingMode:subscribe(mock_device))
  subscribe_request:merge(cluster_base.subscribe(mock_device_door_state_disabled, nil, DoorLockFeatureMapAttr.cluster, DoorLockFeatureMapAttr.ID))
  subscribe_request:merge(DoorLock.events.LockOperation:subscribe(mock_device))
  subscribe_request:merge(DoorLock.events.DoorLockAlarm:subscribe(mock_device))
  test.mock_device.add_test_device(mock_device)
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
  test.socket.capability:__expect_send(
    mock_device:generate_test_message("main", capabilities.lockAlarm.alarm.clear({state_change = true}))
  )
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "init" })
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
  mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
end

test.set_test_init_function(test_init)

local function test_init_door_state_disabled()
  test.disable_startup_messages()
  local subscribe_request = DoorLock.attributes.LockState:subscribe(mock_device_door_state_disabled)
  subscribe_request:merge(DoorLock.attributes.DoorState:subscribe(mock_device_door_state_disabled))
  subscribe_request:merge(DoorLock.attributes.OperatingMode:subscribe(mock_device_door_state_disabled))
  subscribe_request:merge(cluster_base.subscribe(mock_device_door_state_disabled, nil, DoorLockFeatureMapAttr.cluster, DoorLockFeatureMapAttr.ID))
  subscribe_request:merge(DoorLock.events.LockOperation:subscribe(mock_device_door_state_disabled))
  subscribe_request:merge(DoorLock.events.DoorLockAlarm:subscribe(mock_device_door_state_disabled))
  test.mock_device.add_test_device(mock_device_door_state_disabled)
  test.socket.device_lifecycle:__queue_receive({ mock_device_door_state_disabled.id, "added" })
  test.socket.capability:__expect_send(
    mock_device_door_state_disabled:generate_test_message("main", capabilities.lockAlarm.alarm.clear({state_change = true}))
  )
  test.socket.device_lifecycle:__queue_receive({ mock_device_door_state_disabled.id, "init" })
  test.socket.matter:__expect_send({mock_device_door_state_disabled.id, subscribe_request})
  test.socket.device_lifecycle:__queue_receive({ mock_device_door_state_disabled.id, "doConfigure" })
  mock_device_door_state_disabled:expect_metadata_update({ provisioning_state = "PROVISIONED" })
end

test.register_coroutine_test(
  "Check that the device is updated with correct capabilities based on the profile and attributes.",
  function ()
    test.socket.matter:__queue_receive({
      mock_device_door_state_disabled.id,
      DoorLock.attributes.DoorState:build_test_report_data(mock_device_door_state_disabled, 1, DoorLock.attributes.DoorState.DOOR_CLOSED)
    })
    test.socket.capability:__expect_send(
      mock_device_door_state_disabled:generate_test_message("main", capabilities.lock.supportedLockValues({"locked", "unlocked", "not fully locked"}, {visibility = {displayed = false}}))
    )
    test.socket.capability:__expect_send(
      mock_device_door_state_disabled:generate_test_message("main", capabilities.lock.supportedLockCommands({"lock", "unlock"}, {visibility = {displayed = false}}))
    )

    mock_device_door_state_disabled:expect_metadata_update({ profile = "lock-modular", optional_component_capabilities = {{"main", {"doorState"}}}})
  end,
  { test_init = test_init_door_state_disabled }
)


test.register_coroutine_test(
  "Handle received DoorState.DOOR_CLOSED from Matter device.",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        DoorLock.attributes.DoorState:build_test_report_data(
          mock_device, 1, DoorLock.attributes.DoorState.DOOR_CLOSED
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.doorState.doorState.closed())
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.doorState.supportedDoorStates({"closed"}, {visibility={displayed=false}}))
    )
  end
)

test.register_coroutine_test(
  "Handle received DoorState.DOOR_JAMMED from Matter device.",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        DoorLock.attributes.DoorState:build_test_report_data(
          mock_device, 1, DoorLock.attributes.DoorState.DOOR_JAMMED
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.doorState.doorState.jammed())
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.doorState.supportedDoorStates({"jammed"}, {visibility={displayed=false}}))
    )
  end
)

test.register_coroutine_test(
  "Handle received DoorState.DOOR_FORCED_OPEN from Matter device.",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        DoorLock.attributes.DoorState:build_test_report_data(
          mock_device, 1, DoorLock.attributes.DoorState.DOOR_FORCED_OPEN
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.doorState.doorState.forcedOpen())
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.doorState.supportedDoorStates({"forcedOpen"}, {visibility={displayed=false}}))
    )
  end
)

test.register_coroutine_test(
  "Handle received DoorState.DOOR_UNSPECIFIED_ERROR from Matter device.",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        DoorLock.attributes.DoorState:build_test_report_data(
          mock_device, 1, DoorLock.attributes.DoorState.DOOR_UNSPECIFIED_ERROR
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.doorState.doorState.unspecifiedError())
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.doorState.supportedDoorStates({"unspecifiedError"}, {visibility={displayed=false}}))
    )
  end
)

test.register_coroutine_test(
  "Handle received DoorState.DOOR_AJAR from Matter device.",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        DoorLock.attributes.DoorState:build_test_report_data(
          mock_device, 1, DoorLock.attributes.DoorState.DOOR_AJAR
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.doorState.doorState.ajar())
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.doorState.supportedDoorStates({"ajar"}, {visibility={displayed=false}}))
    )
  end
)

test.register_coroutine_test(
  "Handle received DoorState.DOOR_OPEN from Matter device, and then DoorState.DOOR_AJAR, ensuring supportedDoorStates is updated to include both states.",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        DoorLock.attributes.DoorState:build_test_report_data(
          mock_device, 1, DoorLock.attributes.DoorState.DOOR_OPEN
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.doorState.doorState.open())
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.doorState.supportedDoorStates({"open"}, {visibility={displayed=false}}))
    )
    test.wait_for_events()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        DoorLock.attributes.DoorState:build_test_report_data(
          mock_device, 1, DoorLock.attributes.DoorState.DOOR_AJAR
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.doorState.doorState.ajar())
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.doorState.supportedDoorStates({"open", "ajar"}, {visibility={displayed=false}}))
    )
  end
)

test.run_registered_tests()
