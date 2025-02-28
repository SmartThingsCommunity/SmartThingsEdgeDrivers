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
local utils = require "st.utils"
local dkjson = require "dkjson"
local uint32 = require "st.matter.data_types.Uint32"

local clusters = require "st.matter.generated.zap_clusters"
local button_attr = capabilities.button.button

local DEFERRED_CONFIGURE = "__DEFERRED_CONFIGURE"

-- Mock a 3-button device with temperature and humidity sensor
local aqara_mock_device = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("3-button-battery-temperature-humidity.yml"),
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
        {device_type_id = 0x0302, device_type_revision = 1},
      }
    },
    {
      endpoint_id = 2,
      clusters = {
        {cluster_id = clusters.RelativeHumidityMeasurement.ID, cluster_type = "BOTH"},
      },
      device_types = {
        {device_type_id = 0x0307, device_type_revision = 1},
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
        {cluster_id = clusters.PowerSource.ID, cluster_type = "SERVER",
         feature_map = clusters.PowerSource.types.PowerSourceFeature.BATTERY
        }
      },
      device_types = {
        {device_type_id = 0x0011, device_type_revision = 1}
      }
    }
  }
})

local function test_init()
  local opts = { persist = true }
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
  local read_request

  local read_attribute_list = clusters.PowerSource.attributes.AttributeList:read()
  test.socket.matter:__expect_send({aqara_mock_device.id, read_attribute_list})
  test.socket.matter:__queue_receive({aqara_mock_device.id, clusters.PowerSource.attributes.AttributeList:build_test_report_data(aqara_mock_device, 6, {uint32(0x0C)})})

  local subscribe_request = cluster_subscribe_list[1]:subscribe(aqara_mock_device)
  for i, cluster in ipairs(cluster_subscribe_list) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(aqara_mock_device))
    end
  end

  test.socket.matter:__expect_send({aqara_mock_device.id, subscribe_request})
  test.mock_device.add_test_device(aqara_mock_device)
  test.set_rpc_version(5)

  test.socket.device_lifecycle:__queue_receive({ aqara_mock_device.id, "added" })
  test.socket.matter:__expect_send({aqara_mock_device.id, subscribe_request})
  test.mock_devices_api._expected_device_updates[aqara_mock_device.device_id] = "00000000-1111-2222-3333-000000000001"
  test.mock_devices_api._expected_device_updates[1] = {device_id = "00000000-1111-2222-3333-000000000001"}
  test.mock_devices_api._expected_device_updates[1].metadata = {deviceId="00000000-1111-2222-3333-000000000001", profileReference="3-button-battery-temperature-humidity"}

  aqara_mock_device:set_field(DEFERRED_CONFIGURE, true, opts)
  local device_info_copy = utils.deep_copy(aqara_mock_device.raw_st_data)
  device_info_copy.profile.id = "3-button-battery-temperature-humidity"
  local device_info_json = dkjson.encode(device_info_copy)
  test.socket.device_lifecycle:__queue_receive({ aqara_mock_device.id, "infoChanged", device_info_json })
  test.socket.matter:__expect_send({aqara_mock_device.id, subscribe_request})

  read_request = cluster_read_list[1]:read(aqara_mock_device, 3)
  read_request:merge(cluster_read_list[1]:subscribe(aqara_mock_device))
  test.socket.matter:__expect_send({aqara_mock_device.id, read_request})
  test.socket.capability:__expect_send(aqara_mock_device:generate_test_message("button1", button_attr.pushed({state_change = false})))

  read_request = cluster_read_list[1]:read(aqara_mock_device, 4)
  read_request:merge(cluster_read_list[1]:subscribe(aqara_mock_device))
  test.socket.matter:__expect_send({aqara_mock_device.id, read_request})
  test.socket.capability:__expect_send(aqara_mock_device:generate_test_message("button2", button_attr.pushed({state_change = false})))

  read_request = cluster_read_list[1]:read(aqara_mock_device, 5)
  read_request:merge(cluster_read_list[1]:subscribe(aqara_mock_device))
  test.socket.matter:__expect_send({aqara_mock_device.id, read_request})
  test.socket.capability:__expect_send(aqara_mock_device:generate_test_message("button3", button_attr.pushed({state_change = false})))
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Temperature reports should generate correct messages",
  function ()
    test.socket.matter:__queue_receive(
      {
        aqara_mock_device.id,
        clusters.TemperatureMeasurement.server.attributes.MeasuredValue:build_test_report_data(aqara_mock_device, 1, 40*100)
      }
    )
    test.socket.capability:__expect_send(
      aqara_mock_device:generate_test_message("main", capabilities.temperatureMeasurement.temperature({ value = 40.0, unit = "C" }))
    )
  end
)

