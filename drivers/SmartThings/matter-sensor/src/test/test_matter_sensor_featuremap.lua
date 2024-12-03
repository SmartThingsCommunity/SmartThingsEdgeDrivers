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
local t_utils = require "integration_test.utils"
local clusters = require "st.matter.clusters"

local mock_device_humidity_battery = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("humidity-batteryLevel.yml"),
  manufacturer_info = {
    vendor_id = 0x0000,
    product_id = 0x0000,
  },
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
        {cluster_id = clusters.RelativeHumidityMeasurement.ID, cluster_type = "SERVER"},
      },
      device_types = {}
    },
    {
      endpoint_id = 2,
      clusters = {
        {cluster_id = clusters.PowerSource.ID, cluster_type = "SERVER", feature_map = 2},
      },
      device_types = {}
    }
  }
})

local mock_device_humidity_no_battery = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("humidity-battery.yml"),
  manufacturer_info = {
    vendor_id = 0x0000,
    product_id = 0x0000,
  },
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
        {cluster_id = clusters.RelativeHumidityMeasurement.ID, cluster_type = "SERVER"},
      },
      device_types = {}
    }
  }
})

local mock_device_temp_humidity = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("temperature-humidity.yml"),
  manufacturer_info = {
    vendor_id = 0x0000,
    product_id = 0x0000,
  },
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
        {cluster_id = clusters.RelativeHumidityMeasurement.ID, cluster_type = "SERVER"},
      },
      device_types = {}
    },
    {
      endpoint_id = 2,
      clusters = {
        {cluster_id = clusters.TemperatureMeasurement.ID, cluster_type = "BOTH"},
      },
      device_types = {}
    }
  }
})

local cluster_subscribe_list_humidity_battery = {
  clusters.PowerSource.attributes.BatChargeLevel,
  clusters.RelativeHumidityMeasurement.attributes.MeasuredValue,
}

local cluster_subscribe_list_humidity_no_battery = {
  clusters.RelativeHumidityMeasurement.attributes.MeasuredValue
}

local cluster_subscribe_list_temp_humidity = {
  clusters.RelativeHumidityMeasurement.attributes.MeasuredValue,
  clusters.TemperatureMeasurement.attributes.MeasuredValue,
  clusters.TemperatureMeasurement.attributes.MinMeasuredValue,
  clusters.TemperatureMeasurement.attributes.MaxMeasuredValue
}

local function test_init_humidity_battery()
  local subscribe_request_humidity_battery = cluster_subscribe_list_humidity_battery[1]:subscribe(mock_device_humidity_battery)
  for i, cluster in ipairs(cluster_subscribe_list_humidity_battery) do
    if i > 1 then
      subscribe_request_humidity_battery:merge(cluster:subscribe(mock_device_humidity_battery))
    end
  end

  test.socket.matter:__expect_send({mock_device_humidity_battery.id, subscribe_request_humidity_battery})
  test.mock_device.add_test_device(mock_device_humidity_battery)

  test.socket.device_lifecycle:__queue_receive({ mock_device_humidity_battery.id, "added" })
  local read_attribute_list = clusters.PowerSource.attributes.AttributeList:read()
  test.socket.matter:__expect_send({mock_device_humidity_battery.id, read_attribute_list})
  test.socket.device_lifecycle:__queue_receive({ mock_device_humidity_battery.id, "doConfigure" })
  mock_device_humidity_battery:expect_metadata_update({ profile = "humidity-batteryLevel" })
  mock_device_humidity_battery:expect_metadata_update({ provisioning_state = "PROVISIONED" })
end

local function test_init_humidity_no_battery()
  local subscribe_request_humidity_no_battery = cluster_subscribe_list_humidity_no_battery[1]:subscribe(mock_device_humidity_no_battery)
  for i, cluster in ipairs(cluster_subscribe_list_humidity_no_battery) do
    if i > 1 then
      subscribe_request_humidity_no_battery:merge(cluster:subscribe(mock_device_humidity_no_battery))
    end
  end

  test.socket.matter:__expect_send({mock_device_humidity_no_battery.id, subscribe_request_humidity_no_battery})
  test.mock_device.add_test_device(mock_device_humidity_no_battery)

  test.socket.device_lifecycle:__queue_receive({ mock_device_humidity_no_battery.id, "added" })
  local read_attribute_list = clusters.PowerSource.attributes.AttributeList:read()
  test.socket.matter:__expect_send({mock_device_humidity_no_battery.id, read_attribute_list})
  test.socket.device_lifecycle:__queue_receive({ mock_device_humidity_no_battery.id, "doConfigure" })
  mock_device_humidity_no_battery:expect_metadata_update({ profile = "humidity" })
  mock_device_humidity_no_battery:expect_metadata_update({ provisioning_state = "PROVISIONED" })
