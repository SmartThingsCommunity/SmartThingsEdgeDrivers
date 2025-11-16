-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local clusters = require "st.zigbee.zcl.clusters"
local ElectricalMeasurementCluster = clusters.ElectricalMeasurement
local OnOffCluster = clusters.OnOff
local LevelCluster = clusters.Level
local SimpleMeteringCluster = clusters.SimpleMetering
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"

local mock_device = test.mock_device.build_test_zigbee_device({
  profile = t_utils.get_profile_definition("switch-dimmer-power-energy.yml"),
  zigbee_endpoints = {
    [1] = {
      id = 1,
      manufacturer = "Jasco Products",
      model = "43082",
      server_clusters = { 0x0000, 0x0003, 0x0004, 0x0005, 0x0006, 0x0008, 0x0702, 0x0B04 },
      client_clusters = { 0x000A, 0x0019 }
    }
  }
})

zigbee_test_utils.prepare_zigbee_env_info()

local function test_init()
  mock_device:set_field("_configuration_version", 1, {persist = true})
  test.mock_device.add_test_device(mock_device)
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
    "lifecycle configure event should configure device",
    function ()
      test.socket.zigbee:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle:__queue_receive({mock_device.id, "doConfigure"})
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         zigbee_test_utils.build_bind_request(mock_device,
                                                                              zigbee_test_utils.mock_hub_eui,
                                                                              ElectricalMeasurementCluster.ID)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         zigbee_test_utils.build_bind_request(mock_device,
                                                                              zigbee_test_utils.mock_hub_eui,
                                                                              OnOffCluster.ID)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         zigbee_test_utils.build_bind_request(mock_device,
                                                                              zigbee_test_utils.mock_hub_eui,
                                                                              LevelCluster.ID)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         zigbee_test_utils.build_bind_request(mock_device,
                                                                              zigbee_test_utils.mock_hub_eui,
                                                                              SimpleMeteringCluster.ID)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         ElectricalMeasurementCluster.attributes.ActivePower:read(mock_device)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         ElectricalMeasurementCluster.attributes.ACPowerMultiplier:read(mock_device)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         ElectricalMeasurementCluster.attributes.ACPowerDivisor:read(mock_device)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         OnOffCluster.attributes.OnOff:read(mock_device)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         LevelCluster.attributes.CurrentLevel:read(mock_device)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         SimpleMeteringCluster.attributes.InstantaneousDemand:read(mock_device)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         SimpleMeteringCluster.attributes.CurrentSummationDelivered:read(mock_device)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         SimpleMeteringCluster.attributes.Multiplier:read(mock_device)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         SimpleMeteringCluster.attributes.Divisor:read(mock_device)
                                       })
      test.socket.zigbee:__expect_send({
                                        mock_device.id,
                                        ElectricalMeasurementCluster.attributes.ACPowerMultiplier:configure_reporting(mock_device, 1, 43200, 1)
                                      })
      test.socket.zigbee:__expect_send({
                                        mock_device.id,
                                        ElectricalMeasurementCluster.attributes.ACPowerDivisor:configure_reporting(mock_device, 1, 43200, 1)
                                      })
      test.socket.zigbee:__expect_send({
                                        mock_device.id,
                                        ElectricalMeasurementCluster.attributes.ActivePower:configure_reporting(mock_device, 5, 3600, 5)
                                      })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         OnOffCluster.attributes.OnOff:configure_reporting(mock_device, 0, 300)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         LevelCluster.attributes.CurrentLevel:configure_reporting(mock_device, 1, 3600, 1)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         SimpleMeteringCluster.attributes.InstantaneousDemand:configure_reporting(mock_device, 5, 3600, 5)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         SimpleMeteringCluster.attributes.CurrentSummationDelivered:configure_reporting(mock_device, 5, 3600, 1)
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
      message = { mock_device.id, { capability = "switch", component = "main", command = "on", args = { } } }
    },
    {
      channel = "devices",
      direction = "send",
      message = {
        "register_native_capability_cmd_handler",
        { device_uuid = mock_device.id, capability_id = "switch", capability_cmd_id = "on" }
      }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = { mock_device.id, OnOffCluster.server.commands.On(mock_device) }
    }
  }
)

test.register_message_test(
  "Capability command Off should be handled",
  {
    {
      channel = "capability",
      direction = "receive",
      message = { mock_device.id, { capability = "switch", component = "main", command = "off", args = { } } }
    },
    {
      channel = "devices",
      direction = "send",
      message = {
        "register_native_capability_cmd_handler",
        { device_uuid = mock_device.id, capability_id = "switch", capability_cmd_id = "off" }
      }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = { mock_device.id, OnOffCluster.server.commands.Off(mock_device) }
    }
  }
)

test.register_message_test(
  "Capability command setLevel should be handled",
  {
    {
      channel = "capability",
      direction = "receive",
      message = { mock_device.id, { capability = "switchLevel", component = "main", command = "setLevel", args = { 57, 0 } } }
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
      channel = "zigbee",
      direction = "send",
      message = {
        mock_device.id,
        LevelCluster.server.commands.MoveToLevelWithOnOff(mock_device, math.floor(57 * 254 / 100))
      }
    }
  }
)

test.register_message_test(
  "Handle Switch Level",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = {
        mock_device.id,
        LevelCluster.attributes.CurrentLevel:build_test_attr_report(mock_device, math.floor(57 / 100 * 254))
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switchLevel.level(57))
    },
    {
      channel = "devices",
      direction = "send",
      message = {
        "register_native_capability_attr_handler",
        { device_uuid = mock_device.id, capability_id = "switchLevel", capability_attr_id = "level" }
      }
    },
  }
)

test.register_message_test(
  "Handle Power meter",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, SimpleMeteringCluster.attributes.InstantaneousDemand:build_test_attr_report(mock_device, 0x14D) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.powerMeter.power({ value = 33.3, unit = "W" }))
    }
  }
)

test.register_message_test(
  "Handle Energy meter",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, SimpleMeteringCluster.attributes.CurrentSummationDelivered:build_test_attr_report(mock_device, 0x15B3) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.energyMeter.energy({ value = 0.5555, unit = "kWh" }))
    }
  }
)

test.run_registered_tests()
