-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"
local clusters = require "st.matter.clusters"
local button_attr = capabilities.button.button
local utils = require "st.utils"
local dkjson = require "dkjson"
local uint32 = require "st.matter.data_types.Uint32"

local mock_device = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("button.yml"),
  manufacturer_info = {vendor_id = 0x0000, product_id = 0x0000},
  matter_version = {hardware = 1, software = 1},
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
          cluster_id = clusters.Switch.ID,
          feature_map = clusters.Switch.types.Feature.MOMENTARY_SWITCH,
          cluster_type = "SERVER",
        }
      },
      device_types = {
        {device_type_id = 0x000F, device_type_revision = 1} -- Generic Switch
      }
    }
  }
})

local mock_device_battery = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("button-battery.yml"),
  manufacturer_info = {vendor_id = 0x0000, product_id = 0x0000},
  matter_version = {hardware = 1, software = 1},
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
          cluster_id = clusters.Switch.ID,
          feature_map = clusters.Switch.types.Feature.MOMENTARY_SWITCH,
          cluster_type = "SERVER",
        },
        {
          cluster_id = clusters.PowerSource.ID,
          cluster_type = "SERVER",
          feature_map = clusters.PowerSource.types.Feature.BATTERY
        },
      },
      device_types = {
        {device_type_id = 0x000F, device_type_revision = 1} -- Generic Switch
      }
    }
  }
})

local function expect_configure_buttons(device)
  test.socket.capability:__expect_send(device:generate_test_message("main", capabilities.button.supportedButtonValues({"pushed"}, {visibility = {displayed = false}})))
  test.socket.capability:__expect_send(device:generate_test_message("main", button_attr.pushed({state_change = false})))
end

local function update_profile()
  test.socket.matter:__queue_receive({mock_device_battery.id, clusters.PowerSource.attributes.AttributeList:build_test_report_data(
    mock_device_battery, 1, {uint32(clusters.PowerSource.attributes.BatPercentRemaining.ID)}
  )})
  expect_configure_buttons(mock_device_battery)
  mock_device_battery:expect_metadata_update({ profile = "button-battery" })
end

local function test_init()
  local CLUSTER_SUBSCRIBE_LIST = {
    clusters.Switch.server.events.InitialPress,
    clusters.Switch.server.events.LongPress,
    clusters.Switch.server.events.ShortRelease,
    clusters.Switch.server.events.MultiPressComplete,
  }

  local subscribe_request = CLUSTER_SUBSCRIBE_LIST[1]:subscribe(mock_device)
  for i, clus in ipairs(CLUSTER_SUBSCRIBE_LIST) do
    if i > 1 then subscribe_request:merge(clus:subscribe(mock_device)) end
  end

  test.disable_startup_messages()
  test.mock_device.add_test_device(mock_device)
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})

  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "init" })
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})

  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
  expect_configure_buttons(mock_device)
  mock_device:expect_metadata_update({ profile = "button" })
  mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
end

