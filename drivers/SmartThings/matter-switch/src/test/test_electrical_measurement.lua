-- Copyright © 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local clusters = require "st.matter.clusters"
local t_utils = require "integration_test.utils"
local version = require "version"
local switch_fields = require "switch_utils.fields"

if version.api < 11 then
  clusters.ElectricalEnergyMeasurement = require "embedded_clusters.ElectricalEnergyMeasurement"
  clusters.ElectricalPowerMeasurement = require "embedded_clusters.ElectricalPowerMeasurement"
  clusters.PowerTopology = require "embedded_clusters.PowerTopology"
end

local mock_device_with_electrical_measurement_clusters = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("plug-power-energy-powerConsumption.yml"),
  manufacturer_info = {
    vendor_id = 0x0000,
    product_id = 0x0000,
  },
  endpoints = {
    {
      endpoint_id = 2,
      clusters = {
        { cluster_id = clusters.ElectricalEnergyMeasurement.ID, cluster_type = "SERVER", feature_map = 14, },
        { cluster_id = clusters.ElectricalPowerMeasurement.ID, cluster_type = "SERVER", feature_map = 0, },
        { cluster_id = clusters.OnOff.ID, cluster_type = "SERVER", cluster_revision = 1, feature_map = 0, },
      },
      device_types = {
        { device_type_id = switch_fields.DEVICE_TYPE_ID.ON_OFF_PLUG_IN_UNIT, device_type_revision = 1 },
      }
    }
  },
})

local mock_device_with_electrical_measurement_clusters_on_root = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("plug-power-energy-powerConsumption.yml"),
  manufacturer_info = {
    vendor_id = 0x0000,
    product_id = 0x0000,
  },
  endpoints = {
    {
      endpoint_id = 0,
      clusters = {
        { cluster_id = clusters.ElectricalEnergyMeasurement.ID, cluster_type = "SERVER", feature_map = 14, },
        { cluster_id = clusters.ElectricalPowerMeasurement.ID, cluster_type = "SERVER", feature_map = 0, },
      },
      device_types = {
        { device_type_id = 0x0016, device_type_revision = 1 },
      },
    },
    {
      endpoint_id = 2,
      clusters = {
        { cluster_id = clusters.OnOff.ID, cluster_type = "SERVER", cluster_revision = 1, feature_map = 0, },
      },
      device_types = {
        { device_type_id = switch_fields.DEVICE_TYPE_ID.ON_OFF_PLUG_IN_UNIT, device_type_revision = 1 },
      }
    }
  },
})

local function test_init()
  test.disable_startup_messages()
  test.mock_device.add_test_device(mock_device_with_electrical_measurement_clusters)
end
test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Test init for OnOff Plug with Electrical Measurement clusters is handled properly",
  function()
    local subscribed_attributes = {
      clusters.OnOff.attributes.OnOff,
      clusters.ElectricalPowerMeasurement.attributes.ActivePower,
      clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyImported,
      clusters.ElectricalEnergyMeasurement.attributes.PeriodicEnergyImported,
    }
    local subscribe_request = subscribed_attributes[1]:subscribe(mock_device_with_electrical_measurement_clusters)
    for i, cluster in ipairs(subscribed_attributes) do
        if i > 1 then
            subscribe_request:merge(cluster:subscribe(mock_device_with_electrical_measurement_clusters))
        end
    end
    test.socket.device_lifecycle:__queue_receive({ mock_device_with_electrical_measurement_clusters.id, "init" })
    test.socket.matter:__expect_send({ mock_device_with_electrical_measurement_clusters.id, subscribe_request })
    test.wait_for_events()
    print(mock_device_with_electrical_measurement_clusters:get_field(switch_fields.ELECTRICAL_TAGS .. "_2"))
    assert(mock_device_with_electrical_measurement_clusters:get_field(switch_fields.ELECTRICAL_TAGS .. "_2") == "-power-energy-powerConsumption", "Expected electrical tags on EP 2 field to be set correctly")
    assert(mock_device_with_electrical_measurement_clusters:get_field(switch_fields.CUMULATIVE_REPORTS_SUPPORTED) == true, "Expected cumulative reports supported field to be set to true")
    assert(mock_device_with_electrical_measurement_clusters:get_field(switch_fields.ASSIGNED_CHILD_KEY .. "_2") == "2", "Expected assigned child key to be correctly set to the associated EP 2 ID")
  end,
  {
    min_api_version = 17
  }
)

