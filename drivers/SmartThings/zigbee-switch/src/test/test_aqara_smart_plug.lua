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

local base64 = require "st.base64"
local clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local capabilities = require "st.capabilities"
local SinglePrecisionFloat = require "st.zigbee.data_types".SinglePrecisionFloat

local t_utils = require "integration_test.utils"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local test = require "integration_test"

local OnOff = clusters.OnOff
local SimpleMetering = clusters.SimpleMetering
local ElectricalMeasurement = clusters.ElectricalMeasurement
local AnalogInput = clusters.AnalogInput
local Basic = clusters.Basic

local MFG_CODE = 0x115F
local PRIVATE_CLUSTER_ID = 0xFCC0
local PRIVATE_ATTRIBUTE_ID = 0x0009

local PREF_CLUSTER_ID = 0xFCC0
local PREF_MAX_POWER_ATTR_ID = 0x020B
local PREF_RESTORE_STATE_ATTR_ID = 0x0201

local ENDPOINT_POWER_METER = 0x15
local ENDPOINT_ENERGY_METER = 0x1F

local LAST_REPORT_TIME = "LAST_REPORT_TIME"
local APPLICATION_VERSION = "application_version"

local mock_device = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("switch-power-energy-consumption-report-aqara.yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "LUMI",
        model = "lumi.plug.maeu01",
        server_clusters = { OnOff.ID, SimpleMetering.ID, ElectricalMeasurement.ID }
      }
    }
  }
)

local mock_device_version = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("switch-power-energy-consumption-report-aqara.yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "LUMI",
        model = "lumi.plug.maeu01",
        server_clusters = { OnOff.ID, AnalogInput.ID }
      }
    }
  }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device)
  test.mock_device.add_test_device(mock_device_version)
  zigbee_test_utils.init_noop_health_check_timer()
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Handle added lifecycle",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.switch.switch.off())
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.powerMeter.power({ value = 0.0, unit = "W" }))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.energyMeter.energy({ value = 0.0, unit = "Wh" }))
    )
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, PRIVATE_ATTRIBUTE_ID,
          MFG_CODE, data_types.Uint8, 1)
      }
    )
  end
)

test.register_coroutine_test(
  "Handle doConfigure lifecycle",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device,
        zigbee_test_utils.mock_hub_eui,
        ElectricalMeasurement.ID)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      ElectricalMeasurement.attributes.ActivePower:configure_reporting(mock_device, 1, 3600, 5)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device,
        zigbee_test_utils.mock_hub_eui,
        SimpleMetering.ID)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      SimpleMetering.attributes.InstantaneousDemand:configure_reporting(mock_device, 1, 3600, 5)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      SimpleMetering.attributes.CurrentSummationDelivered:configure_reporting(mock_device, 5, 3600, 1)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      SimpleMetering.attributes.CurrentSummationDelivered:configure_reporting(mock_device, 900, 3600, 1)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device,
        zigbee_test_utils.mock_hub_eui,
        OnOff.ID)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      OnOff.attributes.OnOff:configure_reporting(mock_device, 0, 300)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      Basic.attributes.ApplicationVersion:read(mock_device)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      OnOff.attributes.OnOff:read(mock_device)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      ElectricalMeasurement.attributes.ActivePower:read(mock_device)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      SimpleMetering.attributes.CurrentSummationDelivered:read(mock_device)
    })
    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)

test.register_message_test(
  "Capability command On should be handled",
  {
    {
      channel = "capability",
      direction = "receive",
      message = { mock_device.id, { capability = "switch", component = "main", command = "on", args = {} } }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = { mock_device.id, OnOff.server.commands.On(mock_device) }
    }
  }
)

test.register_message_test(
  "Capability command Off should be handled",
  {
    {
      channel = "capability",
      direction = "receive",
      message = { mock_device.id, { capability = "switch", component = "main", command = "off", args = {} } }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = { mock_device.id, OnOff.server.commands.Off(mock_device) }
    }
  }
)

test.register_coroutine_test(
  "On attribute handled",
  function()
    test.socket.zigbee:__queue_receive(
      {
        mock_device.id,
        OnOff.attributes.OnOff:build_test_attr_report(mock_device, true)
      }
    )
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.switch.switch.on())
    )
  end
)

test.register_coroutine_test(
  "Off attribute handled",
  function()
    test.socket.zigbee:__queue_receive(
      {
        mock_device.id,
        OnOff.attributes.OnOff:build_test_attr_report(mock_device, false)
      }
    )
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.switch.switch.off())
    )
  end
)

test.register_coroutine_test(
  "Handle power meter",
  function()
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      SimpleMetering.attributes.InstantaneousDemand:build_test_attr_report(mock_device, 10)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.powerMeter.power({ value = 10000.0, unit = "W" }))
    )
  end
)

test.register_coroutine_test(
  "Handle energy meter",
  function()
    local current_time = os.time() - 60 * 20
    mock_device:set_field(LAST_REPORT_TIME, current_time)

    test.socket.zigbee:__queue_receive({
      mock_device.id,
      SimpleMetering.attributes.CurrentSummationDelivered:build_test_attr_report(mock_device, 10)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.energyMeter.energy({ value = 10, unit = "Wh" }))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.powerConsumptionReport.powerConsumption({ deltaEnergy = 0.0, energy = 10 }))
    )
  end
)

