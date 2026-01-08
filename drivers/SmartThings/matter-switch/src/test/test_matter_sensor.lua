-- Copyright © 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local t_utils = require "integration_test.utils"
local clusters = require "st.matter.clusters"
local uint32 = require "st.matter.data_types.Uint32"

local fields = require "switch_utils.fields"

local mock_device_humidity_battery = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("humidity.yml", {}),
  manufacturer_info = {
    vendor_id = 0x0000,
    product_id = 0x0000,
  },
  matter_version = {
    software = 1,
    hardware = 1,
  },
  endpoints = {
    {
      endpoint_id = 0,
      clusters = {
        {cluster_id = clusters.Basic.ID, cluster_type = "SERVER"},
        {cluster_id = clusters.PowerSource.ID, cluster_type = "SERVER", feature_map = 2}
      },
      device_types = {
        {device_type_id = 0x0016, device_type_revision = 1} -- RootNode
      }
    },
    {
      endpoint_id = 1,
      clusters = {
        {cluster_id = clusters.RelativeHumidityMeasurement.ID, cluster_type = "SERVER"},
      },
      device_types = {
        {device_type_id = fields.DEVICE_TYPE_ID.HUMIDITY_SENSOR, device_type_revision = 1}
      }
    }
  }
})

local cluster_subscribe_list_humidity_battery = {
  clusters.PowerSource.attributes.BatChargeLevel,
  clusters.RelativeHumidityMeasurement.attributes.MeasuredValue,
  clusters.PowerSource.attributes.AttributeList,
}


local function test_init()
  test.disable_startup_messages()
  test.mock_device.add_test_device(mock_device_humidity_battery)
  local subscribe_request = cluster_subscribe_list_humidity_battery[1]:subscribe(mock_device_humidity_battery)
  for i, cluster in ipairs(cluster_subscribe_list_humidity_battery) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(mock_device_humidity_battery))
    end
  end
  test.socket.device_lifecycle:__queue_receive({ mock_device_humidity_battery.id, "added" })
  test.socket.matter:__expect_send({mock_device_humidity_battery.id, subscribe_request})

  test.socket.device_lifecycle:__queue_receive({ mock_device_humidity_battery.id, "init" })
  test.socket.matter:__expect_send({mock_device_humidity_battery.id, subscribe_request})

  test.socket.device_lifecycle:__queue_receive({ mock_device_humidity_battery.id, "doConfigure" })
  mock_device_humidity_battery:expect_metadata_update({ provisioning_state = "PROVISIONED" })
end
test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Test profile change when battery percent remaining attribute (attribute ID 12) is available",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device_humidity_battery.id,
        clusters.PowerSource.attributes.AttributeList:build_test_report_data(mock_device_humidity_battery, 2,
          {
            uint32(0),
            uint32(1),
            uint32(2),
            uint32(12),
            uint32(31),
            uint32(65528),
            uint32(65529),
            uint32(65531),
            uint32(65532),
            uint32(65533),
          })
      }
    )
    mock_device_humidity_battery:expect_metadata_update({ profile = "humidity", optional_component_capabilities = {{"main", {"battery"}}} })
  end
)

test.register_coroutine_test(
  "Test profile change when battery level attribute (attribute ID 14) is available",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device_humidity_battery.id,
        clusters.PowerSource.attributes.AttributeList:build_test_report_data(mock_device_humidity_battery, 2,
          {
            uint32(0),
            uint32(1),
            uint32(2),
            uint32(14),
            uint32(31),
            uint32(65528),
            uint32(65529),
            uint32(65531),
            uint32(65532),
            uint32(65533),
          })
      }
    )
    mock_device_humidity_battery:expect_metadata_update({ profile = "humidity", optional_component_capabilities = {{"main", {"batteryLevel"}}} })
  end
)

test.register_coroutine_test(
  "Test that profile does not change when battery percent remaining and battery level attributes are not available",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device_humidity_battery.id,
        clusters.PowerSource.attributes.AttributeList:build_test_report_data(mock_device_humidity_battery, 2,
          {
            uint32(0),
            uint32(1),
            uint32(2),
            uint32(31),
            uint32(65528),
            uint32(65529),
            uint32(65531),
            uint32(65532),
            uint32(65533),
          })
      }
    )
  end
)

test.run_registered_tests()