test.register_coroutine_test(
  "Test init for OnOff Plug with Electrical Measurement clusters on Root is handled properly",
  function()
    local subscribed_attributes = {
      clusters.OnOff.attributes.OnOff,
      clusters.ElectricalPowerMeasurement.attributes.ActivePower,
      clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyImported,
      clusters.ElectricalEnergyMeasurement.attributes.PeriodicEnergyImported,
    }
    local subscribe_request = subscribed_attributes[1]:subscribe(mock_device_with_electrical_measurement_clusters_on_root)
    for i, cluster in ipairs(subscribed_attributes) do
        if i > 1 then
            subscribe_request:merge(cluster:subscribe(mock_device_with_electrical_measurement_clusters_on_root))
        end
    end
    test.socket.device_lifecycle:__queue_receive({ mock_device_with_electrical_measurement_clusters_on_root.id, "init" })
    test.socket.matter:__expect_send({ mock_device_with_electrical_measurement_clusters_on_root.id, subscribe_request })
    test.wait_for_events()
    assert(mock_device_with_electrical_measurement_clusters_on_root:get_field(switch_fields.ELECTRICAL_TAGS .. "_2") == "-power-energy-powerConsumption", "Expected electrical tags on EP 2 field to be set correctly")
    assert(mock_device_with_electrical_measurement_clusters_on_root:get_field(switch_fields.CUMULATIVE_REPORTS_SUPPORTED) == true, "Expected cumulative reports supported field to be set to true")
    assert(mock_device_with_electrical_measurement_clusters_on_root:get_field(switch_fields.ASSIGNED_CHILD_KEY .. "_0") == "2", "Expected assigned child key to be correctly set to the associated EP 2 ID")
  end,
  {
    test_init = function()
      test.disable_startup_messages()
      test.mock_device.add_test_device(mock_device_with_electrical_measurement_clusters_on_root)
    end,
    min_api_version = 17
  }
)

test.register_coroutine_test(
  "Test doConfigure for OnOff Plug with Electrical Measurement clusters is handled properly",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device_with_electrical_measurement_clusters.id, "doConfigure" })
    mock_device_with_electrical_measurement_clusters:expect_metadata_update({ profile = "plug-power-energy-powerConsumption" })
    mock_device_with_electrical_measurement_clusters:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end,
  {
    test_init = function()
      test.disable_startup_messages()
      test.mock_device.add_test_device(mock_device_with_electrical_measurement_clusters)
      mock_device_with_electrical_measurement_clusters:set_field(switch_fields.ELECTRICAL_TAGS .. "_2", "-power-energy-powerConsumption", {persist = true})
      mock_device_with_electrical_measurement_clusters:set_field(switch_fields.profiling_data.BATTERY_SUPPORT, false, {persist = true})
      mock_device_with_electrical_measurement_clusters:set_field(switch_fields.profiling_data.POWER_TOPOLOGY, false, {persist = true})
    end,
    min_api_version = 17
  }
)

test.register_coroutine_test(
  "Test doConfigure for OnOff Plug with some Electrical Power Measurement cluster is handled properly",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device_with_electrical_measurement_clusters.id, "doConfigure" })
    mock_device_with_electrical_measurement_clusters:expect_metadata_update({ profile = "plug-power" })
    mock_device_with_electrical_measurement_clusters:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end,
  {
    test_init = function()
      test.disable_startup_messages()
      test.mock_device.add_test_device(mock_device_with_electrical_measurement_clusters)
      mock_device_with_electrical_measurement_clusters:set_field(switch_fields.ELECTRICAL_TAGS .. "_2", "-power", {persist = true})
      mock_device_with_electrical_measurement_clusters:set_field(switch_fields.profiling_data.BATTERY_SUPPORT, false, {persist = true})
      mock_device_with_electrical_measurement_clusters:set_field(switch_fields.profiling_data.POWER_TOPOLOGY, false, {persist = true})
    end,
    min_api_version = 17
  }
)

test.register_coroutine_test(
  "Test doConfigure for OnOff Plug with Electrical Energy Measurement cluster is handled properly",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device_with_electrical_measurement_clusters.id, "doConfigure" })
    mock_device_with_electrical_measurement_clusters:expect_metadata_update({ profile = "plug-energy-powerConsumption" })
    mock_device_with_electrical_measurement_clusters:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end,
  {
    test_init = function()
      test.disable_startup_messages()
      test.mock_device.add_test_device(mock_device_with_electrical_measurement_clusters)
      mock_device_with_electrical_measurement_clusters:set_field(switch_fields.ELECTRICAL_TAGS .. "_2", "-energy-powerConsumption", {persist = true})
      mock_device_with_electrical_measurement_clusters:set_field(switch_fields.profiling_data.BATTERY_SUPPORT, false, {persist = true})
      mock_device_with_electrical_measurement_clusters:set_field(switch_fields.profiling_data.POWER_TOPOLOGY, false, {persist = true})
    end,
    min_api_version = 17
  }
)

test.run_registered_tests()
