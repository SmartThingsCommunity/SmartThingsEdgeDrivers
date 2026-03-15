-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"
local utils = require "st.utils"
local dkjson = require "dkjson"

local clusters = require "st.matter.generated.zap_clusters"
local button_attr = capabilities.button.button

local mock_device = test.mock_device.build_test_matter_device(
  {
    profile = t_utils.get_profile_definition("6-button-motion.yml"), -- on a real device we would switch to this, rather than fingerprint to it
    manufacturer_info = {vendor_id = 0x0000, product_id = 0x0000},
    matter_version = {hardware = 1, software = 1},
      endpoints = {
    {
      endpoint_id = 0,
      clusters = {},
      device_types = {}
    },
    {
      endpoint_id = 10,
      clusters = {
        {
          cluster_id = clusters.Switch.ID,
          feature_map = clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH,
          cluster_type = "SERVER"
        },
      },
      device_types = {
        {device_type_id = 0x000F, device_type_revision = 1} -- Generic Switch
      }
    },
    {
      endpoint_id = 20,
      clusters = {
        {
          cluster_id = clusters.Switch.ID,
          feature_map = clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH | clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_RELEASE,
          cluster_type = "SERVER"
        },
      },
      device_types = {
        {device_type_id = 0x000F, device_type_revision = 1} -- Generic Switch
      }
    },
    {
      endpoint_id = 30,
      clusters = {
        {
          cluster_id = clusters.Switch.ID,
          feature_map = clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH | clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_LONG_PRESS,
          cluster_type = "SERVER"
        },
      },
      device_types = {
        {device_type_id = 0x000F, device_type_revision = 1} -- Generic Switch
      }
    },
    {
      endpoint_id = 40,
      clusters = {
        {
          cluster_id = clusters.Switch.ID,
          feature_map = clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH | clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_LONG_PRESS,
          cluster_type = "SERVER"
        },
      },
      device_types = {
        {device_type_id = 0x000F, device_type_revision = 1} -- Generic Switch
      }
    },
    {
      endpoint_id = 50,
      clusters = {
        {
          cluster_id = clusters.Switch.ID,
          feature_map = clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH | clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_MULTI_PRESS,
          cluster_type = "SERVER"
        },
      },
      device_types = {
        {device_type_id = 0x000F, device_type_revision = 1} -- Generic Switch
      }
    },
    {
      endpoint_id = 60,
      clusters = {
        {
          cluster_id = clusters.Switch.ID,
          feature_map = clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH |
            clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_MULTI_PRESS |
            clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_LONG_PRESS,
          cluster_type = "SERVER"
        },
      },
      device_types = {
        {device_type_id = 0x000F, device_type_revision = 1} -- Generic Switch
      }
    },
    {
      endpoint_id = 70,
      clusters = {
        {cluster_id = clusters.OccupancySensing.ID, cluster_type = "SERVER"},
      },
      device_types = {
        {device_type_id = 0x0107, device_type_revision = 1}  -- OccupancySensor
      }
    },
  },
}
)

-- add device for each mock device
local CLUSTER_SUBSCRIBE_LIST ={
  clusters.OccupancySensing.attributes.Occupancy,
  clusters.Switch.server.events.InitialPress,
  clusters.Switch.server.events.LongPress,
  clusters.Switch.server.events.ShortRelease,
  clusters.Switch.server.events.MultiPressComplete,
}

local function expect_configure_buttons()
  test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.button.supportedButtonValues({"pushed"}, {visibility = {displayed = false}})))
  test.socket.capability:__expect_send(mock_device:generate_test_message("main", button_attr.pushed({state_change = false})))

  test.socket.capability:__expect_send(mock_device:generate_test_message("button2", capabilities.button.supportedButtonValues({"pushed", "held"}, {visibility = {displayed = false}})))
  test.socket.capability:__expect_send(mock_device:generate_test_message("button2", button_attr.pushed({state_change = false})))

  test.socket.capability:__expect_send(mock_device:generate_test_message("button3", capabilities.button.supportedButtonValues({"pushed", "held"}, {visibility = {displayed = false}})))
  test.socket.capability:__expect_send(mock_device:generate_test_message("button3", button_attr.pushed({state_change = false})))

  test.socket.capability:__expect_send(mock_device:generate_test_message("button4", capabilities.button.supportedButtonValues({"pushed", "held"}, {visibility = {displayed = false}})))
  test.socket.capability:__expect_send(mock_device:generate_test_message("button4", button_attr.pushed({state_change = false})))

  test.socket.matter:__expect_send({mock_device.id, clusters.Switch.attributes.MultiPressMax:read(mock_device, 50)})
  test.socket.capability:__expect_send(mock_device:generate_test_message("button5", button_attr.pushed({state_change = false})))

  test.socket.matter:__expect_send({mock_device.id, clusters.Switch.attributes.MultiPressMax:read(mock_device, 60)})
  test.socket.capability:__expect_send(mock_device:generate_test_message("button6", button_attr.pushed({state_change = false})))
