-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local clusters = require "st.zigbee.zcl.clusters"
local BasicCluster = clusters.Basic
local OnOffCluster = clusters.OnOff
local t_utils = require "integration_test.utils"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"

local profile = t_utils.get_profile_definition("basic-switch.yml")

local mock_device = test.mock_device.build_test_zigbee_device({
  label = "Zigbee Switch",
  profile = profile,
  zigbee_endpoints = {
    [1] = {
      id = 1,
      manufacturer = "_TZ123fas",
      server_clusters = { 0x0006 },
    },
    [2] = {
      id = 2,
      manufacturer = "_TZ123fas",
      server_clusters = { 0x0006 },
    },
  },
  fingerprinted_endpoint_id = 0x01
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
                                         OnOffCluster.attributes.OnOff:read(mock_device)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         OnOffCluster.attributes.OnOff:read(mock_device):to_endpoint(0x02)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         OnOffCluster.attributes.OnOff:configure_reporting(mock_device, 0, 300):to_endpoint(1)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         OnOffCluster.attributes.OnOff:configure_reporting(mock_device, 0, 300):to_endpoint(2)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         zigbee_test_utils.build_bind_request(mock_device,
                                                                              zigbee_test_utils.mock_hub_eui,
                                                                              OnOffCluster.ID, 1):to_endpoint(1)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         zigbee_test_utils.build_bind_request(mock_device,
                                                                              zigbee_test_utils.mock_hub_eui,
                                                                              OnOffCluster.ID, 2):to_endpoint(2)
                                       })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_attribute_read(mock_device, BasicCluster.ID, {0x0004, 0x0000, 0x0001, 0x0005, 0x0007, 0xfffe})
    })

      mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    end
)

test.run_registered_tests()
