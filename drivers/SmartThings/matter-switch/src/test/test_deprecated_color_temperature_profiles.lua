-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local t_utils = require "integration_test.utils"
local clusters = require "st.matter.clusters"

local fields = require "switch_utils.fields"
local switch_utils = require "switch_utils.utils"

local function build_extended_color_light(vendor_id, product_id)
  return test.mock_device.build_test_matter_device({
    profile = t_utils.get_profile_definition("light-binary.yml"),
    manufacturer_info = {
      vendor_id = vendor_id,
      product_id = product_id,
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
          {cluster_id = clusters.OnOff.ID, cluster_type = "SERVER"},
          {cluster_id = clusters.ColorControl.ID, cluster_type = "BOTH", feature_map = 31},
          {cluster_id = clusters.LevelControl.ID, cluster_type = "SERVER", feature_map = 2}
        },
        device_types = {
          {device_type_id = fields.DEVICE_TYPE_ID.LIGHT.EXTENDED_COLOR, device_type_revision = 1}
        }
      }
    }
  })
end

-- Nanoleaf (0x115A) 0x0035 is in the deprecated_color_temperature_profile_vendor_overrides table
local listed_device = build_extended_color_light(0x115A, 0x0035)
local unlisted_device = build_extended_color_light(0x0000, 0x0000)
-- right vendor, but a product that is not in the table
local unlisted_pid_device = build_extended_color_light(0x115A, 0xFFFF)

local function test_init()
  test.disable_startup_messages()
  test.mock_device.add_test_device(listed_device)
  test.mock_device.add_test_device(unlisted_device)
  test.mock_device.add_test_device(unlisted_pid_device)
end
test.set_test_init_function(test_init)

test.register_coroutine_test(
  "check_deprecated_color_temperature_profile_vendor_overrides matches only listed VID + PID pairs",
  function()
    assert(switch_utils.check_deprecated_color_temperature_profile_vendor_overrides(listed_device),
      "listed VID/PID should match")
    assert(not switch_utils.check_deprecated_color_temperature_profile_vendor_overrides(unlisted_device),
      "unlisted VID should not match")
    assert(not switch_utils.check_deprecated_color_temperature_profile_vendor_overrides(unlisted_pid_device),
      "listed VID with unlisted PID should not match")
  end,
  { min_api_version = 14 }
)

test.register_coroutine_test(
  "doConfigure does not dynamically re-profile a device in the deprecated color temperature override table",
  function()
    listed_device:set_field(fields.profiling_data.BATTERY_SUPPORT, fields.battery_support.NO_BATTERY, { persist = true })
    listed_device:set_field(fields.profiling_data.POWER_TOPOLOGY, false, { persist = true })
    test.socket.device_lifecycle:__queue_receive({ listed_device.id, "doConfigure" })
    test.socket.matter:__expect_send({
      listed_device.id,
      clusters.LevelControl.attributes.Options:write(listed_device, 1, clusters.LevelControl.types.OptionsBitmap.EXECUTE_IF_OFF)
    })
    test.socket.matter:__expect_send({
      listed_device.id,
      clusters.ColorControl.attributes.Options:write(listed_device, 1, clusters.ColorControl.types.OptionsBitmap.EXECUTE_IF_OFF)
    })
    listed_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end,
  { min_api_version = 14 }
)

for name, device in pairs({["unlisted VID"] = unlisted_device, ["unlisted PID"] = unlisted_pid_device}) do
  test.register_coroutine_test(
    "doConfigure dynamically re-profiles a light-color-level device with an " .. name,
    function()
      device:set_field(fields.profiling_data.BATTERY_SUPPORT, fields.battery_support.NO_BATTERY, { persist = true })
      device:set_field(fields.profiling_data.POWER_TOPOLOGY, false, { persist = true })
      test.socket.device_lifecycle:__queue_receive({ device.id, "doConfigure" })
      test.socket.matter:__expect_send({
        device.id,
        clusters.LevelControl.attributes.Options:write(device, 1, clusters.LevelControl.types.OptionsBitmap.EXECUTE_IF_OFF)
      })
      test.socket.matter:__expect_send({
        device.id,
        clusters.ColorControl.attributes.Options:write(device, 1, clusters.ColorControl.types.OptionsBitmap.EXECUTE_IF_OFF)
      })
      device:expect_metadata_update({ profile = "light-color-level" })
      device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    end,
    { min_api_version = 14 }
  )
end

test.run_registered_tests()
