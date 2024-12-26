-- Copyright 2024 SmartThings
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
local t_utils = require "integration_test.utils"
local capabilities = require "st.capabilities"

local clusters = require "st.matter.generated.zap_clusters"
local button_attr = capabilities.button.button

-- Mock a 3-button device with temperature and humidity sensor
local button_mock_device = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("temperature-humidity-3button-battery.yml"),
  manufacturer_info = {vendor_id = 0x115F, product_id = 0x2004, product_name = "Aqara Climate Sensor W100"},
  label = "Climate Sensor W100",
  device_id = "00000000-1111-2222-3333-000000000001",
  endpoints = {
    {
      endpoint_id = 0,
      clusters = {
        {cluster_id = clusters.Basic.ID, cluster_type = "SERVER"},
      },
      device_types = {
        {device_type_id = 0x0016, device_type_revision = 1}, -- RootNode
      }
    },
    {
      endpoint_id = 1,
      clusters = {
        {cluster_id = clusters.TemperatureMeasurement.ID, cluster_type = "SERVER"},
      },
      device_types = {
        {},
      }
    },
    {
      endpoint_id = 2,
      clusters = {
        {cluster_id = clusters.RelativeHumidityMeasurement.ID, cluster_type = "BOTH"},
      },
      device_types = {
        {},
      }
    },
    {
      endpoint_id = 3,
      clusters = {
        {cluster_id = clusters.Switch.ID, cluster_type = "SERVER", cluster_revision = 1,
         feature_map = clusters.Switch.types.Feature.MOMENTARY_SWITCH |
           clusters.Switch.types.Feature.MOMENTARY_SWITCH_MULTI_PRESS |
           clusters.Switch.types.Feature.MOMENTARY_SWITCH_LONG_PRESS,
        }
      },
      device_types = {
        {device_type_id = 0x000F, device_type_revision = 1} -- Generic Switch
      }
    },
    {
      endpoint_id = 4,
      clusters = {
        {cluster_id = clusters.Switch.ID, cluster_type = "SERVER", cluster_revision = 1,
         feature_map = clusters.Switch.types.Feature.MOMENTARY_SWITCH |
           clusters.Switch.types.Feature.MOMENTARY_SWITCH_MULTI_PRESS |
           clusters.Switch.types.Feature.MOMENTARY_SWITCH_LONG_PRESS,
        }
      },
      device_types = {
        {device_type_id = 0x000F, device_type_revision = 1} -- Generic Switch
      }
    },
    {
      endpoint_id = 5,
      clusters = {
        {cluster_id = clusters.Switch.ID, cluster_type = "SERVER", cluster_revision = 1,
         feature_map = clusters.Switch.types.Feature.MOMENTARY_SWITCH |
           clusters.Switch.types.Feature.MOMENTARY_SWITCH_MULTI_PRESS |
           clusters.Switch.types.Feature.MOMENTARY_SWITCH_LONG_PRESS,
        }
      },
      device_types = {
        {device_type_id = 0x000F, device_type_revision = 1} -- Generic Switch
      }
    },
    {
      endpoint_id = 6,
      clusters = {
        {cluster_id = clusters.PowerSource.ID, cluster_type = "SERVER"}
      },
      device_types = {
        {}
      }
    }
  }
})

