-- Copyright © 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"
local clusters = require "st.matter.clusters"

local mock_device_color_temp = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("light-level-colorTemperature.yml"),
  manufacturer_info = {
    vendor_id = 0x0000,
    product_id = 0x0000,
  },
  endpoints = {
    {
      endpoint_id = 1,
      clusters = {
        {cluster_id = clusters.OnOff.ID, cluster_type = "SERVER"},
        {cluster_id = clusters.ColorControl.ID, cluster_type = "BOTH", feature_map = 30},
        {cluster_id = clusters.LevelControl.ID, cluster_type = "SERVER"}
      },
      device_types = {
        {device_type_id = 0x0100, device_type_revision = 1}, -- On/Off Light
        {device_type_id = 0x010C, device_type_revision = 1} -- Color Temperature Light
      }
    }
  }
})

local cluster_subscribe_list = {
  clusters.OnOff.attributes.OnOff,
  clusters.LevelControl.attributes.CurrentLevel,
  clusters.LevelControl.attributes.MaxLevel,
  clusters.LevelControl.attributes.MinLevel,
  clusters.ColorControl.attributes.CurrentHue,
  clusters.ColorControl.attributes.CurrentSaturation,
  clusters.ColorControl.attributes.CurrentX,
  clusters.ColorControl.attributes.CurrentY,
  clusters.ColorControl.attributes.ColorMode,
  clusters.ColorControl.attributes.ColorTemperatureMireds,
  clusters.ColorControl.attributes.ColorTempPhysicalMaxMireds,
  clusters.ColorControl.attributes.ColorTempPhysicalMinMireds,
}

local function set_color_mode(device, endpoint, color_mode)
  test.socket.matter:__queue_receive({
    device.id,
    clusters.ColorControl.attributes.ColorMode:build_test_report_data(
      device, endpoint, color_mode)
  })
  local read_req
  if color_mode == clusters.ColorControl.types.ColorMode.CURRENT_HUE_AND_CURRENT_SATURATION then
    read_req = clusters.ColorControl.attributes.CurrentHue:read()
    read_req:merge(clusters.ColorControl.attributes.CurrentSaturation:read())
  else -- color_mode = clusters.ColorControl.types.ColorMode.CURRENTX_AND_CURRENTY
    read_req = clusters.ColorControl.attributes.CurrentX:read()
    read_req:merge(clusters.ColorControl.attributes.CurrentY:read())
  end
  test.socket.matter:__expect_send({device.id, read_req})
end

local function test_init()
  local subscribe_request = cluster_subscribe_list[1]:subscribe(mock_device_color_temp)
  for i, cluster in ipairs(cluster_subscribe_list) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(mock_device_color_temp))
    end
  end
  test.socket.matter:__expect_send({mock_device_color_temp.id, subscribe_request})
  test.mock_device.add_test_device(mock_device_color_temp)
  set_color_mode(mock_device_color_temp, 1, clusters.ColorControl.types.ColorMode.CURRENT_HUE_AND_CURRENT_SATURATION)
end
test.set_test_init_function(test_init)

test.register_message_test(
  "Color Temperature Step Command Test",
  {
    {
      channel = "capability",
      direction = "receive",
      message = { mock_device_color_temp:generate_test_message("main", capabilities.statelessColorTemperatureStep.stepColorTemperatureByPercent(25)) }
    },
    {
      channel = "matter",
      direction = "send",
      message = mock_device_color_temp:generate_test_message("matter", clusters.ColorControl.server.commands.StepColorTemperature(mock_device_color_temp, 1, clusters.ColorControl.types.StepModeEnum.UP, 1075, 10, 2200, 6500, 0, 0))
    },
    {
      channel = "capability",
      direction = "receive",
      message = { mock_device_color_temp:generate_test_message("main", capabilities.statelessColorTemperatureStep.stepColorTemperatureByPercent(-50)) }
    },
    {
      channel = "matter",
      direction = "send",
      message = mock_device_color_temp:generate_test_message("matter", clusters.ColorControl.server.commands.StepColorTemperature(mock_device_color_temp, 1, clusters.ColorControl.types.StepModeEnum.DOWN, 2150, 10, 2200, 6500, 0, 0))
    },
    {
      channel = "capability",
      direction = "receive",
      message = { mock_device_color_temp:generate_test_message("main", capabilities.statelessColorTemperatureStep.stepColorTemperatureByPercent(100)) }
    },
    {
      channel = "matter",
      direction = "send",
      message = mock_device_color_temp:generate_test_message("matter", clusters.ColorControl.server.commands.StepColorTemperature(mock_device_color_temp, 1, clusters.ColorControl.types.StepModeEnum.UP, 4300, 10, 2200, 6500, 0, 0))
    }
  }
)

test.register_message_test(
  "Level Step Command Test",
  {
    {
      channel = "capability",
      direction = "receive",
      message = { mock_device_color_temp:generate_test_message("main", capabilities.statelessSwitchLevelStep.stepLevel(25)) }
    },
    {
      channel = "matter",
      direction = "send",
      message = mock_device_color_temp:generate_test_message("matter", clusters.LevelControl.server.commands.StepLevel(mock_device_color_temp, 1, clusters.LevelControl.types.StepModeEnum.UP, 1075, 10, 254))
    },
    {
      channel = "capability",
      direction = "receive",
      message = { mock_device_color_temp:generate_test_message("main", capabilities.statelessSwitchLevelStep.stepLevel(-50)) }
    },
    {
      channel = "matter",
      direction = "send",
      message = mock_device_color_temp:generate_test_message("matter", clusters.LevelControl.server.commands.StepLevel(mock_device_color_temp, 1, clusters.LevelControl.types.StepModeEnum.DOWN, 2150, 10, 254))
    },
    {
      channel = "capability",
      direction = "receive",
      message = { mock_device_color_temp:generate_test_message("main", capabilities.statelessSwitchLevelStep.stepLevel(100)) }
    },
    {
      channel = "matter",
      direction = "send",
      message = mock_device_color_temp:generate_test_message("matter", clusters.LevelControl.server.commands.StepLevel(mock_device_color_temp, 1, clusters.LevelControl.types.StepModeEnum.UP, 4300, 10, 254))
    }
  }
)

test.run_registered_tests()