local function test_init_battery()
  local CLUSTER_SUBSCRIBE_LIST_BATTERY = {
    clusters.PowerSource.server.attributes.AttributeList,
    clusters.PowerSource.server.attributes.BatPercentRemaining,
    clusters.Switch.server.events.InitialPress,
    clusters.Switch.server.events.LongPress,
    clusters.Switch.server.events.ShortRelease,
    clusters.Switch.server.events.MultiPressComplete,
  }

  local subscribe_request = CLUSTER_SUBSCRIBE_LIST_BATTERY[1]:subscribe(mock_device_battery)
  for i, clus in ipairs(CLUSTER_SUBSCRIBE_LIST_BATTERY) do
    if i > 1 then subscribe_request:merge(clus:subscribe(mock_device_battery)) end
  end

  test.disable_startup_messages()
  test.mock_device.add_test_device(mock_device_battery)
  test.socket.device_lifecycle:__queue_receive({ mock_device_battery.id, "added" })
  test.socket.matter:__expect_send({mock_device_battery.id, subscribe_request})

  test.socket.device_lifecycle:__queue_receive({ mock_device_battery.id, "init" })
  test.socket.matter:__expect_send({mock_device_battery.id, subscribe_request})

  test.socket.device_lifecycle:__queue_receive({ mock_device_battery.id, "doConfigure" })
  mock_device_battery:expect_metadata_update({ provisioning_state = "PROVISIONED" })
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Simulate the profile change update taking affect and the device info changing",
  function()
    test.socket.matter:__set_channel_ordering("relaxed")
    update_profile()
    test.wait_for_events()
    local device_info_copy = utils.deep_copy(mock_device_battery.raw_st_data)
    device_info_copy.profile.id = "buttons-battery"
    local device_info_json = dkjson.encode(device_info_copy)
    test.socket.device_lifecycle:__queue_receive({ mock_device_battery.id, "infoChanged", device_info_json })
    -- due to the AttributeList being processed in update_profile, setting profiling_data.BATTERY_SUPPORT,
    -- subsequent subscriptions will not include AttributeList.
    local UPDATED_CLUSTER_SUBSCRIBE_LIST = {
      clusters.PowerSource.server.attributes.BatPercentRemaining,
      clusters.Switch.server.events.InitialPress,
      clusters.Switch.server.events.LongPress,
      clusters.Switch.server.events.ShortRelease,
      clusters.Switch.server.events.MultiPressComplete,
    }
    local updated_subscribe_request = UPDATED_CLUSTER_SUBSCRIBE_LIST[1]:subscribe(mock_device_battery)
    for i, clus in ipairs(UPDATED_CLUSTER_SUBSCRIBE_LIST) do
      if i > 1 then updated_subscribe_request:merge(clus:subscribe(mock_device_battery)) end
    end
    test.socket.matter:__expect_send({mock_device_battery.id, updated_subscribe_request})
    expect_configure_buttons(mock_device_battery)
  end,
  { test_init = test_init_battery },
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Handle received BatPercentRemaining from device.",
  function()
    update_profile()
    test.socket.matter:__queue_receive(
      {
        mock_device_battery.id,
        clusters.PowerSource.attributes.BatPercentRemaining:build_test_report_data(
          mock_device_battery, 1, 150
        )
      }
    )
    test.socket.capability:__expect_send(
      mock_device_battery:generate_test_message(
        "main", capabilities.battery.battery(math.floor(150 / 2.0 + 0.5))
      )
    )
  end,
  { test_init = test_init_battery },
  {
     min_api_version = 19
  }
)

test.register_message_test(
  "Handle single press sequence, no hold", {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.Switch.events.InitialPress:build_test_event_report(
          mock_device, 1, {new_position = 1}  --move to position 1
        ),
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", button_attr.pushed({state_change = true})) --should send initial press
    }
  },
  {
     min_api_version = 19
  }
)

test.register_message_test(
  "Handle single press sequence, with hold", {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.Switch.events.InitialPress:build_test_event_report(
          mock_device, 1, {new_position = 1}
        ),
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", button_attr.pushed({state_change = true})) --should send initial press
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.Switch.events.LongPress:build_test_event_report(
          mock_device, 1, {new_position = 1}
        ),
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", button_attr.held({state_change = true}))
    }
  },
  {
     min_api_version = 19
  }
)

test.register_message_test(
  "Handle release after short press", {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.Switch.events.InitialPress:build_test_event_report(
          mock_device, 1, {new_position = 1}
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", button_attr.pushed({state_change = true}))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.Switch.events.ShortRelease:build_test_event_report(
          mock_device, 1, {previous_position = 1}
        )
      }
    },
    { -- this is a double event because the test device in this test shouldn't support the above event
      -- but we handle it anyway
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", button_attr.pushed({state_change = true}))
    },
  },
  {
     min_api_version = 19
  }
)

test.register_message_test(
  "Handle release after long press", {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.Switch.events.InitialPress:build_test_event_report(
          mock_device, 1, {new_position = 1}
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", button_attr.pushed({state_change = true}))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.Switch.events.LongPress:build_test_event_report(
          mock_device, 1, {new_position = 1}
        ),
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", button_attr.held({state_change = true}))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.Switch.events.LongRelease:build_test_event_report(
          mock_device, 1, {previous_position = 1}
        )
      }
    },
  },
  {
     min_api_version = 19
  }
)

