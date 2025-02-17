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
        { device_type_id = 0x0510, device_type_revision = 1 }, -- Electrical Sensor
      }
    },
    {
      endpoint_id = 2,
      clusters = {
        { cluster_id = clusters.OnOff.ID, cluster_type = "SERVER", cluster_revision = 1, feature_map = 0, },
      },
      device_types = {
        { device_type_id = 0x010A, device_type_revision = 1 } -- OnOff Plug
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
  clusters.ElectricalEnergyMeasurement.attributes.PeriodicEnergyImported,
  clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyImported,
}
local subscribed_attributes = {
  clusters.OnOff.attributes.OnOff,
  clusters.ElectricalPowerMeasurement.attributes.ActivePower,
  clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyImported,
  clusters.ElectricalEnergyMeasurement.attributes.PeriodicEnergyImported,
}

local cumulative_report_val_19 = {
  energy = 19000,
  start_timestamp = 0,
  end_timestamp = 0,
  start_systime = 0,
  end_systime = 0,
}

local cumulative_report_val_29 = {
  energy = 29000,
  start_timestamp = 0,
  end_timestamp = 0,
  start_systime = 0,
  end_systime = 0,
}

local cumulative_report_val_39 = {
  energy = 39000,
  start_timestamp = 0,
  end_timestamp = 0,
  start_systime = 0,
  end_systime = 0,
}

local periodic_report_val_23 = {
  energy = 23000,
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
  test.socket.matter:__expect_send({ mock_device.id, subscribe_request })
  test.mock_device.add_test_device(mock_device)
  -- to test powerConsumptionReport
  test.timer.__create_and_queue_test_time_advance_timer(60 * 15, "interval", "create_poll_report_schedule")
end
test.set_test_init_function(test_init)

local function test_init_periodic()
  local subscribe_request = subscribed_attributes_periodic[1]:subscribe(mock_device_periodic)
  for i, cluster in ipairs(subscribed_attributes_periodic) do
    if i > 1 then
        subscribe_request:merge(cluster:subscribe(mock_device_periodic))
    end
  end
  test.socket.matter:__expect_send({ mock_device_periodic.id, subscribe_request })
  test.mock_device.add_test_device(mock_device_periodic)
  -- to test powerConsumptionReport
  test.timer.__create_and_queue_test_time_advance_timer(60 * 15, "interval", "create_poll_report_schedule")
end

test.register_coroutine_test(
  "Check the power and energy meter when the device is added", function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
    local subscribe_request = subscribed_attributes[1]:subscribe(mock_device)
    for i, cluster in ipairs(subscribed_attributes) do
        if i > 1 then
            subscribe_request:merge(cluster:subscribe(mock_device))
        end
    end
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.powerMeter.power({ value = 0.0, unit = "W" }))
    )

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.energyMeter.energy({ value = 0.0, unit = "Wh" }))
    )
    test.socket.matter:__expect_send({mock_device.id, subscribe_request})
    test.wait_for_events()
  end
)

test.register_message_test(
	"On command should send the appropriate commands",
  {
    channel = "devices",
    direction = "send",
    message = {
      "register_native_capability_cmd_handler",
      { device_uuid = mock_device.id, capability_id = "switch", capability_cmd_id = "on" }
    }
  },
	{
		{
			channel = "capability",
			direction = "receive",
			message = {
				mock_device.id,
				{ capability = "switch", component = "main", command = "on", args = { } }
			}
		},
		{
			channel = "matter",
			direction = "send",
			message = {
				mock_device.id,
				clusters.OnOff.server.commands.On(mock_device, 2)
			}
		}
	}
)

test.register_message_test(
  "Off command should send the appropriate commands",
  {
    channel = "devices",
    direction = "send",
    message = {
      "register_native_capability_cmd_handler",
      { device_uuid = mock_device.id, capability_id = "switch", capability_cmd_id = "off" }
    }
  },
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "switch", component = "main", command = "off", args = { } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.OnOff.server.commands.Off(mock_device, 2)
      }
    }
  }
)

