-- Copyright © 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"
local st_utils = require "st.utils"

local clusters = require "st.matter.clusters"
local TRANSITION_TIME = 0
local OPTIONS_MASK = 0x01
local HANDLE_COMMAND_IF_OFF = 0x01

local mock_device = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("light-color-level-illuminance-motion.yml"),
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
        {device_type_id = 0x0016, device_type_revision = 1}  -- RootNode
      }
    },
    {
      endpoint_id = 1,
      clusters = {
        {
          cluster_id = clusters.OnOff.ID,
          cluster_type = "SERVER",
          cluster_revision = 1,
          feature_map = 0, --u32 bitmap
        },
        {cluster_id = clusters.ColorControl.ID, cluster_type = "BOTH", feature_map = 31},
        {cluster_id = clusters.LevelControl.ID, cluster_type = "SERVER"}
      },
      device_types = {
        {device_type_id = 0x010C, device_type_revision = 1}  -- ColorTemperatureLight
      }
    },
    {
      endpoint_id = 2,
      clusters = {
        {cluster_id = clusters.IlluminanceMeasurement.ID, cluster_type = "SERVER"},
      },
      device_types = {
        {device_type_id = 0x0106, device_type_revision = 1}  -- LightSensor
      }
    },
    {
      endpoint_id = 3,
      clusters = {
        {cluster_id = clusters.OccupancySensing.ID, cluster_type = "SERVER"},
      },
      device_types = {
        {device_type_id = 0x0107, device_type_revision = 1}  -- OccupancySensor
      }
    }
  }
})

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
    clusters.IlluminanceMeasurement.attributes.MeasuredValue,
    clusters.OccupancySensing.attributes.Occupancy
  }
  local subscribe_request = cluster_subscribe_list[1]:subscribe(mock_device)
  for i, cluster in ipairs(cluster_subscribe_list) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(mock_device))
    end
  end
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})
  test.mock_device.add_test_device(mock_device)
  set_color_mode(mock_device, 1, clusters.ColorControl.types.ColorMode.CURRENT_HUE_AND_CURRENT_SATURATION)
end
test.set_test_init_function(test_init)

local function test_init_x_y_color_mode()
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
    clusters.IlluminanceMeasurement.attributes.MeasuredValue,
    clusters.OccupancySensing.attributes.Occupancy
  }
  local subscribe_request = cluster_subscribe_list[1]:subscribe(mock_device)
  for i, cluster in ipairs(cluster_subscribe_list) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(mock_device))
    end
  end
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})
  test.mock_device.add_test_device(mock_device)
  set_color_mode(mock_device, 1, clusters.ColorControl.types.ColorMode.CURRENTX_AND_CURRENTY)
end

test.register_message_test(
	"On command should send the appropriate commands",
	{
		{
			channel = "capability",
			direction = "receive",
			message = {
				mock_device.id,
				{ capability = "switch", component = "main", command = "on", args = { } }
			}
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
			channel = "matter",
			direction = "send",
			message = {
				mock_device.id,
				clusters.OnOff.server.commands.On(mock_device, 1)
			}
		}
	}
)

test.register_message_test(
  "Off command should send the appropriate commands",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "switch", component = "main", command = "off", args = { } }
      }
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
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.OnOff.server.commands.Off(mock_device, 1)
      }
    }
  }
)

test.register_message_test(
	"Set level command should send the appropriate commands",
	{
		{
			channel = "capability",
			direction = "receive",
			message = {
				mock_device.id,
				{ capability = "switchLevel", component = "main", command = "setLevel", args = {20,20} }
			}
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
			channel = "matter",
			direction = "send",
			message = {
				mock_device.id,
				clusters.LevelControl.server.commands.MoveToLevelWithOnOff(mock_device, 1, st_utils.round(20/100.0 * 254), 20, 0 ,0)
			}
		},
		{
			channel = "matter",
			direction = "receive",
			message = {
				mock_device.id,
				clusters.LevelControl.server.commands.MoveToLevelWithOnOff:build_test_command_response(mock_device, 1)
			}
		},
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.LevelControl.attributes.CurrentLevel:build_test_report_data(mock_device, 1, 50)
      }
    },
		{
			channel = "capability",
			direction = "send",
			message = mock_device:generate_test_message("main", capabilities.switchLevel.level(20))
		},
    {
      channel = "devices",
      direction = "send",
      message = {
        "register_native_capability_attr_handler",
        { device_uuid = mock_device.id, capability_id = "switchLevel", capability_attr_id = "level" }
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.OnOff.attributes.OnOff:build_test_report_data(mock_device, 1, true)
      }
    },
		{
			channel = "capability",
			direction = "send",
			message = mock_device:generate_test_message("main", capabilities.switch.switch.on())
		},
    {
      channel = "devices",
      direction = "send",
      message = {
        "register_native_capability_attr_handler",
        { device_uuid = mock_device.id, capability_id = "switch", capability_attr_id = "switch" }
      }
    },
	}
)