local function test_init()
  local cluster_subscribe_list = {
    clusters.PowerSource.server.attributes.BatPercentRemaining,
    clusters.TemperatureMeasurement.attributes.MeasuredValue,
    clusters.TemperatureMeasurement.attributes.MinMeasuredValue,
    clusters.TemperatureMeasurement.attributes.MaxMeasuredValue,
    clusters.RelativeHumidityMeasurement.attributes.MeasuredValue,
    clusters.Switch.server.events.InitialPress,
    clusters.Switch.server.events.LongPress,
    clusters.Switch.server.events.ShortRelease,
    clusters.Switch.server.events.MultiPressComplete,
  }

  local cluster_read_list = {
    clusters.Switch.attributes.MultiPressMax
  }

  local ep = 3
  local read_request
  for i, cluster in ipairs(cluster_read_list) do
    for j = 1, 3, 1 do
      read_request = cluster_read_list[1]:read(button_mock_device, ep)
      read_request:merge(cluster:subscribe(button_mock_device))
      test.socket.matter:__expect_send({button_mock_device.id, read_request})
      ep = ep + 1
    end
  end

  local subscribe_request = cluster_subscribe_list[1]:subscribe(button_mock_device)
  for i, cluster in ipairs(cluster_subscribe_list) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(button_mock_device))
    end
  end

  test.socket.matter:__expect_send({button_mock_device.id, subscribe_request})
  test.mock_device.add_test_device(button_mock_device)
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Handle single press sequence for a long hold on long-release-capable button", -- only a long press event should generate a held event
  function ()
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.socket.matter:__queue_receive(
      {
        button_mock_device.id,
        clusters.Switch.events.InitialPress:build_test_event_report(button_mock_device, 3, {new_position = 1})
      }
    )
    test.wait_for_events()
    test.mock_time.advance_time(2)
    test.socket.matter:__queue_receive(
      {
        button_mock_device.id,
        clusters.Switch.events.ShortRelease:build_test_event_report(button_mock_device, 3, {previous_position = 0})
      }
    )
  end
)

test.register_coroutine_test(
  "Handle single press sequence for a long hold on multi button", -- pushes should only be generated from multiPressComplete events
  function ()
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.socket.matter:__queue_receive(
      {
        button_mock_device.id,
        clusters.Switch.events.InitialPress:build_test_event_report(button_mock_device, 3, {new_position = 1})
      }
    )
    test.wait_for_events()
    test.mock_time.advance_time(2)
    test.socket.matter:__queue_receive(
      {
        button_mock_device.id,
        clusters.Switch.events.ShortRelease:build_test_event_report(button_mock_device, 3, {previous_position = 0})
      }
    )
  end
)

test.register_coroutine_test(
  "Handle single press sequence for a multi press on multi button",
    function()
      test.socket.matter:__queue_receive(
        {
          button_mock_device.id,
          clusters.Switch.events.InitialPress:build_test_event_report(button_mock_device, 3, {new_position = 1})
        }
      )
      test.socket.matter:__queue_receive(
        {
          button_mock_device.id,
          clusters.Switch.events.ShortRelease:build_test_event_report(button_mock_device, 3, {previous_position = 0})
        }
      )
      test.socket.matter:__queue_receive(
        {
          button_mock_device.id,
          clusters.Switch.events.InitialPress:build_test_event_report(button_mock_device, 4, {new_position = 1})
        }
      )
      test.socket.matter:__queue_receive(
        {
          button_mock_device.id,
          clusters.Switch.events.MultiPressOngoing:build_test_event_report(button_mock_device, 4, {new_position = 1, current_number_of_presses_counted = 2})
        }
      )
      test.socket.matter:__queue_receive(
        {
          button_mock_device.id,
          clusters.Switch.events.MultiPressComplete:build_test_event_report(button_mock_device, 4, {new_position = 0, total_number_of_presses_counted = 2, previous_position = 1})
        }
      )
      test.socket.capability:__expect_send(button_mock_device:generate_test_message("button2", button_attr.double({state_change = true})))
    end
)

test.register_coroutine_test(
  "Handle long press sequence for a long hold on long-release-capable button", -- only a long press event should generate a held event
  function ()
    test.socket.matter:__queue_receive(
      {
        button_mock_device.id,
        clusters.Switch.events.InitialPress:build_test_event_report(button_mock_device, 3, {new_position = 1})
      }
    )
    test.socket.matter:__queue_receive(
      {
        button_mock_device.id,
        clusters.Switch.events.LongPress:build_test_event_report(button_mock_device, 3, {new_position = 1})
      }
    )
    test.socket.capability:__expect_send(button_mock_device:generate_test_message("button1", button_attr.held({state_change = true})))
    test.socket.matter:__queue_receive(
      {
        button_mock_device.id,
        clusters.Switch.events.LongRelease:build_test_event_report(button_mock_device, 3, {previous_position = 0})
      }
    )
  end
)

