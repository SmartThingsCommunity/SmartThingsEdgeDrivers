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
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"

local clusters = require "st.matter.clusters"

clusters.ElectricalEnergyMeasurement = require "ElectricalEnergyMeasurement"
clusters.ElectricalPowerMeasurement = require "ElectricalPowerMeasurement"

local mock_device = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("plug-power-energy-powerConsumption.yml"),
  manufacturer_info = {
    vendor_id = 0x0000,
    product_id = 0x0000,
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
        { cluster_id = clusters.ElectricalEnergyMeasurement.ID, cluster_type = "SERVER", feature_map = 14, },
        { cluster_id = clusters.ElectricalPowerMeasurement.ID, cluster_type = "SERVER", feature_map = 0, },
      },
      device_types = {
        { device_type_id = 0x0510, device_type_revision = 1 } -- Electrical Sensor
      }
    },
  },
})


local mock_device_periodic = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("plug-energy-powerConsumption.yml"),
  manufacturer_info = {
    vendor_id = 0x0000,
    product_id = 0x0000,
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
        { cluster_id = clusters.ElectricalEnergyMeasurement.ID, cluster_type = "SERVER", feature_map = 10, },
      },
      device_types = {
        { device_type_id = 0x0510, device_type_revision = 1 } -- Electrical Sensor
      }
    },
  },
})

local subscribed_attributes_periodic = {
  clusters.ElectricalEnergyMeasurement.attributes.PeriodicEnergyExported,
}
local subscribed_attributes = {
    clusters.ElectricalPowerMeasurement.attributes.ActivePower,
    clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyExported,
    clusters.ElectricalEnergyMeasurement.attributes.PeriodicEnergyExported,
}

local cumulative_report_val_19 = {
  energy = 19,
  start_timestamp = 0,
  end_timestamp = 0,
  start_systime = 0,
  end_systime = 0,
}

local cumulative_report_val_29 = {
  energy = 29,
  start_timestamp = 0,
  end_timestamp = 0,
  start_systime = 0,
  end_systime = 0,
}

local cumulative_report_val_39 = {
  energy = 39,
  start_timestamp = 0,
  end_timestamp = 0,
  start_systime = 0,
  end_systime = 0,
}

local periodic_report_val_23 = {
  energy = 23,
  start_timestamp = 0,
  end_timestamp = 0,
  start_systime = 0,
  end_systime = 0,
}

local function test_init()
  local subscribe_request = subscribed_attributes[1]:subscribe(mock_device)
  for i, cluster in ipairs(subscribed_attributes) do
      if i > 1 then
          subscribe_request:merge(cluster:subscribe(mock_device))
      end
  end
  test.mock_device.add_test_device(mock_device)
end
test.set_test_init_function(test_init)

local function test_init_periodic()
  local subscribe_request = subscribed_attributes_periodic[1]:subscribe(mock_device_periodic)
  for i, cluster in ipairs(subscribed_attributes_periodic) do
      if i > 1 then
          subscribe_request:merge(cluster:subscribe(mock_device_periodic))
      end
  end
  test.mock_device.add_test_device(mock_device_periodic)

  test.socket["matter"]:__queue_receive(
    {
      mock_device_periodic.id,
      clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyExported:build_test_report_data(
        mock_device_periodic, 1, periodic_report_val_23
      )
    }
  )
  test.socket["capability"]:__expect_send(
    mock_device_periodic:generate_test_message("main", capabilities.energyMeter.energy({ value = 23, unit = "Wh" }))
  )
end

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

test.register_message_test(
  "Active power measurement should generate correct messages",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.ElectricalPowerMeasurement.server.attributes.ActivePower:build_test_report_data(mock_device, 1, 17)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.powerMeter.power({value = 17, unit="W"}))
    },
  }
)