end

local function test_init_temp_humidity()
  local subscribe_request_temp_humidity = cluster_subscribe_list_temp_humidity[1]:subscribe(mock_device_temp_humidity)
  for i, cluster in ipairs(cluster_subscribe_list_temp_humidity) do
    if i > 1 then
      subscribe_request_temp_humidity:merge(cluster:subscribe(mock_device_temp_humidity))
    end
  end

  test.socket.matter:__expect_send({mock_device_temp_humidity.id, subscribe_request_temp_humidity})
  test.mock_device.add_test_device(mock_device_temp_humidity)

  test.socket.device_lifecycle:__queue_receive({ mock_device_temp_humidity.id, "added" })
  local read_attribute_list = clusters.PowerSource.attributes.AttributeList:read()
  test.socket.matter:__expect_send({mock_device_temp_humidity.id, read_attribute_list})
  test.socket.device_lifecycle:__queue_receive({ mock_device_temp_humidity.id, "doConfigure" })
  mock_device_temp_humidity:expect_metadata_update({ profile = "temperature-humidity" })
  mock_device_temp_humidity:expect_metadata_update({ provisioning_state = "PROVISIONED" })
end

-- The encoded TLV value of "\x16\x04\x00\x04\x01\x04\x02\x04\x0C\x04\x1F\x05\xF8\xFF\x05\xF9\xFF\x05\xFB\xFF\x05\xFC\xFF\x05\xFD\xFF\x18" corresponds to the following table.
--
--{
--  attribute={
--    ID=65531,
--    NAME="AttributeList",
--    _cluster={
--      FeatureMap={
--        BASE_MASK=65535,
--        BATTERY=2,
--        RECHARGEABLE=4,
--        REPLACEABLE=8,
--        WIRED=1,
--        augment_type=function: 0xd155a8,
--        bits_are_valid=function: 0xd04af0,
--        is_battery_set=function: 0xd11d98,
--        is_rechargeable_set=function: 0xd04da0,
--        is_replaceable_set=function: 0xd13188,
--        is_wired_set=function: 0xd04100,
--        mask_fields={
--          BASE_MASK=65535,
--          BATTERY=2,
--          RECHARGEABLE=4,
--          REPLACEABLE=8,
--          WIRED=1,
--        },
--        mask_methods={
--          is_battery_set=function: 0xd11d98,
--          is_rechargeable_set=function: 0xd04da0,
--          is_replaceable_set=function: 0xd13188,
--          is_wired_set=function: 0xd04100,
--          set_battery=function: 0xd09128,
--          set_rechargeable=function: 0xcfa258,
--          set_replaceable=function: 0xd04e78,
--          set_wired=function: 0xd05be8,
--          unset_battery=function: 0xcff0a0,
--          unset_rechargeable=function: 0xd12330,
--          unset_replaceable=function: 0xd02548,
--          unset_wired=function: 0xd04b98,
--        },
--        set_battery=function: 0xd09128,
--        set_rechargeable=function: 0xcfa258,
--        set_replaceable=function: 0xd04e78,
--        set_wired=function: 0xd05be8,
--        unset_battery=function: 0xcff0a0,
--        unset_rechargeable=function: 0xd12330,
--        unset_replaceable=function: 0xd02548,
--        unset_wired=function: 0xd04b98,
--      },
--      ID=47,
--      NAME="PowerSource",
--      are_features_supported=function: 0xcfd118,
--      attribute_direction_map={
--        AcceptedCommandList="server",
--        ActiveBatChargeFaults="server",
--        ActiveBatFaults="server",
--        ActiveWiredFaults="server",
--        AttributeList="server",
--        BatANSIDesignation="server",
--        BatApprovedChemistry="server",
--        BatCapacity="server",
--        BatChargeLevel="server",
--        BatChargeState="server",
--        BatChargingCurrent="server",
--        BatCommonDesignation="server",
--        BatFunctionalWhileCharging="server",
--        BatIECDesignation="server",
--        BatPercentRemaining="server",
--        BatPresent="server",
--        BatQuantity="server",
--        BatReplaceability="server",
--        BatReplacementDescription="server",
--        BatReplacementNeeded="server",
--        BatTimeRemaining="server",
--        BatTimeToFullCharge="server",
--        BatVoltage="server",
--        Description="server",
--        EndpointList="server",
--        EventList="server",
--        Order="server",
--        Status="server",
--        WiredAssessedCurrent="server",
--        WiredAssessedInputFrequency="server",
--        WiredAssessedInputVoltage="server",
--        WiredCurrentType="server",
--        WiredMaximumCurrent="server",
--        WiredNominalVoltage="server",
--        WiredPresent="server",
--      },
--      attributes={},
--      client={},
--      command_direction_map={},
--      commands={},
--      events={},
--      get_attribute_by_id=function: 0xd12f90,
--      get_event_by_id=function: 0xcfa000,
--      get_server_command_by_id=function: 0xd12580,
--      server={
--        attributes={
--        _cluster=RecursiveTable: _cluster,
--        set_parent_cluster=function: 0xd12318,
--        },
--        commands={
--          _cluster=RecursiveTable: _cluster,
--          set_parent_cluster=function: 0xd02580,
--        },
--        events={
--          _cluster=RecursiveTable: _cluster,
--          set_parent_cluster=function: 0xd04968,
--        },
--      },
--      types={},
--    },
--    augment_type=function: 0xd6fa00,
--    base_type={},
--    build_test_report_data=function: 0xcec2d8,
--    deserialize=function: 0xd60f90,
--    element_type={},
--    new_value=function: 0xd70660,
--    read=function: 0xd709e0,
--    set_parent_cluster=function: 0xd45a70,
--    subscribe=function: 0xd6fa20,
--  },
--  attribute_id=65531,
--  cluster=RecursiveTable: _cluster,
--  cluster_id=47,
--  data={
--    elements={
--      {
--        value=0,
--      },
--      {
--        value=1,
--      },
--      {
--        value=2,
--      },
--      {
--        value=12,
--      },
--      {
--        value=31,
--      },
--      {
--        value=65528,
--      },
--      {
--        value=65529,
--      },
--      {
--        value=65531,
--      },
--      {
--        value=65532,
--      },
--      {
--        value=65533,
--      },
--    },
--    num_elements=10,
--  },
--  endpoint_id=1,
--  tlv="\x16\x04\x00\x04\x01\x04\x02\x04\x0C\x04\x1F\x05\xF8\xFF\x05\xF9\xFF\x05\xFB\xFF\x05\xFC\xFF\x05\xFD\xFF\x18",
--}

