-- Copyright © 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local t_utils = require "integration_test.utils"
local test = require "integration_test"
local dkjson = require "dkjson"
local utils = require "st.utils"

local mock_device = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("garage-door-battery.yml"),
  manufacturer_info = {vendor_id = 0x1407, product_id = 0x1098},
  endpoints = {
    {
      endpoint_id = 0,
      clusters = {
        {cluster_id = clusters.Basic.ID, cluster_type = "SERVER"},
      },
      device_types = {
        {device_type_id = 0x0016, device_type_revision = 1} -- RootNode
      }
    },
    {
      endpoint_id = 1,
      clusters = {
        {
          cluster_id = clusters.OnOff.ID,
          cluster_type = "SERVER",
          cluster_revision = 1,
          feature_map = 0,
        },
        {
          cluster_id = clusters.PowerSource.ID,
          cluster_type = "SERVER",
          feature_map = clusters.PowerSource.types.Feature.BATTERY,
        },
      },
      device_types = {
        {device_type_id = 0x010A, device_type_revision = 1} -- On/Off Plug-in Unit
      }
    }
  }
})

-- The subscribe list matches the profile capabilities:
--   doorControl -> OnOff.attributes.OnOff
--   battery    -> PowerSource.attributes.BatPercentRemaining
-- The subdriver overrides device_init, so the main driver's extend_device("subscribe", ...)
-- is not called; the default device:subscribe() is used, which does not add AttributeList.
local cluster_subscribe_list = {
  clusters.OnOff.attributes.OnOff,
  clusters.PowerSource.attributes.BatPercentRemaining,
}

local function test_init()
  test.disable_startup_messages()
  test.mock_device.add_test_device(mock_device)

  local subscribe_request = cluster_subscribe_list[1]:subscribe(mock_device)
  for i, clus in ipairs(cluster_subscribe_list) do
    if i > 1 then subscribe_request:merge(clus:subscribe(mock_device)) end
  end

  -- added lifecycle: subdriver overrides device_added to a no-op so no subscribe here
  test.socket.device_lifecycle:__queue_receive({mock_device.id, "added"})

  -- init lifecycle: device_init subscribes
  test.socket.device_lifecycle:__queue_receive({mock_device.id, "init"})
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})

  -- doConfigure: sets battery support field and updates profile metadata
  test.socket.device_lifecycle:__queue_receive({mock_device.id, "doConfigure"})
  mock_device:expect_metadata_update({profile = "garage-door-battery"})
  mock_device:expect_metadata_update({provisioning_state = "PROVISIONED"})
end

test.set_test_init_function(test_init)

-- ── Attribute handler tests ──────────────────────────────────────────────────

test.register_message_test(
  "OnOff true should emit door.open",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.OnOff.attributes.OnOff:build_test_report_data(mock_device, 1, true)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.doorControl.door.open())
    }
  }
)

test.register_message_test(
  "OnOff false should emit door.closed",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.OnOff.attributes.OnOff:build_test_report_data(mock_device, 1, false)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.doorControl.door.closed())
    }
  }
)

-- ── Capability command tests ─────────────────────────────────────────────────

test.register_message_test(
  "doorControl open command should emit opening then send OnOff.On",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        {capability = "doorControl", component = "main", command = "open", args = {}}
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.doorControl.door.opening())
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.OnOff.server.commands.On(mock_device, 1)
      }
    }
  }
)

test.register_message_test(
  "doorControl close command should emit closing then send OnOff.Off",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        {capability = "doorControl", component = "main", command = "close", args = {}}
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.doorControl.door.closing())
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.OnOff.server.commands.Off(mock_device, 1)
      }
    }
  }
)

-- ── Battery attribute tests ───────────────────────────────────────────────────

test.register_message_test(
  "BatPercentRemaining report should emit correct battery percentage",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.PowerSource.attributes.BatPercentRemaining:build_test_report_data(mock_device, 1, 200)
      }
    },
    {
      channel = "capability",
      direction = "send",
      -- BatPercentRemaining is in units of 0.5%, so 200 = 100%
      message = mock_device:generate_test_message("main", capabilities.battery.battery(100))
    }
  }
)

test.register_message_test(
  "BatPercentRemaining report of 150 should emit 75% battery",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.PowerSource.attributes.BatPercentRemaining:build_test_report_data(mock_device, 1, 150)
      }
    },
    {
      channel = "capability",
      direction = "send",
      -- 150 * 0.5 = 75%
      message = mock_device:generate_test_message("main", capabilities.battery.battery(75))
    }
  }
)

-- ── Profile / driverSwitched tests ────────────────────────────────────────────