test.register_coroutine_test(
  "Min and max temperature attributes set capability constraint",
  function ()
    test.socket.matter:__queue_receive(
      {
        aqara_mock_device.id,
        clusters.TemperatureMeasurement.attributes.MinMeasuredValue:build_test_report_data(aqara_mock_device, 1, 500)
      }
    )
    test.socket.matter:__queue_receive(
      {
        aqara_mock_device.id,
        clusters.TemperatureMeasurement.attributes.MaxMeasuredValue:build_test_report_data(aqara_mock_device, 1, 4000)
      }
    )
    test.socket.capability:__expect_send(
      aqara_mock_device:generate_test_message("main", capabilities.temperatureMeasurement.temperatureRange({ value = { minimum = 5.00, maximum = 40.00 }, unit = "C" }))
    )
  end
)

test.register_coroutine_test(
  "Relative humidity reports should generate correct messages",
  function ()
    test.socket.matter:__queue_receive(
      {
        aqara_mock_device.id,
        clusters.RelativeHumidityMeasurement.server.attributes.MeasuredValue:build_test_report_data(aqara_mock_device, 2, 4049)
      }
    )
    test.socket.capability:__expect_send(
      aqara_mock_device:generate_test_message("main", capabilities.relativeHumidityMeasurement.humidity({ value = 40 }))
    )
    test.socket.matter:__queue_receive(
      {
        aqara_mock_device.id,
        clusters.RelativeHumidityMeasurement.server.attributes.MeasuredValue:build_test_report_data(aqara_mock_device, 2, 4050)
      }
    )
    test.socket.capability:__expect_send(
      aqara_mock_device:generate_test_message("main", capabilities.relativeHumidityMeasurement.humidity({ value = 41 }))
    )
  end
)

test.register_coroutine_test(
  "Battery percent reports should generate correct messages",
  function ()
    test.socket.matter:__queue_receive(
      {
        aqara_mock_device.id,
        clusters.PowerSource.attributes.BatPercentRemaining:build_test_report_data(aqara_mock_device, 1, 150)
      }
    )
    test.socket.capability:__expect_send(
      aqara_mock_device:generate_test_message("main", capabilities.battery.battery(math.floor(150 / 2.0 + 0.5)))
    )
  end
)

test.register_coroutine_test(
  "Handle single press sequence for a long hold on long-release-capable button", -- only a long press event should generate a held event
  function ()
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.socket.matter:__queue_receive(
      {
        aqara_mock_device.id,
        clusters.Switch.events.InitialPress:build_test_event_report(aqara_mock_device, 3, {new_position = 1})
      }
    )
    test.wait_for_events()
    test.mock_time.advance_time(2)
    test.socket.matter:__queue_receive(
      {
        aqara_mock_device.id,
        clusters.Switch.events.ShortRelease:build_test_event_report(aqara_mock_device, 3, {previous_position = 0})
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
        aqara_mock_device.id,
        clusters.Switch.events.InitialPress:build_test_event_report(aqara_mock_device, 3, {new_position = 1})
      }
    )
    test.wait_for_events()
    test.mock_time.advance_time(2)
    test.socket.matter:__queue_receive(
      {
        aqara_mock_device.id,
        clusters.Switch.events.ShortRelease:build_test_event_report(aqara_mock_device, 3, {previous_position = 0})
      }
    )
  end
)

test.register_coroutine_test(
  "Handle single press sequence for a multi press on multi button",
    function()
      test.socket.matter:__queue_receive(
        {
          aqara_mock_device.id,
          clusters.Switch.events.InitialPress:build_test_event_report(aqara_mock_device, 3, {new_position = 1})
        }
      )
      test.socket.matter:__queue_receive(
        {
          aqara_mock_device.id,
          clusters.Switch.events.ShortRelease:build_test_event_report(aqara_mock_device, 3, {previous_position = 0})
        }
      )
      test.socket.matter:__queue_receive(
        {
          aqara_mock_device.id,
          clusters.Switch.events.InitialPress:build_test_event_report(aqara_mock_device, 4, {new_position = 1})
        }
      )
      test.socket.matter:__queue_receive(
        {
          aqara_mock_device.id,
          clusters.Switch.events.MultiPressOngoing:build_test_event_report(aqara_mock_device, 4, {new_position = 1, current_number_of_presses_counted = 2})
        }
      )
      test.socket.matter:__queue_receive(
        {
          aqara_mock_device.id,
          clusters.Switch.events.MultiPressComplete:build_test_event_report(aqara_mock_device, 4, {new_position = 0, total_number_of_presses_counted = 2, previous_position = 1})
        }
      )
      test.socket.capability:__expect_send(aqara_mock_device:generate_test_message("button2", button_attr.double({state_change = true})))
    end
)