test.register_message_test(
  "Receiving a max press attribute of 2 should emit correct event", {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.Switch.attributes.MultiPressMax:build_test_report_data(
          mock_device, 1, 2
        )
      },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",
        capabilities.button.supportedButtonValues({"pushed", "double"}, {visibility = {displayed = false}}))
    },
  },
  {
     min_api_version = 19
  }
)

test.register_message_test(
  "Receiving a max press attribute of 3 should emit correct event", {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.Switch.attributes.MultiPressMax:build_test_report_data(
          mock_device, 1, 3
        )
      },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",
        capabilities.button.supportedButtonValues({"pushed", "double", "pushed_3x"}, {visibility = {displayed = false}}))
    },
  },
  {
     min_api_version = 19
  }
)

test.register_message_test(
  "Receiving a max press attribute of greater than 6 should only emit up to pushed_6x", {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.Switch.attributes.MultiPressMax:build_test_report_data(
          mock_device, 1, 7
        )
      },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",
        capabilities.button.supportedButtonValues({"pushed", "double", "pushed_3x", "pushed_4x", "pushed_5x", "pushed_6x"}, {visibility = {displayed = false}}))
    },
  },
  {
     min_api_version = 19
  }
)

test.register_message_test(
  "Handle double press", {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.Switch.events.InitialPress:build_test_event_report(
          mock_device, 1, {new_position = 1}
        )
      }
    },
    { -- again, on a device that reports that it supports double press, this event
      -- will not be generated. See a multi-button test file for that case
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", button_attr.pushed({state_change = true}))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.Switch.events.MultiPressComplete:build_test_event_report(
          mock_device, 1, {new_position = 1, total_number_of_presses_counted = 2, previous_position = 0}
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", button_attr.double({state_change = true}))
    },
  },
  {
     min_api_version = 19
  }
)

test.register_message_test(
  "Handle multi press for 4 times", {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.Switch.events.InitialPress:build_test_event_report(
          mock_device, 1, {new_position = 1, total_number_of_presses_counted = 1, previous_position = 0}
        )
      }
    },
    { -- again, on a device that reports that it supports double press, this event
      -- will not be generated. See the multi-button test file for that case
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", button_attr.pushed({state_change = true}))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.Switch.events.MultiPressComplete:build_test_event_report(
          mock_device, 1, {new_position = 1, total_number_of_presses_counted = 4, previous_position = 0}
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", button_attr.pushed_4x({state_change = true}))
    },
  },
  {
     min_api_version = 19
  }
)

local function reset_battery_profiling_info()
  local fields = require "switch_utils.fields"
  mock_device:set_field(fields.profiling_data.BATTERY_SUPPORT, fields.battery_support.NO_BATTERY, {persist=true})
end

test.register_coroutine_test(
  "Test profile does not change to button-battery when battery percent remaining attribute (attribute ID 12) is not available",
  function()
    reset_battery_profiling_info()
    test.wait_for_events()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        clusters.PowerSource.attributes.AttributeList:build_test_report_data(mock_device, 1, {uint32(10)})
      }
    )
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Test profile change to button-batteryLevel when battery percent remaining attribute (attribute ID 14) is available",
  function()
    reset_battery_profiling_info()
    test.wait_for_events()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        clusters.PowerSource.attributes.AttributeList:build_test_report_data(mock_device, 1, {uint32(
          clusters.PowerSource.attributes.BatChargeLevel.ID
        )})
      }
    )
    expect_configure_buttons(mock_device)
    mock_device:expect_metadata_update({ profile = "button-batteryLevel" })
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Test profile change to button-battery when battery percent remaining attribute (attribute ID 12) is available",
  function()
    reset_battery_profiling_info()
    test.wait_for_events()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        clusters.PowerSource.attributes.AttributeList:build_test_report_data(mock_device, 1, {uint32(
          clusters.PowerSource.attributes.BatPercentRemaining.ID
        )})
      }
    )
    expect_configure_buttons(mock_device)
    mock_device:expect_metadata_update({ profile = "button-battery" })
  end,
  {
     min_api_version = 19
  }
)

test.run_registered_tests()