test.register_message_test(
  "Active power measurement should generate correct messages",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.ElectricalPowerMeasurement.server.attributes.ActivePower:build_test_report_data(mock_device, 1, 17000)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.powerMeter.power({value = 17.0, unit="W"}))
    },
  }
)

test.register_coroutine_test(
  "Cumulative Energy measurement should generate correct messages",
    function()
      test.socket.matter:__queue_receive(
        {
          mock_device.id,
          clusters.ElectricalEnergyMeasurement.server.attributes.CumulativeEnergyImported:build_test_report_data(
            mock_device, 1, cumulative_report_val_19
          )
        }
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.energyMeter.energy({ value = 19.0, unit = "Wh" }))
      )
      test.socket.matter:__queue_receive(
        {
          mock_device.id,
          clusters.ElectricalEnergyMeasurement.server.attributes.CumulativeEnergyImported:build_test_report_data(
            mock_device, 1, cumulative_report_val_19
          )
        }
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.energyMeter.energy({ value = 19.0, unit = "Wh" }))
      )
      test.socket.matter:__queue_receive(
        {
          mock_device.id,
          clusters.ElectricalEnergyMeasurement.server.attributes.CumulativeEnergyImported:build_test_report_data(
            mock_device, 1, cumulative_report_val_29
          )
        }
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.energyMeter.energy({ value = 29.0, unit = "Wh" }))
      )
      test.socket.matter:__queue_receive(
        {
          mock_device.id,
          clusters.ElectricalEnergyMeasurement.server.attributes.CumulativeEnergyImported:build_test_report_data(
            mock_device, 1, cumulative_report_val_39
          )
        }
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.energyMeter.energy({ value = 39.0, unit = "Wh" }))
      )
      test.mock_time.advance_time(2000)
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.powerConsumptionReport.powerConsumption({
          start = "1970-01-01T00:00:00Z",
          ["end"] = "1970-01-01T00:33:19Z",
          deltaEnergy = 0.0,
          energy = 39.0
        }))
      )
    end
)

test.register_message_test(
  "Periodic Energy as subordinate to Cumulative Energy measurement should not generate any messages",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.ElectricalEnergyMeasurement.server.attributes.PeriodicEnergyImported:build_test_report_data(mock_device, 1, periodic_report_val_23)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.ElectricalEnergyMeasurement.server.attributes.PeriodicEnergyImported:build_test_report_data(mock_device, 1, periodic_report_val_23)
      }
    },
  }
)

test.register_coroutine_test(
  "Periodic Energy measurement should generate correct messages",
    function()
      test.socket.matter:__queue_receive(
        {
          mock_device_periodic.id,
          clusters.ElectricalEnergyMeasurement.server.attributes.PeriodicEnergyImported:build_test_report_data(
            mock_device_periodic, 1, periodic_report_val_23
          )
        }
      )
      test.socket.capability:__expect_send(
        mock_device_periodic:generate_test_message("main", capabilities.energyMeter.energy({value = 23.0, unit="Wh"}))
      )
      test.socket.matter:__queue_receive(
        {
          mock_device_periodic.id,
          clusters.ElectricalEnergyMeasurement.server.attributes.PeriodicEnergyImported:build_test_report_data(
            mock_device_periodic, 1, periodic_report_val_23
          )
        }
      )
      test.socket.capability:__expect_send(
        mock_device_periodic:generate_test_message("main", capabilities.energyMeter.energy({value = 46.0, unit="Wh"}))
      )
      test.socket.matter:__queue_receive(
        {
          mock_device_periodic.id,
          clusters.ElectricalEnergyMeasurement.server.attributes.PeriodicEnergyImported:build_test_report_data(
            mock_device_periodic, 1, periodic_report_val_23
          )
        }
      )
      test.socket.capability:__expect_send(
        mock_device_periodic:generate_test_message("main", capabilities.energyMeter.energy({value = 69.0, unit="Wh"}))
      )
      test.mock_time.advance_time(2000)
      test.socket.capability:__expect_send(
        mock_device_periodic:generate_test_message("main", capabilities.powerConsumptionReport.powerConsumption({
          start = "1970-01-01T00:00:00Z",
          ["end"] = "1970-01-01T00:33:19Z",
          deltaEnergy = 0.0,
          energy = 69.0
        }))
      )
    end,
    { test_init = test_init_periodic }
)