local im = require "st.matter.interaction_model"
local function create_interaction_response()
  local status = im.InteractionResponse.Status.SUCCESS
  local tlv_encoded = "\x16\x04\x00\x04\x01\x04\x02\x04\x0C\x04\x1F\x05\xF8\xFF\x05\xF9\xFF\x05\xFB\xFF\x05\xFC\xFF\x05\xFD\xFF\x18"
  local interaction_info_block = im.InteractionInfoBlock(
    2, 47, 65531, nil, nil, tlv_encoded
  )
  local interaction_response_info_block = im.InteractionResponseInfoBlock(
    interaction_info_block, status, nil, nil
  )
  local interaction_response = im.InteractionResponse(
    im.InteractionResponse.ResponseType.REPORT_DATA,
    {interaction_response_info_block}, nil, nil
  )
  return interaction_response
end

test.register_coroutine_test(
  "Test profile change on init for humidity sensor with battery",
  function()
    test.socket.capability:__set_channel_ordering("relaxed")

    test.socket.matter:__queue_receive(
      {
        mock_device_humidity_battery.id,
        create_interaction_response()
      }
    )
    mock_device_humidity_battery:expect_metadata_update({ profile = "humidity-battery" })
  end,
  { test_init = test_init_humidity_battery }
)

test.register_coroutine_test(
  "Test profile change on init for humidity sensor without battery",
  function()
  end,
  { test_init = test_init_humidity_no_battery }
)

test.register_coroutine_test(
  "Test profile change on init for temperature-humidity sensor",
  function()
  end,
  { test_init = test_init_temp_humidity }
)

test.run_registered_tests()