test.register_coroutine_test(
  "doConfigure should set garage-door-battery profile",
  function()
    test.socket.device_lifecycle:__queue_receive({mock_device.id, "doConfigure"})
    mock_device:expect_metadata_update({profile = "garage-door-battery"})
    mock_device:expect_metadata_update({provisioning_state = "PROVISIONED"})
  end,
  {min_api_version = 17}
)

test.register_coroutine_test(
  "driverSwitched should restore garage-door-battery profile",
  function()
    test.socket.device_lifecycle:__queue_receive({mock_device.id, "driverSwitched"})
    mock_device:expect_metadata_update({profile = "garage-door-battery"})
    mock_device:expect_metadata_update({provisioning_state = "PROVISIONED"})
  end,
  {min_api_version = 17}
)


local mock_device_misprofiled = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("light-binary.yml"),
  manufacturer_info = {vendor_id = 0x1407, product_id = 0x1098},
  endpoints = {
    {
      endpoint_id = 0,
      clusters = {
        {cluster_id = clusters.Basic.ID, cluster_type = "SERVER"},
      },
      device_types = {
        {device_type_id = 0x0016, device_type_revision = 1} -- RootNode
      }
    },
    {
      endpoint_id = 1,
      clusters = {
        {
          cluster_id = clusters.OnOff.ID,
          cluster_type = "SERVER",
          cluster_revision = 1,
          feature_map = 0,
        },
        {
          cluster_id = clusters.PowerSource.ID,
          cluster_type = "SERVER",
          feature_map = clusters.PowerSource.types.Feature.BATTERY,
        },
      },
      device_types = {
        {device_type_id = 0x010A, device_type_revision = 1} -- On/Off Plug-in Unit
      }
    }
  }
})

test.register_coroutine_test(
  "doConfigure should correct profile if misprofiled",
  function()
    test.disable_startup_messages()
    test.mock_device.add_test_device(mock_device_misprofiled)

    local subscribe_request = cluster_subscribe_list[1]:subscribe(mock_device_misprofiled)
    for i, clus in ipairs(cluster_subscribe_list) do
      if i > 1 then subscribe_request:merge(clus:subscribe(mock_device_misprofiled)) end
    end

    -- added lifecycle: subdriver overrides device_added to a no-op so no subscribe here
    test.socket.device_lifecycle:__queue_receive({mock_device_misprofiled.id, "added"})

    -- init lifecycle: device_init subscribes
    test.socket.device_lifecycle:__queue_receive({mock_device_misprofiled.id, "init"})
    test.socket.matter:__expect_send({mock_device_misprofiled.id, subscribe_request})

    -- doConfigure: sets battery support field and updates profile metadata
    test.socket.device_lifecycle:__queue_receive({mock_device_misprofiled.id, "doConfigure"})
    mock_device_misprofiled:expect_metadata_update({profile = "garage-door-battery"})
    mock_device_misprofiled:expect_metadata_update({provisioning_state = "PROVISIONED"})
  end,
  {
    test_init = function() test.mock_device.add_test_device(mock_device_misprofiled) end,
  }
)