end

-- All messages queued and expectations set are done before the driver is actually run
local function test_init()
  -- we dont want the integration test framework to generate init/doConfigure, we are doing that here
  -- so we can set the proper expectations on those events.
  test.disable_startup_messages()
  test.mock_device.add_test_device(mock_device) -- make sure the cache is populated

  -- added sets a bunch of fields on the device, and calls init
  local subscribe_request = CLUSTER_SUBSCRIBE_LIST[1]:subscribe(mock_device)
  for i, clus in ipairs(CLUSTER_SUBSCRIBE_LIST) do
    if i > 1 then subscribe_request:merge(clus:subscribe(mock_device)) end
  end
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })

  -- init results in subscription interaction
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "init" })

  --doConfigure sets the provisioning state to provisioned
  mock_device:expect_metadata_update({ profile = "6-button-motion" })
  mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  expect_configure_buttons()
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })

  -- simulate the profile change update taking affect and the device info changing
  local device_info_copy = utils.deep_copy(mock_device.raw_st_data)
  device_info_copy.profile.id = "6-buttons-motion"
  local device_info_json = dkjson.encode(device_info_copy)
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "infoChanged", device_info_json })
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})
  expect_configure_buttons()
end
test.set_test_init_function(test_init)

test.register_message_test(
  "Handle single press sequence, no hold", {
  {
    channel = "matter",
    direction = "receive",
    message = {
      mock_device.id,
      clusters.Switch.events.InitialPress:build_test_event_report(
        mock_device, 10, {new_position = 1}  --move to position 1?
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
  "Handle single press sequence for short release-supported button", {
  {
    channel = "matter",
    direction = "receive",
    message = {
      mock_device.id,
      clusters.Switch.events.InitialPress:build_test_event_report(
        mock_device, 20, {new_position = 1}  --move to position 1?
      ),
    }
  },
  {
    channel = "matter",
    direction = "receive",
    message = {
      mock_device.id,
      clusters.Switch.events.ShortRelease:build_test_event_report(
        mock_device, 20, {previous_position = 0}  --move to position 1?
      ),
    }
  },
  {
    channel = "capability",
    direction = "send",
    message = mock_device:generate_test_message("button2", button_attr.pushed({state_change = true})) --should send initial press
  }
},
{
   min_api_version = 19
}
)

test.register_coroutine_test(
  "Handle single press sequence for emulated hold on short-release-only button",
  function ()
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.Switch.events.InitialPress:build_test_event_report(
        mock_device, 20, {new_position = 1}
      )
    })
    test.wait_for_events()
    test.mock_time.advance_time(2)
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.Switch.events.ShortRelease:build_test_event_report(
        mock_device, 20, {previous_position = 0}
      )
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("button2", button_attr.held({state_change = true})))
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Handle single press sequence for a long hold on long-release-capable button", -- only a long press event should generate a held event
  function ()
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.Switch.events.InitialPress:build_test_event_report(
        mock_device, 30, {new_position = 1}
      )
    })
    test.wait_for_events()
    test.mock_time.advance_time(2)
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.Switch.events.ShortRelease:build_test_event_report(
        mock_device, 30, {previous_position = 0}
      )
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("button3", button_attr.pushed({state_change = true})))
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Handle single press sequence for a long hold on multi button", -- pushes should only be generated from multiPressComplete events
  function ()
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.Switch.events.InitialPress:build_test_event_report(
        mock_device, 50, {new_position = 1}
      )
    })
    test.wait_for_events()
    test.mock_time.advance_time(2)
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.Switch.events.ShortRelease:build_test_event_report(
        mock_device, 50, {previous_position = 0}
      )
    })
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Handle single press sequence for a multi press on multi button",
  function ()
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.Switch.events.InitialPress:build_test_event_report(
        mock_device, 60, {new_position = 1}
      )
    })
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.Switch.events.ShortRelease:build_test_event_report(
        mock_device, 60, {previous_position = 0}
      )
    })
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.Switch.events.InitialPress:build_test_event_report(
        mock_device, 60, {new_position = 1}
      )
    })
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.Switch.events.MultiPressOngoing:build_test_event_report(
        mock_device, 60, {new_position = 1, current_number_of_presses_counted = 2}
      )
    })
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.Switch.events.MultiPressComplete:build_test_event_report(
        mock_device, 60, {new_position = 0, total_number_of_presses_counted = 2, previous_position = 1}
      )
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("button6", button_attr.double({state_change = true})))
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Handle long press sequence for a long hold on long-release-capable button", -- only a long press event should generate a held event
  function ()
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.Switch.events.InitialPress:build_test_event_report(
        mock_device, 40, {new_position = 1}
      )
    })
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.Switch.events.LongPress:build_test_event_report(
        mock_device, 40, {new_position = 1}
      )
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("button4", button_attr.held({state_change = true})))
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.Switch.events.LongRelease:build_test_event_report(
        mock_device, 40, {previous_position = 0}
      )
    })
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Occupancy reports should generate correct messages",
  function ()
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.OccupancySensing.attributes.Occupancy:build_test_report_data(mock_device, 70, 1)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.motionSensor.motion.active()))
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.OccupancySensing.attributes.Occupancy:build_test_report_data(mock_device, 70, 0)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.motionSensor.motion.inactive()))
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Handle long press sequence for a long hold on multi button",
  function ()
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.Switch.events.InitialPress:build_test_event_report(
        mock_device, 60, {new_position = 1}
      )
    })
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.Switch.events.LongPress:build_test_event_report(
        mock_device, 60, {new_position = 1}
      )
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("button6", button_attr.held({state_change = true})))
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.Switch.events.LongRelease:build_test_event_report(
        mock_device, 60, {previous_position = 0}
      )
    })
  end,
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
        mock_device, 10, {new_position = 1}
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
        mock_device, 10, {new_position = 1}
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
        mock_device, 10, {new_position = 1}
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
        mock_device, 10, {previous_position = 1}
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
        mock_device, 10, {new_position = 1}
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
        mock_device, 10, {new_position = 1}
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
        mock_device, 10, {previous_position = 1}
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
          mock_device, 10, 2
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
          mock_device, 60, 3
        )
      },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("button6",
        capabilities.button.supportedButtonValues({"pushed", "double", "held", "pushed_3x"}, {visibility = {displayed = false}}))
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
          mock_device, 10, 7
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
        mock_device, 10, {new_position = 1}
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
        mock_device, 10, {new_position = 1, total_number_of_presses_counted = 2, previous_position = 0}
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
        mock_device, 10, {new_position = 1}
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
        mock_device, 10, {new_position = 1, total_number_of_presses_counted = 4, previous_position=0}
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