test.register_coroutine_test(
  "Handle long press sequence for a long hold on long-release-capable button", -- only a long press event should generate a held event
  function ()
    test.socket.matter:__queue_receive(
      {
        aqara_mock_device.id,
        clusters.Switch.events.InitialPress:build_test_event_report(aqara_mock_device, 3, {new_position = 1})
      }
    )
    test.socket.matter:__queue_receive(
      {
        aqara_mock_device.id,
        clusters.Switch.events.LongPress:build_test_event_report(aqara_mock_device, 3, {new_position = 1})
      }
    )
    test.socket.capability:__expect_send(aqara_mock_device:generate_test_message("button1", button_attr.held({state_change = true})))
    test.socket.matter:__queue_receive(
      {
        aqara_mock_device.id,
        clusters.Switch.events.LongRelease:build_test_event_report(aqara_mock_device, 3, {previous_position = 0})
      }
    )
  end
)

test.register_coroutine_test(
  "Handle long press sequence for a long hold on multi button",
  function ()
    test.socket.matter:__queue_receive(
      {
        aqara_mock_device.id,
        clusters.Switch.events.InitialPress:build_test_event_report(aqara_mock_device, 5, {new_position = 1})
      }
    )
    test.socket.matter:__queue_receive(
      {
        aqara_mock_device.id,
        clusters.Switch.events.LongPress:build_test_event_report(aqara_mock_device, 5, {new_position = 1})
      }
    )
    test.socket.capability:__expect_send(aqara_mock_device:generate_test_message("button3", button_attr.held({state_change = true})))
    test.socket.matter:__queue_receive(
      {
        aqara_mock_device.id,
        clusters.Switch.events.LongRelease:build_test_event_report(aqara_mock_device, 5, {previous_position = 0})
      }
    )
  end
)

test.register_coroutine_test(
  "Handle double press",
  function()
    test.socket.matter:__queue_receive(
      {
        aqara_mock_device.id,
        clusters.Switch.events.MultiPressComplete:build_test_event_report(aqara_mock_device, 3, {new_position = 1, total_number_of_presses_counted = 2, previous_position = 0})
      }
    )
    test.socket.capability:__expect_send(
      aqara_mock_device:generate_test_message("button1", button_attr.double({state_change = true}))
    )
  end
)

test.register_coroutine_test(
  "Receiving a max press attribute of 2 should emit correct event",
    function()
      test.socket.matter:__queue_receive(
        {
          aqara_mock_device.id,
          clusters.Switch.attributes.MultiPressMax:build_test_report_data(aqara_mock_device, 3, 2)
        }
      )
      test.socket.capability:__expect_send(
        aqara_mock_device:generate_test_message("button1", capabilities.button.supportedButtonValues({"pushed", "double", "held"}, {visibility = {displayed = false}}))
      )
    end
)

test.register_coroutine_test(
  "Handle single press sequence for emulated hold on short-release-only button",
  function ()
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.socket.matter:__queue_receive(
      {
        aqara_mock_device.id,
        clusters.Switch.events.InitialPress:build_test_event_report(aqara_mock_device, 4, {new_position = 1})
      }
    )
    test.wait_for_events()
    test.mock_time.advance_time(2)
    test.socket.matter:__queue_receive(
      {
        aqara_mock_device.id,
        clusters.Switch.events.ShortRelease:build_test_event_report(aqara_mock_device, 4, {previous_position = 0})
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
        aqara_mock_device.id,
        clusters.Switch.attributes.MultiPressMax:build_test_report_data(
          aqara_mock_device, 5, 3
        )
      },
    },
    {
      channel = "capability",
      direction = "send",
      message = aqara_mock_device:generate_test_message("button3",
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
        aqara_mock_device.id,
        clusters.Switch.attributes.MultiPressMax:build_test_report_data(
          aqara_mock_device, 3, 7
        )
      },
    },
    {
      channel = "capability",
      direction = "send",
      message = aqara_mock_device:generate_test_message("button1",
        capabilities.button.supportedButtonValues({"pushed", "double", "held", "pushed_3x", "pushed_4x", "pushed_5x", "pushed_6x"}, {visibility = {displayed = false}}))
    },
  }
)

test.run_registered_tests()

