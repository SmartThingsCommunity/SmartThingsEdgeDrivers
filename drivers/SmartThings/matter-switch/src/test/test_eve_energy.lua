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
local cluster_base = require "st.matter.cluster_base"

local PRIVATE_CLUSTER_ID = 0x130AFC01
local PRIVATE_ATTR_ID_WATT = 0x130A000A
local PRIVATE_ATTR_ID_WATT_ACCUMULATED = 0x130A000B

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
        device_type_id = 0x0016, device_type_revision = 1, -- RootNode
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
  "Check that the timer created in create_poll_schedule properly reads the device in requestData",
  function()
    test.mock_time.advance_time(60000) -- Ensure that the timer created in create_poll_schedule triggers
    test.socket.matter:__set_channel_ordering("relaxed")

    test.socket.matter:__expect_send({ mock_device.id, clusters.OnOff.attributes.OnOff:read(mock_device) })
    test.socket.matter:__expect_send({ mock_device.id,
      cluster_base.read(mock_device, 0x01, PRIVATE_CLUSTER_ID, PRIVATE_ATTR_ID_WATT, nil) })
    test.socket.matter:__expect_send({ mock_device.id,
      cluster_base.read(mock_device, 0x01, PRIVATE_CLUSTER_ID, PRIVATE_ATTR_ID_WATT_ACCUMULATED, nil) })

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

test.run_registered_tests()
