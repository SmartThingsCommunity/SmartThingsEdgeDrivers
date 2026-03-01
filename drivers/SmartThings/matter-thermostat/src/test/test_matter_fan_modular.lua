-- Copyright © 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local im = require "st.matter.interaction_model"
local t_utils = require "integration_test.utils"
local test = require "integration_test"

local mock_device = test.mock_device.build_test_matter_device({
    profile = t_utils.get_profile_definition("fan-modular.yml"),
    manufacturer_info = {
      vendor_id = 0x0000,
      product_id = 0x0000,
    },
    endpoints = {
      {
        endpoint_id = 0,
        clusters = {
          {cluster_id = clusters.Basic.ID, cluster_type = "SERVER"}
        },
        device_types = {
          {device_type_id = 0x0016, device_type_revision = 1} -- RootNode
        }
      },
      {
        endpoint_id = 1,
        clusters = {
          {cluster_id = clusters.FanControl.ID, cluster_type = "SERVER", feature_map = 15},
          {cluster_id = clusters.OnOff.ID, cluster_type = "SERVER"}
        },
        device_types = {
          {device_type_id = 0x002B, device_type_revision = 1} -- Fan
        }
      }
    }
})

local subscribe_request

local function read_req_on_added(device)
  local attributes = {
    clusters.Thermostat.attributes.ControlSequenceOfOperation,
    clusters.FanControl.attributes.FanModeSequence,
    clusters.FanControl.attributes.WindSupport,
    clusters.FanControl.attributes.RockSupport,
  }
  local read_request = im.InteractionRequest(im.InteractionRequest.RequestType.READ, {})
  for _, clus in ipairs(attributes) do
    read_request:merge(clus:read(device))
  end
  test.socket.matter:__expect_send({ device.id, read_request })
end

local function test_init()
  test.mock_device.add_test_device(mock_device)
  local cluster_subscribe_list = {
    clusters.FanControl.attributes.FanMode,
    clusters.FanControl.attributes.FanModeSequence,
    clusters.FanControl.attributes.PercentCurrent,
  }
  subscribe_request = cluster_subscribe_list[1]:subscribe(mock_device)
  for i, cluster in ipairs(cluster_subscribe_list) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(mock_device))
    end
  end
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
  read_req_on_added(mock_device)
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "init" })
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})
end
test.set_test_init_function(test_init)

local cluster_subscribe_list_configured = {
  clusters.FanControl.attributes.FanMode,
  clusters.FanControl.attributes.FanModeSequence,
  clusters.FanControl.attributes.PercentCurrent,
  clusters.FanControl.attributes.WindSupport,
  clusters.FanControl.attributes.WindSetting,
  clusters.FanControl.attributes.RockSupport,
  clusters.FanControl.attributes.RockSetting,
  clusters.OnOff.attributes.OnOff,
}

local expected_metadata = {
  optional_component_capabilities = { { "main", { "switch", "fanOscillationMode", "windMode", } } },
  profile = "fan-modular"
}

local function update_device_profile()
  mock_device:set_field("__BATTERY_SUPPORT", "NO_BATTERY")
  mock_device:set_field("__THERMOSTAT_RUNNING_STATE_SUPPORT", false)
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
  mock_device:expect_metadata_update(expected_metadata)
  mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  local updated_device_profile = t_utils.get_profile_definition(
    "fan-modular.yml", { enabled_optional_capabilities = expected_metadata.optional_component_capabilities }
  )
  test.wait_for_events()
  test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({ profile = updated_device_profile }))
  for _, attr in ipairs(cluster_subscribe_list_configured) do
    subscribe_request:merge(attr:subscribe(mock_device))
  end
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})
end

test.register_coroutine_test(
  "Test fan speed commands",
  function()
    update_device_profile()
    test.wait_for_events()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        clusters.FanControl.attributes.PercentCurrent:build_test_report_data(mock_device, 1, 10)
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.fanSpeedPercent.percent(10))
    )
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        { capability = "fanSpeedPercent", component = "main", command = "setPercent", args = { 50 } }
      }
    )
    test.socket.matter:__expect_send(
      {
        mock_device.id,
        clusters.FanControl.attributes.PercentSetting:write(mock_device, 1, 50)
      }
    )
  end
)

local supportedFanWind = {
  capabilities.windMode.windMode.noWind.NAME,
  capabilities.windMode.windMode.sleepWind.NAME,
  capabilities.windMode.windMode.naturalWind.NAME
}

test.register_coroutine_test(
  "Test wind mode",
  function()
    update_device_profile()
    test.wait_for_events()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        clusters.FanControl.attributes.WindSupport:build_test_report_data(mock_device, 1, 0x03) -- NoWind, SleepWind (0x0001), and NaturalWind (0x0002)
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.windMode.supportedWindModes(supportedFanWind, { visibility = { displayed = false } })
      )
    )
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        clusters.FanControl.attributes.WindSetting:build_test_report_data(
          mock_device,
          1,
          clusters.FanControl.types.WindSettingMask.SLEEP_WIND
        )
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windMode.windMode.sleepWind())
    )
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        { capability = "windMode", component = "main", command = "setWindMode", args = { "naturalWind" } }
      }
    )
    test.socket.matter:__expect_send(
      {
        mock_device.id,
        clusters.FanControl.attributes.WindSetting:write(
          mock_device,
          1,
          clusters.FanControl.types.WindSettingMask.NATURAL_WIND
        )
      }
    )
  end
)

test.register_coroutine_test(
  "Test fan mode handler",
  function()
    update_device_profile()
    test.wait_for_events()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        clusters.FanControl.attributes.FanMode:build_test_report_data(
          mock_device,
          1,
          clusters.FanControl.attributes.FanMode.OFF
        )
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.fanMode.fanMode("off"))
    )
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        clusters.FanControl.attributes.FanMode:build_test_report_data(
          mock_device,
          1,
          clusters.FanControl.attributes.FanMode.LOW
        )
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.fanMode.fanMode("low"))
    )
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        clusters.FanControl.attributes.FanMode:build_test_report_data(
          mock_device,
          1,
          clusters.FanControl.attributes.FanMode.HIGH
        )
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.fanMode.fanMode("high"))
    )
  end
)

test.register_coroutine_test(
  "Fan Mode sequence reports should generate the appropriate supported modes",
  function()
    update_device_profile()
    test.wait_for_events()
    local FanModeSequence = clusters.FanControl.attributes.FanModeSequence
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        FanModeSequence:build_test_report_data(mock_device, 1, FanModeSequence.OFF_ON)
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.fanMode.supportedFanModes(
          { "off", "high" },
          { visibility = { displayed = false } }
        )
      )
    )
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        FanModeSequence:build_test_report_data(mock_device, 1, FanModeSequence.OFF_LOW_MED_HIGH_AUTO)
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.fanMode.supportedFanModes(
          { "off", "low", "medium", "high", "auto" },
          { visibility = { displayed = false } }
        )
      )
    )
  end
)

test.run_registered_tests()