test.register_message_test(
    "Receiving a max press attribute of 2 should emit correct event", {
      {
        channel = "matter",
        direction = "receive",
        message = {
          mock_device.id,
          clusters.Switch.attributes.MultiPressMax:build_test_report_data(
              mock_device, 50, 2
          )
        },
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("button5",
            capabilities.button.supportedButtonValues({"pushed", "double"}, {visibility = {displayed = false}}))
      },
    },
    {
       min_api_version = 19
    }
)

test.register_message_test(
  "Handle a long press including MultiPressComplete", {
  {
    channel = "matter",
    direction = "receive",
    message = {
      mock_device.id,
      clusters.Switch.events.InitialPress:build_test_event_report(
        mock_device, 60, {new_position = 1}
      )
    }
  },
  {
    channel = "matter",
    direction = "receive",
    message = {
      mock_device.id,
      clusters.Switch.events.LongPress:build_test_event_report(
        mock_device, 60, {new_position = 1}
      )
    }
  },
  {
    channel = "capability",
    direction = "send",
    message = mock_device:generate_test_message("button6", button_attr.held({state_change = true}))
  },
  {
    channel = "matter",
    direction = "receive",
    message = {
      mock_device.id,
      clusters.Switch.events.MultiPressComplete:build_test_event_report(
        mock_device, 60, {new_position = 0, total_number_of_presses_counted = 1, previous_position=0}
      )
    }
  }
  -- no double event
},
{
   min_api_version = 19
}
)

test.register_message_test(
  "Handle long press followed by single press", {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.Switch.events.InitialPress:build_test_event_report(
                mock_device, 60, {new_position = 1}
        )
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.Switch.events.LongPress:build_test_event_report(
                mock_device, 60, {new_position = 1}
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("button6", button_attr.held({state_change = true}))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.Switch.events.InitialPress:build_test_event_report(
                mock_device, 60, {new_position = 1}
        )
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.Switch.events.MultiPressComplete:build_test_event_report(
                mock_device, 60, {new_position = 0, total_number_of_presses_counted = 1, previous_position=0}
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("button6", button_attr.pushed({state_change = true}))
    }
  },
  {
     min_api_version = 19
  }
)
-- run the tests
test.run_registered_tests()
