-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local t_utils = require "integration_test.utils"
local uint32 = require "st.matter.data_types.Uint32"
local version = require "version"
local st_utils = require "st.utils"

if version.api < 11 then
  clusters.ElectricalEnergyMeasurement = require "embedded_clusters.ElectricalEnergyMeasurement"
  clusters.ElectricalPowerMeasurement = require "embedded_clusters.ElectricalPowerMeasurement"
  clusters.PowerTopology = require "embedded_clusters.PowerTopology"
end

if version.api < 16 then
  clusters.Descriptor = require "embedded_clusters.Descriptor"
end

local mock_device = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("plug-level-power-energy-powerConsumption.yml"),
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
        { cluster_id = clusters.PowerTopology.ID, cluster_type = "SERVER", feature_map = 2, }, -- TREE_TOPOLOGY
      },
      device_types = {
        { device_type_id = 0x0510, device_type_revision = 1 }, -- Electrical Sensor
      }
    },
    {
      endpoint_id = 2,
      clusters = {
        { cluster_id = clusters.OnOff.ID, cluster_type = "SERVER", cluster_revision = 1, feature_map = 0, },
        {cluster_id = clusters.LevelControl.ID, cluster_type = "SERVER", feature_map = 2}
      },
      device_types = {
        { device_type_id = 0x010B, device_type_revision = 1 }, -- OnOff Dimmable Plug
      }
    },
    {
      endpoint_id = 3,
      clusters = {
        { cluster_id = clusters.ElectricalEnergyMeasurement.ID, cluster_type = "SERVER", feature_map = 14, },
        { cluster_id = clusters.PowerTopology.ID, cluster_type = "SERVER", feature_map = 2, }, -- TREE_TOPOLOGY
      },
      device_types = {
        { device_type_id = 0x0510, device_type_revision = 1 }, -- Electrical Sensor
      }
    },
    {
      endpoint_id = 4,
      clusters = {
        { cluster_id = clusters.OnOff.ID, cluster_type = "SERVER", cluster_revision = 1, feature_map = 0, },
        { cluster_id = clusters.LevelControl.ID, cluster_type = "SERVER", feature_map = 2},
      },
      device_types = {
        { device_type_id = 0x010B, device_type_revision = 1 }, -- OnOff Dimmable Plug
      }
    },
  },
})

local subscribed_attributes = {
  clusters.OnOff.attributes.OnOff,
  clusters.LevelControl.attributes.CurrentLevel,
  clusters.LevelControl.attributes.MaxLevel,
  clusters.LevelControl.attributes.MinLevel,
  clusters.ElectricalPowerMeasurement.attributes.ActivePower,
  clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyImported,
  clusters.ElectricalEnergyMeasurement.attributes.PeriodicEnergyImported,
  clusters.Descriptor.attributes.PartsList,
}

local cumulative_report_val_19 = {
  energy = 19000,
  start_timestamp = 0,
  end_timestamp = 0,
  start_systime = 0,
  end_systime = 0,
  apparent_energy = 0,
  reactive_energy = 0
}

local cumulative_report_val_29 = {
  energy = 29000,
  start_timestamp = 0,
  end_timestamp = 0,
  start_systime = 0,
  end_systime = 0,
  apparent_energy = 0,
  reactive_energy = 0
}

local cumulative_report_val_39 = {
  energy = 39000,
  start_timestamp = 0,
  end_timestamp = 0,
  start_systime = 0,
  end_systime = 0,
  apparent_energy = 0,
  reactive_energy = 0
}

local function test_init()
  test.mock_device.add_test_device(mock_device)
  local subscribe_request = subscribed_attributes[1]:subscribe(mock_device)
  for i, cluster in ipairs(subscribed_attributes) do
      if i > 1 then
          subscribe_request:merge(cluster:subscribe(mock_device))
      end
  end
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
  test.socket.matter:__expect_send({ mock_device.id, subscribe_request })
  test.socket.matter:__expect_send({ mock_device.id, subscribe_request })
end
test.set_test_init_function(test_init)

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
    {
      channel = "devices",
      direction = "send",
      message = {
        "register_native_capability_attr_handler",
        { device_uuid = mock_device.id, capability_id = "powerMeter", capability_attr_id = "power" }
      }
    }
  }
)

test.register_coroutine_test(
  "Cumulative Energy measurement should generate correct messages",
    function()

      test.mock_time.advance_time(901) -- move time 15 minutes past 0 (this can be assumed to be true in practice in all cases)

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

      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.powerConsumptionReport.powerConsumption({
          start = "1970-01-01T00:00:00Z",
          ["end"] = "1970-01-01T00:15:00Z",
          deltaEnergy = 0.0,
          energy = 19.0
        }))
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

      test.wait_for_events()
      test.mock_time.advance_time(1500)

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
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.powerConsumptionReport.powerConsumption({
          start = "1970-01-01T00:15:01Z",
          ["end"] = "1970-01-01T00:40:00Z",
          deltaEnergy = 20.0,
          energy = 39.0
        }))
      )
    end
)

test.register_coroutine_test(
  "Test profile change on init for Electrical Sensor device type",
  function()

    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
    test.socket.matter:__expect_send({mock_device.id, clusters.LevelControl.attributes.Options:write(mock_device, 2, clusters.LevelControl.types.OptionsBitmap.EXECUTE_IF_OFF)})
    test.socket.matter:__expect_send({mock_device.id, clusters.LevelControl.attributes.Options:write(mock_device, 4, clusters.LevelControl.types.OptionsBitmap.EXECUTE_IF_OFF)})
    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    test.wait_for_events()
    test.socket.matter:__queue_receive({ mock_device.id, clusters.Descriptor.attributes.PartsList:build_test_report_data(mock_device, 1, {uint32(2)})})
    test.socket.matter:__queue_receive({ mock_device.id, clusters.Descriptor.attributes.PartsList:build_test_report_data(mock_device, 3, {uint32(4)})})
    mock_device:expect_metadata_update({ profile = "plug-level-power-energy-powerConsumption" })
    mock_device:expect_device_create({
      type = "EDGE_CHILD",
      label = "nil 2",
      profile = "plug-level-energy-powerConsumption",
      parent_device_id = mock_device.id,
      parent_assigned_child_key = string.format("%d", 4)
    })
  end,
  { test_init = test_init }
)

test.register_message_test(
  "Set level command should send the appropriate commands",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "switchLevel", component = "main", command = "setLevel", args = {20,20} }
      }
    },
    {
      channel = "devices",
      direction = "send",
      message = {
        "register_native_capability_cmd_handler",
        { device_uuid = mock_device.id, capability_id = "switchLevel", capability_cmd_id = "setLevel" }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.LevelControl.server.commands.MoveToLevelWithOnOff(mock_device, 2, st_utils.round(20/100.0 * 254), 20, 0 ,0)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.LevelControl.server.commands.MoveToLevelWithOnOff:build_test_command_response(mock_device, 2)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.LevelControl.attributes.CurrentLevel:build_test_report_data(mock_device, 2, 50)
      }
    },
    {
      channel = "devices",
      direction = "send",
      message = {
        "register_native_capability_attr_handler",
        { device_uuid = mock_device.id, capability_id = "switchLevel", capability_attr_id = "level" }
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switchLevel.level(20))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.OnOff.attributes.OnOff:build_test_report_data(mock_device, 2, true)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switch.switch.on())
    },
    {
      channel = "devices",
      direction = "send",
      message = {
        "register_native_capability_attr_handler",
        { device_uuid = mock_device.id, capability_id = "switch", capability_attr_id = "switch" }
      }
    },
  }
)

test.run_registered_tests()
