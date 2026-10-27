-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local version = require "version"
local clusters = require "st.zigbee.zcl.clusters"
local BasicCluster = clusters.Basic
local OnOffCluster = clusters.OnOff
local t_utils = require "integration_test.utils"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local capabilities = require "st.capabilities"

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
local mock_child = test.mock_device.build_test_child_device({
  profile = profile,
  parent_device_id = mock_device.id,
  parent_assigned_child_key = "02",
  label = "Generic Tuya second endpoint",
})

zigbee_test_utils.prepare_zigbee_env_info()

local function test_init()
  mock_device:set_field("_configuration_version", 1, {persist = true})
  test.mock_device.add_test_device(mock_device)
  mock_child:set_field("_configuration_version", 1, {persist = true})
  test.mock_device.add_test_device(mock_child)
end

test.set_test_init_function(test_init)

test.register_coroutine_test("Other Tuya switches retain their generic lifecycle handler", function()
  local driver = test.driver_wrapper.driver_under_test
  local tuya_name = version.api >= 16 and "tuya-multi" or require("tuya-multi").NAME
  local dispatchers = driver.lifecycle_dispatcher:find_child_dispatchers(driver, mock_device, "doConfigure")
  assert(#dispatchers == 1 and dispatchers[1].name == tuya_name)
  assert(#dispatchers[1]:find_child_dispatchers(driver, mock_device, "doConfigure") == 0,
    "Generic Tuya devices must not enter the KES606 sub-driver")
  assert(not require("tuya-multi.zemismart-kes606.can_handle")({}, driver, mock_device))
end)

test.register_message_test("Other Tuya switches retain standard switch commands and reports", {
  { channel = "capability", direction = "receive", message = {
    mock_device.id, { capability = "switch", component = "main", command = "on", args = {} }
  } },
  { channel = "zigbee", direction = "send", message = {
    mock_device.id, OnOffCluster.server.commands.On(mock_device)
  } },
  { channel = "devices", direction = "send", message = {
    "register_native_capability_cmd_handler",
    { device_uuid = mock_device.id, capability_id = "switch", capability_cmd_id = "on" }
  } },
  { channel = "zigbee", direction = "receive", message = {
    mock_device.id, OnOffCluster.attributes.OnOff:build_test_attr_report(mock_device, true)
  } },
  { channel = "capability", direction = "send", message =
    mock_device:generate_test_message("main", capabilities.switch.switch.on()) },
  { channel = "devices", direction = "send", message = {
    "register_native_capability_attr_handler",
    { device_uuid = mock_device.id, capability_id = "switch", capability_attr_id = "switch" }
  } },
})

test.register_coroutine_test("Generic Tuya children configure through the root without the Tuya magic packet", function()
  local driver = test.driver_wrapper.driver_under_test
  assert(not require("tuya-multi.can_handle")({}, driver, mock_child))
  assert(#driver.lifecycle_dispatcher:find_child_dispatchers(driver, mock_child, "doConfigure") == 0)
  test.socket.zigbee:__expect_send({ mock_device.id,
    OnOffCluster.attributes.OnOff:read(mock_device):to_endpoint(0x02) })
  mock_child:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  test.socket.device_lifecycle:__queue_receive({ mock_child.id, "doConfigure" })
end)

test.register_coroutine_test("Generic Tuya children retain the root driver-switch decision", function()
  local driver = test.driver_wrapper.driver_under_test
  assert(#driver.lifecycle_dispatcher:find_child_dispatchers(driver, mock_child, "driverSwitched") == 0)
  mock_child:expect_metadata_update({ provisioning_state = "NONFUNCTIONAL" })
  test.socket.device_lifecycle:__queue_receive({ mock_child.id, "driverSwitched" })
end)

test.register_coroutine_test("Generic Tuya child commands and reports retain their own endpoint", function()
  mock_child:expect_native_cmd_handler_registration("switch", "on")
  test.socket.zigbee:__expect_send({ mock_device.id,
    OnOffCluster.server.commands.On(mock_device):to_endpoint(0x02) })
  test.socket.capability:__queue_receive({ mock_child.id,
    { capability = "switch", component = "main", command = "on", args = {} } })
  test.wait_for_events()
  mock_device:expect_native_attr_handler_registration("switch", "switch")
  test.socket.capability:__expect_send(mock_child:generate_test_message("main", capabilities.switch.switch.on()))
  test.socket.zigbee:__queue_receive({ mock_device.id,
    OnOffCluster.attributes.OnOff:build_test_attr_report(mock_device, true):from_endpoint(0x02) })
end)

for _, endpoint_ids in ipairs({ { 1, 4 }, { 1 } }) do
  local endpoints = {}
  for _, ep in ipairs(endpoint_ids) do
    endpoints[ep] = { id = ep, manufacturer = "_TZ123fas", server_clusters = { 0x0006 } }
  end
  local sample = test.mock_device.build_test_zigbee_device({
    profile = profile, fingerprinted_endpoint_id = 1, zigbee_endpoints = endpoints,
  })
  local is_multi = #endpoint_ids > 1
  local description = is_multi
    and "Sparse Tuya endpoints 1 and 4 both configure through the generic Tuya handler"
    or "Single-endpoint Tuya device retains root configuration without a magic packet"
  test.register_coroutine_test(description, function()
    local driver = test.driver_wrapper.driver_under_test
    local actual = driver:get_device_info(sample.id)
    assert((require("tuya-multi.can_handle")({}, driver, actual)) == is_multi)
    assert(actual.zigbee_endpoints[2] == nil, "The test must preserve the gap in the SDK endpoint map")
    test.socket.zigbee:__set_channel_ordering("relaxed")
    for _, ep in ipairs(endpoint_ids) do
      test.socket.zigbee:__expect_send({ sample.id, OnOffCluster.attributes.OnOff:read(sample):to_endpoint(ep) })
      test.socket.zigbee:__expect_send({ sample.id,
        OnOffCluster.attributes.OnOff:configure_reporting(sample, 0, 300):to_endpoint(ep) })
      test.socket.zigbee:__expect_send({ sample.id,
        zigbee_test_utils.build_bind_request(sample, zigbee_test_utils.mock_hub_eui,
          OnOffCluster.ID, ep):to_endpoint(ep) })
    end
    if is_multi then
      test.socket.zigbee:__expect_send({ sample.id,
        zigbee_test_utils.build_attribute_read(sample, BasicCluster.ID,
          { 0x0004, 0x0000, 0x0001, 0x0005, 0x0007, 0xfffe }) })
    end
    sample:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    test.socket.device_lifecycle:__queue_receive({ sample.id, "doConfigure" })
  end, {
    test_init = function()
      sample:set_field("_configuration_version", 1, {persist = true})
      test.mock_device.add_test_device(sample)
    end,
  })
end

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
    end,
    {
       min_api_version = 14
    }
)

test.run_registered_tests()