local MINIMUM_ST_ENERGY_REPORT_INTERVAL = (15 * 60) -- 15 minutes, reported in seconds

test.register_coroutine_test(
  "Generated poll timer (<15 minutes) gets correctly set", function()

    test.socket["matter"]:__queue_receive(
      {
        mock_device.id,
        clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyImported:build_test_report_data(
          mock_device, 1, cumulative_report_val_19
        )
      }
    )
    test.socket["capability"]:__expect_send(
      mock_device:generate_test_message("main", capabilities.energyMeter.energy({ value = 19.0, unit = "Wh" }))
    )
    test.socket["matter"]:__queue_receive(
      {
        mock_device.id,
        clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyImported:build_test_report_data(
          mock_device, 1, cumulative_report_val_19
        )
      }
    )
    test.socket["capability"]:__expect_send(
      mock_device:generate_test_message("main", capabilities.energyMeter.energy({ value = 19.0, unit = "Wh" }))
    )
    test.wait_for_events()
    test.mock_time.advance_time(899)
    test.socket["matter"]:__queue_receive(
      {
        mock_device.id,
        clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyImported:build_test_report_data(
          mock_device, 1, cumulative_report_val_29
        )
      }
    )
    test.socket["capability"]:__expect_send(
      mock_device:generate_test_message("main", capabilities.energyMeter.energy({ value = 29.0, unit = "Wh" }))
    )
    test.wait_for_events()
    local report_import_poll_timer = mock_device:get_field("__recurring_import_report_poll_timer")
    local import_timer_length = mock_device:get_field("__import_report_timeout")
    assert(report_import_poll_timer ~= nil, "report_import_poll_timer should exist")
    assert(import_timer_length ~= nil, "import_timer_length should exist")
    assert(import_timer_length == MINIMUM_ST_ENERGY_REPORT_INTERVAL, "import_timer should min_interval")
  end
)

test.register_coroutine_test(
  "Generated poll timer (>15 minutes) gets correctly set", function()

    test.socket["matter"]:__queue_receive(
      {
        mock_device.id,
        clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyImported:build_test_report_data(
          mock_device, 1, cumulative_report_val_19
        )
      }
    )
    test.socket["capability"]:__expect_send(
      mock_device:generate_test_message("main", capabilities.energyMeter.energy({ value = 19.0, unit = "Wh" }))
    )
    test.socket["matter"]:__queue_receive(
      {
        mock_device.id,
        clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyImported:build_test_report_data(
          mock_device, 1, cumulative_report_val_19
        )
      }
    )
    test.socket["capability"]:__expect_send(
      mock_device:generate_test_message("main", capabilities.energyMeter.energy({ value = 19.0, unit = "Wh" }))
    )
    test.wait_for_events()
    test.mock_time.advance_time(2000)
    test.socket["matter"]:__queue_receive(
      {
        mock_device.id,
        clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyImported:build_test_report_data(
          mock_device, 1, cumulative_report_val_29
        )
      }
    )
    test.socket["capability"]:__expect_send(
      mock_device:generate_test_message("main", capabilities.energyMeter.energy({ value = 29.0, unit = "Wh" }))
    )
    test.socket["capability"]:__expect_send(
        mock_device:generate_test_message("main", capabilities.powerConsumptionReport.powerConsumption({
            start = "1970-01-01T00:00:00Z",
            ["end"] = "1970-01-01T00:33:19Z",
            deltaEnergy = 0.0,
            energy = 29.0
        }))
    )
    test.wait_for_events()
    local report_import_poll_timer = mock_device:get_field("__recurring_import_report_poll_timer")
    local import_timer_length = mock_device:get_field("__import_report_timeout")
    assert(report_import_poll_timer ~= nil, "report_import_poll_timer should exist")
    assert(import_timer_length ~= nil, "import_timer_length should exist")
    assert(import_timer_length == 2000, "import_timer should min_interval")
  end
)