test.register_coroutine_test(
  "Handle maxPower in infochanged",
  function()
    test.socket.environment_update:__queue_receive({ "zigbee",
      { hub_zigbee_id = base64.encode(zigbee_test_utils.mock_hub_eui) } })
    local updates = {
      preferences = {
      }
    }
    updates.preferences["stse.maxPower"] = 23
    test.wait_for_events()
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed(updates))
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PREF_CLUSTER_ID, PREF_MAX_POWER_ATTR_ID,
        MFG_CODE,
        data_types.SinglePrecisionFloat,
        SinglePrecisionFloat(0, 11, 0.123046875)) })
    updates.preferences["stse.maxPower"] = 1
    test.wait_for_events()
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed(updates))
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PREF_CLUSTER_ID, PREF_MAX_POWER_ATTR_ID,
        MFG_CODE,
        data_types.SinglePrecisionFloat,
        SinglePrecisionFloat(0, 6, 0.5625)) })
  end
)

test.register_coroutine_test(
  "Handle restorePowerState in infochanged",
  function()
    test.socket.environment_update:__queue_receive({ "zigbee",
      { hub_zigbee_id = base64.encode(zigbee_test_utils.mock_hub_eui) } })
    local updates = {
      preferences = {
      }
    }
    updates.preferences["stse.restorePowerState"] = true
    test.wait_for_events()
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed(updates))
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PREF_CLUSTER_ID,
        PREF_RESTORE_STATE_ATTR_ID, MFG_CODE,
        data_types.Boolean,
        true) })
    updates.preferences["stse.restorePowerState"] = false
    test.wait_for_events()
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed(updates))
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PREF_CLUSTER_ID,
        PREF_RESTORE_STATE_ATTR_ID, MFG_CODE,
        data_types.Boolean,
        false) })
  end
)

-- mock_device_version

test.register_coroutine_test(
  "On attribute handled with application version handler",
  function()
    test.socket.zigbee:__queue_receive(
      {
        mock_device_version.id,
        Basic.attributes.ApplicationVersion:build_test_attr_report(mock_device_version, 32)
      }
    )
    mock_device_version:set_field(APPLICATION_VERSION, 32, { persist = true })
    test.wait_for_events()

    test.socket.zigbee:__queue_receive(
      {
        mock_device_version.id,
        OnOff.attributes.OnOff:build_test_attr_report(mock_device_version, true)
      }
    )
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.capability:__expect_send(
      mock_device_version:generate_test_message("main", capabilities.switch.switch.on())
    )
    test.socket.zigbee:__expect_send({
      mock_device_version.id,
      AnalogInput.attributes.PresentValue:read(mock_device_version):to_endpoint(ENDPOINT_POWER_METER)
    })
    test.socket.zigbee:__expect_send({
      mock_device_version.id,
      AnalogInput.attributes.PresentValue:read(mock_device_version):to_endpoint(ENDPOINT_ENERGY_METER)
    })
  end
)

test.register_coroutine_test(
  "Off attribute handled with application version handler",
  function()
    test.socket.zigbee:__queue_receive(
      {
        mock_device_version.id,
        Basic.attributes.ApplicationVersion:build_test_attr_report(mock_device_version, 32)
      }
    )
    mock_device_version:set_field(APPLICATION_VERSION, 32, { persist = true })
    test.wait_for_events()

    test.socket.zigbee:__queue_receive(
      {
        mock_device_version.id,
        OnOff.attributes.OnOff:build_test_attr_report(mock_device_version, false)
      }
    )
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.capability:__expect_send(
      mock_device_version:generate_test_message("main", capabilities.switch.switch.off())
    )
  end
)

test.register_coroutine_test(
  "Power meter handled with application version handler",
  function()
    test.socket.zigbee:__queue_receive(
      {
        mock_device_version.id,
        Basic.attributes.ApplicationVersion:build_test_attr_report(mock_device_version, 32)
      }
    )
    mock_device_version:set_field(APPLICATION_VERSION, 32, { persist = true })
    test.wait_for_events()

    test.socket.zigbee:__queue_receive({
      mock_device_version.id,
      AnalogInput.attributes.PresentValue:build_test_attr_report(mock_device_version,
        SinglePrecisionFloat(0, 9, 0.953125)):from_endpoint(ENDPOINT_POWER_METER)
    })
    test.socket.capability:__expect_send(
      mock_device_version:generate_test_message("main",
        capabilities.powerMeter.power({ value = 1000.0, unit = "W" }))
    )
  end
)

test.register_coroutine_test(
  "Energy meter handled with application version handler",
  function()
    test.socket.zigbee:__queue_receive(
      {
        mock_device_version.id,
        Basic.attributes.ApplicationVersion:build_test_attr_report(mock_device_version, 32)
      }
    )
    mock_device_version:set_field(APPLICATION_VERSION, 32, { persist = true })
    test.wait_for_events()

    local current_time = os.time() - 60 * 20
    mock_device_version:set_field(LAST_REPORT_TIME, current_time)

    test.socket.zigbee:__queue_receive({
      mock_device_version.id,
      AnalogInput.attributes.PresentValue:build_test_attr_report(mock_device_version,
        SinglePrecisionFloat(0, 9, 0.953125)):from_endpoint(ENDPOINT_ENERGY_METER)
    })
    test.socket.capability:__expect_send(
      mock_device_version:generate_test_message("main",
        capabilities.energyMeter.energy({ value = 1000000.0, unit = "Wh" }))
    )
    test.socket.capability:__expect_send(
      mock_device_version:generate_test_message("main",
        capabilities.powerConsumptionReport.powerConsumption({ deltaEnergy = 0.0, energy = 1000000.0 }))
    )
  end
)

test.run_registered_tests()