test.register_message_test(
	"Current level reports should generate appropriate events",
	{
		{
			channel = "matter",
			direction = "receive",
			message = {
				mock_device.id,
				clusters.LevelControl.server.attributes.CurrentLevel:build_test_report_data(mock_device, 1, 50)
			}
		},
		{
			channel = "capability",
			direction = "send",
			message = mock_device:generate_test_message("main", capabilities.switchLevel.level(math.floor((50 / 254.0 * 100) + 0.5)))
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

local hue = math.floor((50 * 0xFE) / 100.0 + 0.5)
local sat = math.floor((50 * 0xFE) / 100.0 + 0.5)

test.register_message_test(
  "Set color command should send huesat commands when supported",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.ColorControl.attributes.ColorCapabilities:build_test_report_data(mock_device, 1, 0x01)
      }
    },
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "colorControl", component = "main", command = "setColor", args = { { hue = 50, saturation = 50 } } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.ColorControl.server.commands.MoveToHueAndSaturation(mock_device, 1, hue, sat, TRANSITION_TIME, OPTIONS_MASK, HANDLE_COMMAND_IF_OFF)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.ColorControl.server.commands.MoveToHueAndSaturation:build_test_command_response(mock_device, 1)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.ColorControl.attributes.CurrentHue:build_test_report_data(mock_device, 1, hue)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.colorControl.hue(50))
    },
    {
      channel = "devices",
      direction = "send",
      message = {
        "register_native_capability_attr_handler",
        { device_uuid = mock_device.id, capability_id = "colorControl", capability_attr_id = "hue" }
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.ColorControl.attributes.CurrentSaturation:build_test_report_data(mock_device, 1, sat)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.colorControl.saturation(50))
    },
    {
      channel = "devices",
      direction = "send",
      message = {
        "register_native_capability_attr_handler",
        { device_uuid = mock_device.id, capability_id = "colorControl", capability_attr_id = "saturation" }
      }
    },
  }
)

test.register_message_test(
  "Set Hue command should send MoveToHue",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "colorControl", component = "main", command = "setHue", args = { 50 } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.ColorControl.server.commands.MoveToHue(mock_device, 1, hue, 0, TRANSITION_TIME, OPTIONS_MASK, HANDLE_COMMAND_IF_OFF)
      }
    },
  }
)

test.register_message_test(
  "Set Saturation command should send MoveToSaturation",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "colorControl", component = "main", command = "setSaturation", args = { 50 } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.ColorControl.server.commands.MoveToSaturation(mock_device, 1, sat, TRANSITION_TIME, OPTIONS_MASK, HANDLE_COMMAND_IF_OFF)
      }
    },
  }
)

test.register_message_test(
  "Set color temperature should send the appropriate commands",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "colorTemperature", component = "main", command = "setColorTemperature", args = {1800} }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.ColorControl.server.commands.MoveToColorTemperature(mock_device, 1, 556, TRANSITION_TIME, OPTIONS_MASK, HANDLE_COMMAND_IF_OFF)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.ColorControl.server.commands.MoveToColorTemperature:build_test_command_response(mock_device, 1)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.ColorControl.attributes.ColorTemperatureMireds:build_test_report_data(mock_device, 1, 556)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.colorTemperature.colorTemperature(1800))
    },
  }
)

test.register_coroutine_test(
  "X and Y color values should report hue and saturation once both have been received",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        clusters.ColorControl.attributes.CurrentX:build_test_report_data(mock_device, 1, 15091)
      }
    )
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        clusters.ColorControl.attributes.CurrentY:build_test_report_data(mock_device, 1, 21547)
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.colorControl.hue(50)
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.colorControl.saturation(72)
      )
    )
  end,
  { test_init = test_init_x_y_color_mode }
)

test.register_coroutine_test(
  "X and Y color values have 0 value",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        clusters.ColorControl.attributes.CurrentX:build_test_report_data(mock_device, 1, 0)
      }
    )
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        clusters.ColorControl.attributes.CurrentY:build_test_report_data(mock_device, 1, 0)
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.colorControl.hue(33)
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.colorControl.saturation(100)
      )
    )
  end,
  { test_init = test_init_x_y_color_mode }
)

test.register_coroutine_test(
  "Y and X color values should report hue and saturation once both have been received",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        clusters.ColorControl.attributes.CurrentY:build_test_report_data(mock_device, 1, 21547)
      }
    )
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        clusters.ColorControl.attributes.CurrentX:build_test_report_data(mock_device, 1, 15091)
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.colorControl.hue(50)
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.colorControl.saturation(72)
      )
    )
  end,
  { test_init = test_init_x_y_color_mode }
)

test.register_message_test(
  "Do not report when receiving a color temperature of 0 mireds",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.ColorControl.attributes.ColorTemperatureMireds:build_test_report_data(mock_device, 1, 0)
      }
    }
  }
)

test.register_message_test(
  "Illuminance reports should generate correct messages",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.IlluminanceMeasurement.server.attributes.MeasuredValue:build_test_report_data(mock_device, 2, 21370)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.illuminanceMeasurement.illuminance({ value = 137 }))
    }
  }
)

test.register_message_test(
  "Occupancy reports should generate correct messages",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.OccupancySensing.attributes.Occupancy:build_test_report_data(mock_device, 3, 1)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.motionSensor.motion.active())
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.OccupancySensing.attributes.Occupancy:build_test_report_data(mock_device, 3, 0)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.motionSensor.motion.inactive())
    }
  }
)

test.run_registered_tests()