local mock_device = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("12-button-keyboard.yml"),
  manufacturer_info = {vendor_id = 0x1407, product_id = 0x1388},
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
          cluster_type = "SERVER"
        }
      },
      device_types = {
        {device_type_id = 0x000F, device_type_revision = 1} -- Generic Switch
      }
    },
    {
      endpoint_id = 2,
      clusters = {
        {
          cluster_id = clusters.Switch.ID,
          feature_map = clusters.Switch.types.Feature.MOMENTARY_SWITCH,
          cluster_type = "SERVER"
        }
      },
      device_types = {
        {device_type_id = 0x000F, device_type_revision = 1} -- Generic Switch
      }
    },
    {
      endpoint_id = 3,
      clusters = {
        {
          cluster_id = clusters.Switch.ID,
          feature_map = clusters.Switch.types.Feature.MOMENTARY_SWITCH,
          cluster_type = "SERVER"
        }
      },
      device_types = {
        {device_type_id = 0x000F, device_type_revision = 1} -- Generic Switch
      }
    },
    {
      endpoint_id = 4,
      clusters = {
        {
          cluster_id = clusters.Switch.ID,
          feature_map = clusters.Switch.types.Feature.MOMENTARY_SWITCH,
          cluster_type = "SERVER"
        }
      },
      device_types = {
        {device_type_id = 0x000F, device_type_revision = 1} -- Generic Switch
      }
    },
    {
      endpoint_id = 5,
      clusters = {
        {
          cluster_id = clusters.Switch.ID,
          feature_map = clusters.Switch.types.Feature.MOMENTARY_SWITCH,
          cluster_type = "SERVER"
        }
      },
      device_types = {
        {device_type_id = 0x000F, device_type_revision = 1} -- Generic Switch
      }
    },
    {
      endpoint_id = 6,
      clusters = {
        {
          cluster_id = clusters.Switch.ID,
          feature_map = clusters.Switch.types.Feature.MOMENTARY_SWITCH,
          cluster_type = "SERVER"
        }
      },
      device_types = {
        {device_type_id = 0x000F, device_type_revision = 1} -- Generic Switch
      }
    },
    {
      endpoint_id = 7,
      clusters = {
        {
          cluster_id = clusters.Switch.ID,
          feature_map = clusters.Switch.types.Feature.MOMENTARY_SWITCH,
          cluster_type = "SERVER"
        }
      },
      device_types = {
        {device_type_id = 0x000F, device_type_revision = 1} -- Generic Switch
      }
    },
    {
      endpoint_id = 8,
      clusters = {
        {
          cluster_id = clusters.Switch.ID,
          feature_map = clusters.Switch.types.Feature.MOMENTARY_SWITCH,
          cluster_type = "SERVER"
        }
      },
      device_types = {
        {device_type_id = 0x000F, device_type_revision = 1} -- Generic Switch
      }
    },
    {
      endpoint_id = 9,
      clusters = {
        {
          cluster_id = clusters.Switch.ID,
          feature_map = clusters.Switch.types.Feature.MOMENTARY_SWITCH,
          cluster_type = "SERVER"
        }
      },
      device_types = {
        {device_type_id = 0x000F, device_type_revision = 1} -- Generic Switch
      }
    },
    {
      endpoint_id = 10,
      clusters = {
        {
          cluster_id = clusters.Switch.ID,
          feature_map = clusters.Switch.types.Feature.MOMENTARY_SWITCH,
          cluster_type = "SERVER"
        }
      },
      device_types = {
        {device_type_id = 0x000F, device_type_revision = 1} -- Generic Switch
      }
    },
    {
      endpoint_id = 11,
      clusters = {
        {
          cluster_id = clusters.Switch.ID,
          feature_map = clusters.Switch.types.Feature.MOMENTARY_SWITCH,
          cluster_type = "SERVER"
        }
      },
      device_types = {
        {device_type_id = 0x000F, device_type_revision = 1} -- Generic Switch
      }
    },
    {
      endpoint_id = 12,
      clusters = {
        {
          cluster_id = clusters.Switch.ID,
          feature_map = clusters.Switch.types.Feature.MOMENTARY_SWITCH,
          cluster_type = "SERVER"
        }
      },
      device_types = {
        {device_type_id = 0x000F, device_type_revision = 1} -- Generic Switch
      }
    }
  }
})

local function configure_buttons()
  for key = 1, 12 do
    local component = "F" .. key
    if key == 1 then component = "main" end
    test.socket.capability:__expect_send(mock_device:generate_test_message(component, capabilities.button.supportedButtonValues({"pushed"}, {visibility = {displayed = false}})))
  end
end

local function test_init_mk1()
  test.disable_startup_messages()
  test.mock_device.add_test_device(mock_device)
  local cluster_subscribe_list = {
    clusters.Switch.events.InitialPress
  }
  local subscribe_request = cluster_subscribe_list[1]:subscribe(mock_device)
  for i, clus in ipairs(cluster_subscribe_list) do
    if i > 1 then subscribe_request:merge(clus:subscribe(mock_device)) end
  end

  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })

  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "init" })
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})

  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
  mock_device:expect_metadata_update({ profile = "12-button-keyboard" })
  mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  configure_buttons()

  local device_info_copy = utils.deep_copy(mock_device.raw_st_data)
  device_info_copy.profile.id = "12-buttons-keyboard"
  local device_info_json = dkjson.encode(device_info_copy)
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "infoChanged", device_info_json })
  configure_buttons()
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})
end

test.register_coroutine_test(
  "Handle single press sequence",
  function()
    for key = 1, 12 do
      test.socket.matter:__queue_receive({
        mock_device.id,
        clusters.Switch.events.InitialPress:build_test_event_report(mock_device, key, {new_position = 1})
      })
      test.socket.capability:__expect_send(
        mock_device:generate_test_message(key == 1 and "main" or "F" .. key, capabilities.button.button.pushed({state_change = true}))
      )
    end
  end,
  {
    test_init = test_init_mk1,
    min_api_version = 17
  }
)

-- run the tests
test.run_registered_tests()