test.register_message_test(
  "Cumulative Energy measurement should generate correct messages",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.ElectricalEnergyMeasurement.server.attributes.CumulativeEnergyExported:build_test_report_data(mock_device, 1, cumulative_report_val_19)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.energyMeter.energy({value = 19, unit="Wh"}))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.ElectricalEnergyMeasurement.server.attributes.CumulativeEnergyExported:build_test_report_data(mock_device, 1, cumulative_report_val_19)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.energyMeter.energy({value = 19, unit="Wh"}))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.ElectricalEnergyMeasurement.server.attributes.CumulativeEnergyExported:build_test_report_data(mock_device, 1, cumulative_report_val_29)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.powerConsumptionReport.powerConsumption({
        start = "1970-01-01T00:00:00Z",
        ["end"] = "1969-12-31T23:59:59Z",
        deltaEnergy = 0.0,
        energy = 19
      }))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.energyMeter.energy({value = 29, unit="Wh"}))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.ElectricalEnergyMeasurement.server.attributes.CumulativeEnergyExported:build_test_report_data(mock_device, 1, cumulative_report_val_39)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.energyMeter.energy({value = 39, unit="Wh"}))
    },
  }
)

test.register_message_test(
  "Periodic Energy as subordinate to Cumulative Energy measurement should not generate any messages",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.ElectricalEnergyMeasurement.server.attributes.PeriodicEnergyExported:build_test_report_data(mock_device, 1, periodic_report_val_23)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.ElectricalEnergyMeasurement.server.attributes.PeriodicEnergyExported:build_test_report_data(mock_device, 1, periodic_report_val_23)
      }
    },
  }
)

test.register_message_test(
  "Periodic Energy measurement should generate correct messages",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device_periodic.id,
        clusters.ElectricalEnergyMeasurement.server.attributes.PeriodicEnergyExported:build_test_report_data(mock_device_periodic, 1, periodic_report_val_23)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device_periodic:generate_test_message("main", capabilities.energyMeter.energy({value = 46, unit="Wh"}))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device_periodic.id,
        clusters.ElectricalEnergyMeasurement.server.attributes.PeriodicEnergyExported:build_test_report_data(mock_device_periodic, 1, periodic_report_val_23)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device_periodic:generate_test_message("main", capabilities.powerConsumptionReport.powerConsumption({
        start = "1970-01-01T00:00:00Z",
        ["end"] = "1969-12-31T23:59:59Z",
        deltaEnergy = 0.0,
        energy = 46
      }))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device_periodic:generate_test_message("main", capabilities.energyMeter.energy({value = 69, unit="Wh"}))
    },
  },
  { test_init = test_init_periodic }
)

local MINIMUM_ST_ENERGY_REPORT_INTERVAL = (15 * 60) -- 15 minutes, reported in seconds

test.register_coroutine_test(
  "Generated poll timer (<15 minutes) gets correctly set", function()

    test.socket["matter"]:__queue_receive(
      {
        mock_device.id,
        clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyExported:build_test_report_data(
          mock_device, 1, cumulative_report_val_19
        )
      }
    )
    test.socket["capability"]:__expect_send(
      mock_device:generate_test_message("main", capabilities.energyMeter.energy({ value = 19, unit = "Wh" }))
    )
    test.socket["matter"]:__queue_receive(
      {
        mock_device.id,
        clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyExported:build_test_report_data(
          mock_device, 1, cumulative_report_val_19
        )
      }
    )
    test.socket["capability"]:__expect_send(
      mock_device:generate_test_message("main", capabilities.energyMeter.energy({ value = 19, unit = "Wh" }))
    )
    test.wait_for_events()
    test.mock_time.advance_time(899)
    test.socket["matter"]:__queue_receive(
      {
        mock_device.id,
        clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyExported:build_test_report_data(
          mock_device, 1, cumulative_report_val_29
        )
      }
    )
    test.socket["capability"]:__expect_send(
        mock_device:generate_test_message("main", capabilities.powerConsumptionReport.powerConsumption({
            start = "1970-01-01T00:00:00Z",
            ["end"] = "1970-01-01T00:14:58Z",
            deltaEnergy = 0.0,
            energy = 19
        }))
    )
    test.socket["capability"]:__expect_send(
      mock_device:generate_test_message("main", capabilities.energyMeter.energy({ value = 29, unit = "Wh" }))
    )
    test.wait_for_events()
    local report_export_poll_timer = mock_device:get_field("__recurring_export_report_poll_timer")
    local export_timer_length = mock_device:get_field("__export_report_timeout")
    assert(report_export_poll_timer ~= nil, "report_export_poll_timer should exist")
    assert(export_timer_length ~= nil, "export_timer_length should exist")
    assert(export_timer_length == MINIMUM_ST_ENERGY_REPORT_INTERVAL, "export_timer should min_interval")
  end
)

