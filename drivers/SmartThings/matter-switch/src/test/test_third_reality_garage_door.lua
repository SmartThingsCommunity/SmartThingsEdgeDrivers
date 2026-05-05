-- Copyright © 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local t_utils = require "integration_test.utils"
local test = require "integration_test"

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
  end,
  {min_api_version = 17}
)

-- run the tests
test.run_registered_tests()
