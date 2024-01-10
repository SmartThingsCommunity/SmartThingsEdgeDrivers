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
local t_utils = require "integration_test.utils"
local data_types = require "st.matter.data_types"

local clusters = require "st.matter.clusters"
local cluster_base = require "st.matter.cluster_base"

local PRIVATE_CLUSTER_ID = 0x130AFC01
local PRIVATE_ATTR_ID_WATT = 0x130A000A
local PRIVATE_ATTR_ID_WATT_ACCUMULATED = 0x130A000B
local PRIVATE_ATTR_ID_ACCUMULATED_CONTROL_POINT = 0x130A000E

local mock_device = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("power-energy-powerConsumption.yml"),
  manufacturer_info = {
    vendor_id = 0x130A,
    product_id = 0x0050,
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
          cluster_id = clusters.OnOff.ID,
          cluster_type = "SERVER",
          cluster_revision = 1,
          feature_map = 0, --u32 bitmap
        },
        {
          cluster_id = PRIVATE_CLUSTER_ID,
          cluster_type = "SERVER",
          cluster_revision = 1,
          feature_map = 0, --u32 bitmap
        }
      },
      device_types = {
        { device_type_id = 0x010A, device_type_revision = 1 } -- On/Off Plug
      }
    }
  }
})

local function test_init()
  local cluster_subscribe_list = {
    clusters.OnOff.attributes.OnOff,
  }
  test.socket.matter:__set_channel_ordering("relaxed")
  local subscribe_request = cluster_subscribe_list[1]:subscribe(mock_device)
  for i, cluster in ipairs(cluster_subscribe_list) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(mock_device))
    end
  end
  test.socket.matter:__expect_send({ mock_device.id, subscribe_request })
  test.mock_device.add_test_device(mock_device)
end
test.set_test_init_function(test_init)

test.register_message_test(
  "On command should send the appropriate commands",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "switch", component = "main", command = "on", args = {} }
      }
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
  "Off command should send the appropriate commands",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "switch", component = "main", command = "off", args = {} }
      }
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

test.register_coroutine_test(
  "Check the power and energy meter when the device is added", function()
    test.socket.matter:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.powerMeter.power({ value = 0.0, unit = "W" }))
    )

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.energyMeter.energy({ value = 0.0, unit = "Wh" }))
    )

    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "Check when the device is removed", function()
    test.socket.matter:__set_channel_ordering("relaxed")

    local poll_timer = mock_device:get_field("RECURRING_POLL_TIMER")
    assert(poll_timer ~= nil, "poll_timer should exist")

    local report_poll_timer = mock_device:get_field("RECURRING_REPORT_POLL_TIMER")
    assert(report_poll_timer ~= nil, "report_poll_timer should exist")

    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "removed" })
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "Check that the timer created in create_poll_schedule properly reads the device in requestData",
  function()
    test.mock_time.advance_time(60000) -- Ensure that the timer created in create_poll_schedule triggers
    test.socket.matter:__set_channel_ordering("relaxed")

    local attribute_read = cluster_base.read(mock_device, 0x01, PRIVATE_CLUSTER_ID, PRIVATE_ATTR_ID_WATT, nil)
    attribute_read:merge(cluster_base.read(mock_device, 0x01, PRIVATE_CLUSTER_ID, PRIVATE_ATTR_ID_WATT_ACCUMULATED, nil))
    test.socket.matter:__expect_send({ mock_device.id, attribute_read})

    test.wait_for_events()
  end,
  {
    test_init = function()
      local cluster_subscribe_list = {
        clusters.OnOff.attributes.OnOff,
      }
      test.socket.matter:__set_channel_ordering("relaxed")
      local subscribe_request = cluster_subscribe_list[1]:subscribe(mock_device)
      for i, cluster in ipairs(cluster_subscribe_list) do
        if i > 1 then
          subscribe_request:merge(cluster:subscribe(mock_device))
        end
      end
      test.socket.matter:__expect_send({ mock_device.id, subscribe_request })
      test.mock_device.add_test_device(mock_device)

      test.timer.__create_and_queue_test_time_advance_timer(60, "interval", "create_poll_schedule")
    end
  }
)