test.register_coroutine_test(
  "Generated poll timer (>15 minutes) gets correctly set", function()

    test.socket["matter"]:__queue_receive(
      {
        mock_device.id,
        clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyExported:build_test_report_data(
          mock_device, 1, cumulative_report_val_19
        )
      }
    )
    test.socket["capability"]:__expect_send(
      mock_device:generate_test_message("main", capabilities.energyMeter.energy({ value = 19, unit = "Wh" }))
    )
    test.socket["matter"]:__queue_receive(
      {
        mock_device.id,
        clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyExported:build_test_report_data(
          mock_device, 1, cumulative_report_val_19
        )
      }
    )
    test.socket["capability"]:__expect_send(
      mock_device:generate_test_message("main", capabilities.energyMeter.energy({ value = 19, unit = "Wh" }))
    )
    test.wait_for_events()
    test.mock_time.advance_time(2000)
    test.socket["matter"]:__queue_receive(
      {
        mock_device.id,
        clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyExported:build_test_report_data(
          mock_device, 1, cumulative_report_val_29
        )
      }
    )
    test.socket["capability"]:__expect_send(
        mock_device:generate_test_message("main", capabilities.powerConsumptionReport.powerConsumption({
            start = "1970-01-01T00:00:00Z",
            ["end"] = "1970-01-01T00:33:19Z",
            deltaEnergy = 0.0,
            energy = 19
        }))
    )
    test.socket["capability"]:__expect_send(
      mock_device:generate_test_message("main", capabilities.energyMeter.energy({ value = 29, unit = "Wh" }))
    )
    test.wait_for_events()
    local report_export_poll_timer = mock_device:get_field("__recurring_export_report_poll_timer")
    local export_timer_length = mock_device:get_field("__export_report_timeout")
    assert(report_export_poll_timer ~= nil, "report_export_poll_timer should exist")
    assert(export_timer_length ~= nil, "export_timer_length should exist")
    assert(export_timer_length == 2000, "export_timer should min_interval")
  end
)

test.register_coroutine_test(
  "Check when the device is removed", function()

    test.socket["matter"]:__queue_receive(
      {
        mock_device.id,
        clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyExported:build_test_report_data(
          mock_device, 1, cumulative_report_val_19
        )
      }
    )
    test.socket["capability"]:__expect_send(
      mock_device:generate_test_message("main", capabilities.energyMeter.energy({ value = 19, unit = "Wh" }))
    )
    test.socket["matter"]:__queue_receive(
      {
        mock_device.id,
        clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyExported:build_test_report_data(
          mock_device, 1, cumulative_report_val_19
        )
      }
    )
    test.socket["capability"]:__expect_send(
      mock_device:generate_test_message("main", capabilities.energyMeter.energy({ value = 19, unit = "Wh" }))
    )
    test.wait_for_events()
    test.mock_time.advance_time(2000)
    test.socket["matter"]:__queue_receive(
      {
        mock_device.id,
        clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyExported:build_test_report_data(
          mock_device, 1, cumulative_report_val_29
        )
      }
    )
    test.socket["capability"]:__expect_send(
        mock_device:generate_test_message("main", capabilities.powerConsumptionReport.powerConsumption({
            start = "1970-01-01T00:00:00Z",
            ["end"] = "1970-01-01T00:33:19Z",
            deltaEnergy = 0.0,
            energy = 19
        }))
    )
    test.socket["capability"]:__expect_send(
      mock_device:generate_test_message("main", capabilities.energyMeter.energy({ value = 29, unit = "Wh" }))
    )
    test.wait_for_events()
    local report_export_poll_timer = mock_device:get_field("__recurring_export_report_poll_timer")
    local export_timer_length = mock_device:get_field("__export_report_timeout")
    assert(report_export_poll_timer ~= nil, "report_export_poll_timer should exist")
    assert(export_timer_length ~= nil, "export_timer_length should exist")
    assert(export_timer_length == 2000, "export_timer should min_interval")


    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "removed" })
    test.wait_for_events()
    report_export_poll_timer = mock_device:get_field("__recurring_export_report_poll_timer")
    export_timer_length = mock_device:get_field("__export_report_timeout")
    assert(report_export_poll_timer == nil, "report_export_poll_timer should exist")
    assert(export_timer_length == nil, "export_timer_length should exist")
  end
)