test.register_coroutine_test(
  "Handle long press sequence for a long hold on multi button",
  function ()
    test.socket.matter:__queue_receive(
      {
        button_mock_device.id,
        clusters.Switch.events.InitialPress:build_test_event_report(button_mock_device, 5, {new_position = 1})
      }
    )
    test.socket.matter:__queue_receive(
      {
        button_mock_device.id,
        clusters.Switch.events.LongPress:build_test_event_report(button_mock_device, 5, {new_position = 1})
      }
    )
    test.socket.capability:__expect_send(button_mock_device:generate_test_message("button3", button_attr.held({state_change = true})))
    test.socket.matter:__queue_receive(
      {
        button_mock_device.id,
        clusters.Switch.events.LongRelease:build_test_event_report(button_mock_device, 5, {previous_position = 0})
      }
    )
  end
)

test.register_coroutine_test(
  "Handle double press",
  function()
    test.socket.matter:__queue_receive(
      {
        button_mock_device.id,
        clusters.Switch.events.MultiPressComplete:build_test_event_report(button_mock_device, 3, {new_position = 1, total_number_of_presses_counted = 2, previous_position = 0})
      }
    )
    test.socket.capability:__expect_send(
      button_mock_device:generate_test_message("button1", button_attr.double({state_change = true}))
    )
  end
)

test.register_coroutine_test(
  "Receiving a max press attribute of 2 should emit correct event",
    function()
      test.socket.matter:__queue_receive(
        {
          button_mock_device.id,
          clusters.Switch.attributes.MultiPressMax:build_test_report_data(button_mock_device, 3, 2)
        }
      )
      test.socket.capability:__expect_send(
        button_mock_device:generate_test_message("button1", capabilities.button.supportedButtonValues({"pushed", "double", "held"}, {visibility = {displayed = false}}))
      )
    end
)

test.register_coroutine_test(
  "Handle single press sequence for emulated hold on short-release-only button",
  function ()
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.socket.matter:__queue_receive(
      {
        button_mock_device.id,
        clusters.Switch.events.InitialPress:build_test_event_report(button_mock_device, 4, {new_position = 1})
      }
    )
    test.wait_for_events()
    test.mock_time.advance_time(2)
    test.socket.matter:__queue_receive(
      {
        button_mock_device.id,
        clusters.Switch.events.ShortRelease:build_test_event_report(button_mock_device, 4, {previous_position = 0})
      }
    )
  end
)

test.register_message_test(
  "Receiving a max press attribute of 3 should emit correct event", {
    {
      channel = "matter",
      direction = "receive",
      message = {
        button_mock_device.id,
        clusters.Switch.attributes.MultiPressMax:build_test_report_data(
          button_mock_device, 5, 3
        )
      },
    },
    {
      channel = "capability",
      direction = "send",
      message = button_mock_device:generate_test_message("button3",
        capabilities.button.supportedButtonValues({"pushed", "double", "held", "pushed_3x"}, {visibility = {displayed = false}}))
    },
  }
)

test.register_message_test(
  "Receiving a max press attribute of greater than 6 should only emit up to pushed_6x", {
    {
      channel = "matter",
      direction = "receive",
      message = {
        button_mock_device.id,
        clusters.Switch.attributes.MultiPressMax:build_test_report_data(
          button_mock_device, 3, 7
        )
      },
    },
    {
      channel = "capability",
      direction = "send",
      message = button_mock_device:generate_test_message("button1",
        capabilities.button.supportedButtonValues({"pushed", "double", "held", "pushed_3x", "pushed_4x", "pushed_5x", "pushed_6x"}, {visibility = {displayed = false}}))
    },
  }
)

test.run_registered_tests()

