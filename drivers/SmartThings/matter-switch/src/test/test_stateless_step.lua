-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
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
  clusters.ColorControl.attributes.ColorTemperatureMireds,
  clusters.ColorControl.attributes.ColorTempPhysicalMaxMireds,
  clusters.ColorControl.attributes.ColorTempPhysicalMinMireds,
}

local function test_init()
  local subscribe_request = cluster_subscribe_list[1]:subscribe(mock_device_color_temp)
  for i, cluster in ipairs(cluster_subscribe_list) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(mock_device_color_temp))
    end
  end
  test.socket.matter:__expect_send({mock_device_color_temp.id, subscribe_request})
  test.mock_device.add_test_device(mock_device_color_temp)
end
test.set_test_init_function(test_init)

local fields = require "switch_utils.fields"

test.register_message_test(
  "Color Temperature Step Command Test",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device_color_temp.id,
        { capability = "statelessColorTemperatureStep", component = "main", command = "stepColorTemperatureByPercent", args = { 20 } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device_color_temp.id,
        clusters.ColorControl.server.commands.StepColorTemperature(mock_device_color_temp, 1, clusters.ColorControl.types.StepModeEnum.DOWN, 187, fields.TRANSITION_TIME, fields.COLOR_TEMPERATURE_MIRED_MIN, fields.COLOR_TEMPERATURE_MIRED_MAX, fields.OPTIONS_MASK, fields.IGNORE_COMMAND_IF_OFF)
      },
    },
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device_color_temp.id,
        { capability = "statelessColorTemperatureStep", component = "main", command = "stepColorTemperatureByPercent", args = { 90 } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device_color_temp.id,
        clusters.ColorControl.server.commands.StepColorTemperature(mock_device_color_temp, 1, clusters.ColorControl.types.StepModeEnum.DOWN, 840, fields.TRANSITION_TIME, fields.COLOR_TEMPERATURE_MIRED_MIN, fields.COLOR_TEMPERATURE_MIRED_MAX, fields.OPTIONS_MASK, fields.IGNORE_COMMAND_IF_OFF)
      },
    },
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device_color_temp.id,
        { capability = "statelessColorTemperatureStep", component = "main", command = "stepColorTemperatureByPercent", args = { -50 } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device_color_temp.id,
        clusters.ColorControl.server.commands.StepColorTemperature(mock_device_color_temp, 1, clusters.ColorControl.types.StepModeEnum.UP, 467, fields.TRANSITION_TIME, fields.COLOR_TEMPERATURE_MIRED_MIN, fields.COLOR_TEMPERATURE_MIRED_MAX, fields.OPTIONS_MASK, fields.IGNORE_COMMAND_IF_OFF)
      },
    }
  }
)


test.register_message_test(
  "Level Step Command Test",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device_color_temp.id,
        { capability = "statelessSwitchLevelStep", component = "main", command = "stepLevel", args = { 25 } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device_color_temp.id,
        clusters.LevelControl.server.commands.Step(mock_device_color_temp, 1, clusters.LevelControl.types.StepModeEnum.UP, 64, fields.TRANSITION_TIME, fields.OPTIONS_MASK, fields.IGNORE_COMMAND_IF_OFF)
      },
    },
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device_color_temp.id,
        { capability = "statelessSwitchLevelStep", component = "main", command = "stepLevel", args = { -50 } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device_color_temp.id,
        clusters.LevelControl.server.commands.Step(mock_device_color_temp, 1, clusters.LevelControl.types.StepModeEnum.DOWN, 127, fields.TRANSITION_TIME, fields.OPTIONS_MASK, fields.IGNORE_COMMAND_IF_OFF)
      },
    },
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device_color_temp.id,
        { capability = "statelessSwitchLevelStep", component = "main", command = "stepLevel", args = { 100 } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device_color_temp.id,
        clusters.LevelControl.server.commands.Step(mock_device_color_temp, 1, clusters.LevelControl.types.StepModeEnum.UP, 254, fields.TRANSITION_TIME, fields.OPTIONS_MASK, fields.IGNORE_COMMAND_IF_OFF)
      },
    }
  }
)

test.run_registered_tests()