test.register_coroutine_test(
  "Check the refresh command", function()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        { capability = capabilities.refresh.ID, command = capabilities.refresh.commands.refresh.NAME, args = {} },
      }
    )

    local refresh_response = cluster_base.read(mock_device, 0x01, PRIVATE_CLUSTER_ID, PRIVATE_ATTR_ID_WATT, nil)
    refresh_response:merge(cluster_base.read(mock_device, 0x01, PRIVATE_CLUSTER_ID, PRIVATE_ATTR_ID_WATT_ACCUMULATED, nil))
    test.socket.matter:__expect_send({ mock_device.id, refresh_response})
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "Report with the custom Watt attribute", function()
    local data = data_types.validate_or_build_type(50, data_types.Uint16, "watt")
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        cluster_base.build_test_report_data(
          mock_device,
          0x01,
          PRIVATE_CLUSTER_ID,
          PRIVATE_ATTR_ID_WATT,
          data
        )
      }
    )

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.powerMeter.power({ value = 50, unit = "W" }))
    )

    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "Report with the custom Watt accumulated attribute", function()
    local data = data_types.validate_or_build_type(50, data_types.Uint16, "watt accumulated")
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        cluster_base.build_test_report_data(
          mock_device,
          0x01,
          PRIVATE_CLUSTER_ID,
          PRIVATE_ATTR_ID_WATT_ACCUMULATED,
          data
        )
      }
    )

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.energyMeter.energy({ value = 50000, unit = "Wh" }))
    )

    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "Report with the custom Watt accumulated attribute after 10 minutes", function()
    local currentTime = 60000
    test.mock_time.advance_time(currentTime)

    local data = data_types.validate_or_build_type(50, data_types.Uint16, "watt accumulated")
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        cluster_base.build_test_report_data(
          mock_device,
          0x01,
          PRIVATE_CLUSTER_ID,
          PRIVATE_ATTR_ID_WATT_ACCUMULATED,
          data
        )
      }
    )

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.energyMeter.energy({ value = 50000, unit = "Wh" }))
    )

    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "Check the reset command", function()
    local timeDiff = 1
    local currentTime = 978307200 + timeDiff -- 1 January 2001
    test.mock_time.advance_time(currentTime)

    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {
          capability = capabilities.energyMeter.ID,
          command = capabilities.energyMeter.commands.resetEnergyMeter.NAME,
          args = {}
        },
      }
    )

    local data = data_types.validate_or_build_type(timeDiff, data_types.Uint32)
    test.socket.matter:__expect_send({ mock_device.id,
      cluster_base.write(mock_device, 0x01, PRIVATE_CLUSTER_ID, PRIVATE_ATTR_ID_ACCUMULATED_CONTROL_POINT, nil, data) })

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.powerConsumptionReport.powerConsumption({
          energy = 0,
          deltaEnergy = 0,
          start = "1970-01-01T00:00:00Z",
          ["end"] = "2001-01-01T00:00:00Z"
        }))
    )

    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "Test the on attribute", function()
    local data = data_types.validate_or_build_type(1, data_types.Uint16, "on")
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        cluster_base.build_test_report_data(
          mock_device,
          0x01,
          clusters.OnOff.ID,
          clusters.OnOff.attributes.OnOff.ID,
          data
        )
      }
    )

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.switch.switch({ value = "on" }))
    )

    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "Report with power consumption after 15 minutes even when device is off", function()
    -- device is off
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.OnOff.attributes.OnOff:build_test_report_data(mock_device, 1, false)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.switch.switch({ value = "off" }))
    )

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.powerMeter.power({ value = 0, unit = "W" }))
    )

    test.wait_for_events()
    -- after 15 minutes, the device should still report power consumption even when off
    test.mock_time.advance_time(60 * 15) -- Ensure that the timer created in create_poll_schedule triggers


    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.powerConsumptionReport.powerConsumption({
          energy = 0,
          deltaEnergy = 0.0,
          start = "1970-01-01T00:00:00Z",
          ["end"] = "1970-01-01T00:14:59Z"
        }))
    )

    test.wait_for_events()
  end,
  {
    test_init = function()
      local cluster_subscribe_list = {
        clusters.OnOff.attributes.OnOff,
      }
      test.socket.matter:__set_channel_ordering("relaxed")
      local subscribe_request = cluster_subscribe_list[1]:subscribe(mock_device)
      for i, cluster in ipairs(cluster_subscribe_list) do
        if i > 1 then
          subscribe_request:merge(cluster:subscribe(mock_device))
        end
      end
      test.socket.matter:__expect_send({ mock_device.id, subscribe_request })
      test.mock_device.add_test_device(mock_device)
      test.timer.__create_and_queue_test_time_advance_timer(60 * 15, "interval", "create_poll_report_schedule")
      test.timer.__create_and_queue_test_time_advance_timer(60, "interval", "create_poll_schedule")
    end
  }
)

test.run_registered_tests()
