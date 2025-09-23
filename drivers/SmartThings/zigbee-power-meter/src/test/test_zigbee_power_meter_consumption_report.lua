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

-- Mock out globals
local test = require "integration_test"
local clusters = require "st.zigbee.zcl.clusters"
local ElectricalMeasurement = clusters.ElectricalMeasurement
local SimpleMetering = clusters.SimpleMetering
local capabilities = require "st.capabilities"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils = require "integration_test.utils"
local messages = require "st.zigbee.messages"
local config_reporting_response = require "st.zigbee.zcl.global_commands.configure_reporting_response"
local zb_const = require "st.zigbee.constants"
local zcl_messages = require "st.zigbee.zcl"
local data_types = require "st.zigbee.data_types"
local Status = require "st.zigbee.generated.types.ZclStatus"

local mock_device = test.mock_device.build_test_zigbee_device(
    {
      profile = t_utils.get_profile_definition("power-meter-consumption-report.yml"),
      zigbee_endpoints = {
        [1] = {
          id = 1,
          model = "E240-KR080Z0-HA",
          server_clusters = {SimpleMetering.ID, ElectricalMeasurement.ID}
        }
      }
    }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  mock_device:set_field("_configuration_version", 1, {persist = true})
  test.mock_device.add_test_device(mock_device)
end

test.set_test_init_function(test_init)

local function build_config_response_msg(device, cluster, global_status, attribute, attr_status)
  local addr_header = messages.AddressHeader(
    device:get_short_address(),
    device.fingerprinted_endpoint_id,
    zb_const.HUB.ADDR,
    zb_const.HUB.ENDPOINT,
    zb_const.HA_PROFILE_ID,
    cluster
  )
  local config_response_body
  if global_status ~= nil then
     config_response_body = config_reporting_response.ConfigureReportingResponse({}, global_status)
  else
    local individual_record = config_reporting_response.ConfigureReportingResponseRecord(attr_status, 0x01, attribute)
    config_response_body = config_reporting_response.ConfigureReportingResponse({individual_record}, nil)
  end
  local zcl_header = zcl_messages.ZclHeader({
    cmd = data_types.ZCLCommandId(config_response_body.ID)
  })
  local message_body = zcl_messages.ZclMessageBody({
    zcl_header = zcl_header,
    zcl_body = config_response_body
  })
  return messages.ZigbeeMessageRx({
    address_header = addr_header,
    body = message_body
  })
end

test.register_message_test(
    "ActivePower Report should be handled. Sensor value is in W, capability attribute value is in hectowatts",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, ElectricalMeasurement.attributes.ACPowerDivisor:build_test_attr_report(mock_device, 0x0A) }
      },
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, ElectricalMeasurement.attributes.ActivePower:build_test_attr_report(mock_device,
                                                                                                        27) },
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.powerMeter.power({ value = 2.7, unit = "W" }))
      }
    }
)

test.register_message_test(
  "SimpleMetering event should be handled by powerConsumptionReport capability",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, SimpleMetering.attributes.CurrentSummationDelivered:build_test_attr_report(mock_device, 1000) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.powerConsumptionReport.powerConsumption({energy = 1.0, deltaEnergy = 0.0 }))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.energyMeter.energy({value = 0.001, unit = "kWh"}))
    },
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, SimpleMetering.attributes.CurrentSummationDelivered:build_test_attr_report(mock_device, 1500) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.powerConsumptionReport.powerConsumption({energy = 1.5, deltaEnergy = 0.5 }))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.energyMeter.energy({value = 0.0015, unit = "kWh"}))
    }
  }
)

test.register_coroutine_test(
    "lifecycle configure event should configure device",
    function ()
      test.socket.zigbee:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         SimpleMetering.attributes.InstantaneousDemand:read(mock_device)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         SimpleMetering.attributes.CurrentSummationDelivered:read(mock_device)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         ElectricalMeasurement.attributes.ActivePower:read(mock_device)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                        ElectricalMeasurement.attributes.ACPowerMultiplier:read(mock_device)
                                      })
      test.socket.zigbee:__expect_send({
                                        mock_device.id,
                                        ElectricalMeasurement.attributes.ACPowerDivisor:read(mock_device)
                                      })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         zigbee_test_utils.build_bind_request(mock_device,
                                                                              zigbee_test_utils.mock_hub_eui,
                                                                              SimpleMetering.ID)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         SimpleMetering.attributes.InstantaneousDemand:configure_reporting(mock_device, 5, 3600, 500)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         SimpleMetering.attributes.CurrentSummationDelivered:configure_reporting(mock_device, 5, 3600, 1)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         zigbee_test_utils.build_bind_request(mock_device,
                                                                              zigbee_test_utils.mock_hub_eui,
                                                                              ElectricalMeasurement.ID)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         ElectricalMeasurement.attributes.ActivePower:configure_reporting(mock_device, 5, 3600, 5)
                                       })
      test.socket.zigbee:__expect_send({
                                        mock_device.id,
                                        ElectricalMeasurement.attributes.ACPowerMultiplier:configure_reporting(mock_device, 1, 43200, 1)
                                      })
      test.socket.zigbee:__expect_send({
                                        mock_device.id,
                                        ElectricalMeasurement.attributes.ACPowerDivisor:configure_reporting(mock_device, 1, 43200, 1)
                                      })
      mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    end
)

test.register_coroutine_test(
    "configuration version below 1 use override configs",
    function()
      test.socket.zigbee:__set_channel_ordering("relaxed")
      test.timer.__create_and_queue_test_time_advance_timer(5*60, "oneshot")
      assert(mock_device:get_field("_configuration_version") == nil)
      test.mock_device.add_test_device(mock_device)
      test.socket.device_lifecycle:__queue_receive({ mock_device.id, "init" })
      test.wait_for_events()
      test.socket.zigbee:__expect_send({mock_device.id, ElectricalMeasurement.attributes.ActivePower:configure_reporting(mock_device, 5, 3600, 5)})
      test.socket.zigbee:__expect_send({mock_device.id, SimpleMetering.attributes.InstantaneousDemand:configure_reporting(mock_device, 5, 3600, 500)})
      test.socket.zigbee:__expect_send({mock_device.id, SimpleMetering.attributes.CurrentSummationDelivered:configure_reporting(mock_device, 5, 3600, 1)})
      test.mock_time.advance_time(5*60 + 1)
      test.wait_for_events()
      test.socket.zigbee:__queue_receive({mock_device.id, build_config_response_msg(mock_device, ElectricalMeasurement.ID, Status.SUCCESS)})
      test.socket.zigbee:__queue_receive({mock_device.id, build_config_response_msg(mock_device, SimpleMetering.ID, Status.SUCCESS)})
      test.wait_for_events()
      assert(mock_device:get_field("_configuration_version") == 1)
    end,
    {
      test_init = function()
        -- no op to override auto device add on startup
      end
    }
)


test.run_registered_tests()