test.register_coroutine_test(
  "Check when the device is removed", function()

    test.socket["matter"]:__queue_receive(
      {
        mock_device.id,
        clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyImported:build_test_report_data(
          mock_device, 1, cumulative_report_val_19
        )
      }
    )
    test.socket["capability"]:__expect_send(
      mock_device:generate_test_message("main", capabilities.energyMeter.energy({ value = 19.0, unit = "Wh" }))
    )
    test.socket["matter"]:__queue_receive(
      {
        mock_device.id,
        clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyImported:build_test_report_data(
          mock_device, 1, cumulative_report_val_19
        )
      }
    )
    test.socket["capability"]:__expect_send(
      mock_device:generate_test_message("main", capabilities.energyMeter.energy({ value = 19.0, unit = "Wh" }))
    )
    test.wait_for_events()
    test.mock_time.advance_time(2000)
    test.socket["matter"]:__queue_receive(
      {
        mock_device.id,
        clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyImported:build_test_report_data(
          mock_device, 1, cumulative_report_val_29
        )
      }
    )
    test.socket["capability"]:__expect_send(
      mock_device:generate_test_message("main", capabilities.energyMeter.energy({ value = 29.0, unit = "Wh" }))
    )
    test.socket["capability"]:__expect_send(
        mock_device:generate_test_message("main", capabilities.powerConsumptionReport.powerConsumption({
            start = "1970-01-01T00:00:00Z",
            ["end"] = "1970-01-01T00:33:19Z",
            deltaEnergy = 0.0,
            energy = 29.0
        }))
    )
    test.wait_for_events()
    local report_import_poll_timer = mock_device:get_field("__recurring_import_report_poll_timer")
    local import_timer_length = mock_device:get_field("__import_report_timeout")
    assert(report_import_poll_timer ~= nil, "report_import_poll_timer should exist")
    assert(import_timer_length ~= nil, "import_timer_length should exist")
    assert(import_timer_length == 2000, "import_timer should min_interval")


    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "removed" })
    test.wait_for_events()
    report_import_poll_timer = mock_device:get_field("__recurring_import_report_poll_timer")
    import_timer_length = mock_device:get_field("__import_report_timeout")
    assert(report_import_poll_timer == nil, "report_import_poll_timer should exist")
    assert(import_timer_length == nil, "import_timer_length should exist")
  end
)

test.register_coroutine_test(
  "Generated periodic import energy device poll timer (<15 minutes) gets correctly set", function()
    test.socket["matter"]:__queue_receive(
      {
        mock_device_periodic.id,
        clusters.ElectricalEnergyMeasurement.attributes.PeriodicEnergyImported:build_test_report_data(
          mock_device_periodic, 1, periodic_report_val_23
        )
      }
    )
    test.socket["capability"]:__expect_send(
      mock_device_periodic:generate_test_message("main", capabilities.energyMeter.energy({ value = 23.0, unit = "Wh" }))
    )
    test.socket["matter"]:__queue_receive(
      {
        mock_device_periodic.id,
        clusters.ElectricalEnergyMeasurement.attributes.PeriodicEnergyImported:build_test_report_data(
          mock_device_periodic, 1, periodic_report_val_23
        )
      }
    )
    test.socket["capability"]:__expect_send(
      mock_device_periodic:generate_test_message("main", capabilities.energyMeter.energy({ value = 46.0, unit = "Wh" }))
    )
    test.wait_for_events()
    test.mock_time.advance_time(899)
    test.socket["matter"]:__queue_receive(
      {
        mock_device_periodic.id,
        clusters.ElectricalEnergyMeasurement.attributes.PeriodicEnergyImported:build_test_report_data(
          mock_device_periodic, 1, periodic_report_val_23
        )
      }
    )
    test.socket["capability"]:__expect_send(
      mock_device_periodic:generate_test_message("main", capabilities.energyMeter.energy({ value = 69.0, unit = "Wh" }))
    )
    test.wait_for_events()
    local report_import_poll_timer = mock_device_periodic:get_field("__recurring_import_report_poll_timer")
    local import_timer_length = mock_device_periodic:get_field("__import_report_timeout")
    assert(report_import_poll_timer ~= nil, "report_import_poll_timer should exist")
    assert(import_timer_length ~= nil, "import_timer_length should exist")
    assert(import_timer_length == MINIMUM_ST_ENERGY_REPORT_INTERVAL, "import_timer should min_interval")
  end,
  { test_init = test_init_periodic }
)