test.register_coroutine_test(
  "Generated periodic export energy device poll timer (<15 minutes) gets correctly set", function()

    test.socket["matter"]:__queue_receive(
      {
        mock_device_periodic.id,
        clusters.ElectricalEnergyMeasurement.attributes.PeriodicEnergyExported:build_test_report_data(
          mock_device_periodic, 1, periodic_report_val_23
        )
      }
    )
    test.socket["capability"]:__expect_send(
      mock_device_periodic:generate_test_message("main", capabilities.energyMeter.energy({ value = 46, unit = "Wh" }))
    )
    test.wait_for_events()
    test.mock_time.advance_time(899)
    test.socket["matter"]:__queue_receive(
      {
        mock_device_periodic.id,
        clusters.ElectricalEnergyMeasurement.attributes.PeriodicEnergyExported:build_test_report_data(
          mock_device_periodic, 1, periodic_report_val_23
        )
      }
    )
    test.socket["capability"]:__expect_send(
      mock_device_periodic:generate_test_message("main", capabilities.powerConsumptionReport.powerConsumption({
        deltaEnergy=0.0,
        ["end"]="1970-01-01T00:14:58Z",
        energy=46,
        start="1970-01-01T00:00:00Z"
      }))
    )
    test.socket["capability"]:__expect_send(
      mock_device_periodic:generate_test_message("main", capabilities.energyMeter.energy({ value = 69, unit = "Wh" }))
    )
    test.wait_for_events()
    local report_export_poll_timer = mock_device_periodic:get_field("__recurring_export_report_poll_timer")
    local export_timer_length = mock_device_periodic:get_field("__export_report_timeout")
    assert(report_export_poll_timer ~= nil, "report_export_poll_timer should exist")
    assert(export_timer_length ~= nil, "export_timer_length should exist")
    assert(export_timer_length == MINIMUM_ST_ENERGY_REPORT_INTERVAL, "export_timer should min_interval")
  end,
  { test_init = test_init_periodic }
)


test.register_coroutine_test(
  "Generated periodic export energy device poll timer (>15 minutes) gets correctly set", function()

    test.socket["matter"]:__queue_receive(
      {
        mock_device_periodic.id,
        clusters.ElectricalEnergyMeasurement.attributes.PeriodicEnergyExported:build_test_report_data(
          mock_device_periodic, 1, periodic_report_val_23
        )
      }
    )
    test.socket["capability"]:__expect_send(
      mock_device_periodic:generate_test_message("main", capabilities.energyMeter.energy({ value = 46, unit = "Wh" }))
    )
    test.wait_for_events()
    test.mock_time.advance_time(2000)
    test.socket["matter"]:__queue_receive(
      {
        mock_device_periodic.id,
        clusters.ElectricalEnergyMeasurement.attributes.PeriodicEnergyExported:build_test_report_data(
          mock_device_periodic, 1, periodic_report_val_23
        )
      }
    )
    test.socket["capability"]:__expect_send(
      mock_device_periodic:generate_test_message("main", capabilities.powerConsumptionReport.powerConsumption({
        deltaEnergy=0.0,
        ["end"] = "1970-01-01T00:33:19Z",
        energy=46,
        start="1970-01-01T00:00:00Z"
      }))
    )
    test.socket["capability"]:__expect_send(
      mock_device_periodic:generate_test_message("main", capabilities.energyMeter.energy({ value = 69, unit = "Wh" }))
    )
    test.wait_for_events()
    local report_export_poll_timer = mock_device_periodic:get_field("__recurring_export_report_poll_timer")
    local export_timer_length = mock_device_periodic:get_field("__export_report_timeout")
    assert(report_export_poll_timer ~= nil, "report_export_poll_timer should exist")
    assert(export_timer_length ~= nil, "export_timer_length should exist")
    assert(export_timer_length == 2000, "export_timer should min_interval")
  end,
  { test_init = test_init_periodic }
)

test.register_coroutine_test(
  "Test profile change on init for Electrical Sensor device type",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
    mock_device:expect_metadata_update({ profile = "power-energy-powerConsumption" })
    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end,
  { test_init = test_init }
)

test.register_coroutine_test(
  "Test profile change on init for only Periodic Electrical Sensor device type",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device_periodic.id, "doConfigure" })
    mock_device_periodic:expect_metadata_update({ profile = "electrical-energy-powerConsumption" })
    mock_device_periodic:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end,
  { test_init = test_init_periodic }
)

test.run_registered_tests()