test.register_coroutine_test(
  "Generated periodic import energy device poll timer (>15 minutes) gets correctly set", function()
    test.socket["matter"]:__queue_receive(
      {
        mock_device_periodic.id,
        clusters.ElectricalEnergyMeasurement.attributes.PeriodicEnergyImported:build_test_report_data(
          mock_device_periodic, 1, periodic_report_val_23
        )
      }
    )
    test.socket["capability"]:__expect_send(
      mock_device_periodic:generate_test_message("main", capabilities.energyMeter.energy({ value = 23.0, unit = "Wh" }))
    )
    test.socket["matter"]:__queue_receive(
      {
        mock_device_periodic.id,
        clusters.ElectricalEnergyMeasurement.attributes.PeriodicEnergyImported:build_test_report_data(
          mock_device_periodic, 1, periodic_report_val_23
        )
      }
    )
    test.socket["capability"]:__expect_send(
      mock_device_periodic:generate_test_message("main", capabilities.energyMeter.energy({ value = 46.0, unit = "Wh" }))
    )
    test.wait_for_events()
    test.mock_time.advance_time(2000)
    test.socket["matter"]:__queue_receive(
      {
        mock_device_periodic.id,
        clusters.ElectricalEnergyMeasurement.attributes.PeriodicEnergyImported:build_test_report_data(
          mock_device_periodic, 1, periodic_report_val_23
        )
      }
    )
    test.socket["capability"]:__expect_send(
      mock_device_periodic:generate_test_message("main", capabilities.energyMeter.energy({ value = 69.0, unit = "Wh" }))
    )
    test.socket["capability"]:__expect_send(
      mock_device_periodic:generate_test_message("main", capabilities.powerConsumptionReport.powerConsumption({
        deltaEnergy=0.0,
        ["end"] = "1970-01-01T00:33:19Z",
        energy=69.0,
        start="1970-01-01T00:00:00Z"
      }))
    )
    test.wait_for_events()
    local report_import_poll_timer = mock_device_periodic:get_field("__recurring_import_report_poll_timer")
    local import_timer_length = mock_device_periodic:get_field("__import_report_timeout")
    assert(report_import_poll_timer ~= nil, "report_import_poll_timer should exist")
    assert(import_timer_length ~= nil, "import_timer_length should exist")
    assert(import_timer_length == 2000, "import_timer should min_interval")
  end,
  { test_init = test_init_periodic }
)

test.register_coroutine_test(
  "Test profile change on init for Electrical Sensor device type",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
    mock_device:expect_metadata_update({ profile = "plug-power-energy-powerConsumption" })
    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end,
  { test_init = test_init }
)

test.register_coroutine_test(
  "Test profile change on init for only Periodic Electrical Sensor device type",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device_periodic.id, "doConfigure" })
    mock_device_periodic:expect_metadata_update({ profile = "plug-energy-powerConsumption" })
    mock_device_periodic:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end,
  { test_init = test_init_periodic }
)

test.run_registered_tests()
