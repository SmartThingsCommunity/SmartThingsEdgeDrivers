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
  profile = t_utils.get_profile_definition("switch-color-level.yml"),
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
        {device_type_id = 0x0016, device_type_revision = 1} -- RootNode
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
        {cluster_id = clusters.LevelControl.ID, cluster_type = "SERVER", feature_map = 2}
      },
      device_types = {
        {device_type_id = 0x0100, device_type_revision = 1} -- On/Off Light
      }
    }
  }
})

local mock_device_no_hue_sat = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("switch-color-level.yml"),
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
        {device_type_id = 0x0100, device_type_revision = 1} -- On/Off Light
      }
    }
  }
})

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

local mock_device_extended_color = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("light-color-level.yml"),
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
        {cluster_id = clusters.LevelControl.ID, cluster_type = "SERVER", feature_map = 2}
      },
      device_types = {
        {device_type_id = 0x0100, device_type_revision = 1}, -- On/Off Light
        {device_type_id = 0x0101, device_type_revision = 1}, -- Dimmable Light
        {device_type_id = 0x010C, device_type_revision = 1}, -- Color Temperature Light
        {device_type_id = 0x010D, device_type_revision = 1}, -- Extended Color Light
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
  clusters.ColorControl.attributes.ColorMode,
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
  local subscribe_request = cluster_subscribe_list[1]:subscribe(mock_device)
  for i, cluster in ipairs(cluster_subscribe_list) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(mock_device))
    end
  end
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})

  -- note that since disable_startup_messages is not explicitly called here,
  -- the following subscribe is due to the init event sent by the test framework.
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})
  test.mock_device.add_test_device(mock_device)
  set_color_mode(mock_device, 1, clusters.ColorControl.types.ColorMode.CURRENT_HUE_AND_CURRENT_SATURATION)
end
test.set_test_init_function(test_init)

local function test_init_x_y_color_mode()
  local subscribe_request = cluster_subscribe_list[1]:subscribe(mock_device)
  for i, cluster in ipairs(cluster_subscribe_list) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(mock_device))
    end
  end
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})

  test.socket.matter:__expect_send({mock_device.id, subscribe_request})
  test.mock_device.add_test_device(mock_device)
  set_color_mode(mock_device, 1, clusters.ColorControl.types.ColorMode.CURRENTX_AND_CURRENTY)
end

local function test_init_no_hue_sat()
  local subscribe_request = cluster_subscribe_list[1]:subscribe(mock_device_no_hue_sat)
  for i, cluster in ipairs(cluster_subscribe_list) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(mock_device_no_hue_sat))
    end
  end
  test.socket.device_lifecycle:__queue_receive({ mock_device_no_hue_sat.id, "added" })
  test.socket.matter:__expect_send({mock_device_no_hue_sat.id, subscribe_request})

  test.socket.matter:__expect_send({mock_device_no_hue_sat.id, subscribe_request})
  test.mock_device.add_test_device(mock_device_no_hue_sat)
  set_color_mode(mock_device_no_hue_sat, 1, clusters.ColorControl.types.ColorMode.CURRENTX_AND_CURRENTY)
end


local cluster_subscribe_list_color_temp = {
  clusters.OnOff.attributes.OnOff,
  clusters.LevelControl.attributes.CurrentLevel,
  clusters.LevelControl.attributes.MaxLevel,
  clusters.LevelControl.attributes.MinLevel,
  clusters.ColorControl.attributes.ColorTemperatureMireds,
  clusters.ColorControl.attributes.ColorTempPhysicalMaxMireds,
  clusters.ColorControl.attributes.ColorTempPhysicalMinMireds
}

local function test_init_color_temp()
  test.mock_device.add_test_device(mock_device_color_temp)
  local subscribe_request = cluster_subscribe_list_color_temp[1]:subscribe(mock_device_color_temp)
  for i, cluster in ipairs(cluster_subscribe_list_color_temp) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(mock_device_color_temp))
    end
  end

  test.socket.device_lifecycle:__queue_receive({ mock_device_color_temp.id, "added" })
  test.socket.matter:__expect_send({mock_device_color_temp.id, subscribe_request})

  test.socket.device_lifecycle:__queue_receive({ mock_device_color_temp.id, "init" })
  test.socket.matter:__expect_send({mock_device_color_temp.id, subscribe_request})

  test.socket.device_lifecycle:__queue_receive({ mock_device_color_temp.id, "doConfigure" })
  test.socket.matter:__expect_send({
    mock_device_color_temp.id,
    clusters.LevelControl.attributes.Options:write(mock_device_color_temp, 1, clusters.LevelControl.types.OptionsBitmap.EXECUTE_IF_OFF)
  })
  test.socket.matter:__expect_send({
    mock_device_color_temp.id,
    clusters.ColorControl.attributes.Options:write(mock_device_color_temp, 1, clusters.ColorControl.types.OptionsBitmap.EXECUTE_IF_OFF)
  })
  mock_device_color_temp:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  test.socket.matter:__expect_send({mock_device_color_temp.id, subscribe_request})
end

local function test_init_extended_color()
  test.mock_device.add_test_device(mock_device_extended_color)
  local subscribe_request = cluster_subscribe_list[1]:subscribe(mock_device_extended_color)
  for i, cluster in ipairs(cluster_subscribe_list) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(mock_device_extended_color))
    end
  end
  test.socket.matter:__expect_send({mock_device_extended_color.id, subscribe_request})
  test.socket.device_lifecycle:__queue_receive({ mock_device_extended_color.id, "added" })

  test.socket.device_lifecycle:__queue_receive({ mock_device_extended_color.id, "init" })
  test.socket.matter:__expect_send({mock_device_extended_color.id, subscribe_request})

  test.socket.device_lifecycle:__queue_receive({ mock_device_extended_color.id, "doConfigure" })
  test.socket.matter:__expect_send({
    mock_device_extended_color.id,
    clusters.LevelControl.attributes.Options:write(mock_device_extended_color, 1, clusters.LevelControl.types.OptionsBitmap.EXECUTE_IF_OFF)
  })
  test.socket.matter:__expect_send({
    mock_device_extended_color.id,
    clusters.ColorControl.attributes.Options:write(mock_device_extended_color, 1, clusters.ColorControl.types.OptionsBitmap.EXECUTE_IF_OFF)
  })
  mock_device_extended_color:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  test.socket.matter:__expect_send({mock_device_extended_color.id, subscribe_request})
end

test.register_message_test(
  "Test that Color Temperature Light device does not switch profiles",
  {},
  { test_init = test_init_color_temp }
)

test.register_message_test(
  "Test that Extended Color Light device does not switch profiles",
  {},
  { test_init = test_init_extended_color }
)

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
      message = mock_device:generate_test_message("main", capabilities.switchLevel.level(st_utils.round((50 / 254.0 * 100) + 0.5)))
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

test.register_coroutine_test(
  "Set color command should send the appropriate commands", function()
    test.socket.capability:__queue_receive(
      {
        mock_device_no_hue_sat.id,
        { capability = "colorControl", component = "main", command = "setColor", args = { { hue = 50, saturation = 72 } }},
      }
    )
    test.socket.matter:__expect_send(
      {
        mock_device_no_hue_sat.id,
        clusters.ColorControl.server.commands.MoveToColor(mock_device_no_hue_sat, 1, 15182, 21547, TRANSITION_TIME, OPTIONS_MASK, HANDLE_COMMAND_IF_OFF)
      }
    )
    test.socket.matter:__queue_receive(
      {
        mock_device_no_hue_sat.id,
        clusters.ColorControl.server.commands.MoveToColor:build_test_command_response(mock_device_no_hue_sat, 1)
      }
    )
    test.socket.matter:__queue_receive(
      {
        mock_device_no_hue_sat.id,
        clusters.ColorControl.attributes.CurrentX:build_test_report_data(mock_device_no_hue_sat, 1, 15091)
      }
    )
    test.socket.matter:__queue_receive(
      {
        mock_device_no_hue_sat.id,
        clusters.ColorControl.attributes.CurrentY:build_test_report_data(mock_device_no_hue_sat, 1, 21547)
      }
    )
    test.socket.capability:__expect_send(
      mock_device_no_hue_sat:generate_test_message(
        "main", capabilities.colorControl.hue(50)
      )
    )
    test.socket.capability:__expect_send(
      mock_device_no_hue_sat:generate_test_message(
        "main", capabilities.colorControl.saturation(72)
      )
    )
  end,
  { test_init = test_init_no_hue_sat }
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

hue = 0xFE
sat = 0xFE
test.register_message_test(
  "Set color command should clamp invalid huesat values",
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
        { capability = "colorControl", component = "main", command = "setColor", args = { { hue = 110, saturation = 110 } } }
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
      message = mock_device:generate_test_message("main", capabilities.colorControl.hue(100))
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
      message = mock_device:generate_test_message("main", capabilities.colorControl.saturation(100))
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

hue = math.floor((50 * 0xFE) / 100.0 + 0.5)
sat = math.floor((50 * 0xFE) / 100.0 + 0.5)
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
  "Min and max color temperature attributes set capability constraint",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.ColorControl.attributes.ColorTempPhysicalMinMireds:build_test_report_data(mock_device, 1, 153)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.ColorControl.attributes.ColorTempPhysicalMaxMireds:build_test_report_data(mock_device, 1, 555)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.colorTemperature.colorTemperatureRange({minimum = 1800, maximum = 6500}))
    }
  }
)

test.register_message_test(
  "Min and max color temperature attributes set capability constraint using improved temperature conversion rounding",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.ColorControl.attributes.ColorTempPhysicalMinMireds:build_test_report_data(mock_device, 1, 165)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.ColorControl.attributes.ColorTempPhysicalMaxMireds:build_test_report_data(mock_device, 1, 365)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.colorTemperature.colorTemperatureRange({minimum = 2800, maximum = 6000}))
    }
  }
)

test.register_message_test(
  "Device reports mireds outside of supported range, set capability to min/max value in kelvin",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.ColorControl.attributes.ColorTempPhysicalMinMireds:build_test_report_data(mock_device, 1, 165)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.ColorControl.attributes.ColorTempPhysicalMaxMireds:build_test_report_data(mock_device, 1, 365)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.colorTemperature.colorTemperatureRange({minimum = 2800, maximum = 6000}))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.ColorControl.attributes.ColorTemperatureMireds:build_test_report_data(mock_device, 1, 160)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.colorTemperature.colorTemperature(6000))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.ColorControl.attributes.ColorTemperatureMireds:build_test_report_data(mock_device, 1, 370)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.colorTemperature.colorTemperature(2800))
    }
  }
)

test.register_message_test(
  "Capability sets color temp outside of supported range, value sent to device is limited to min/max value in mireds",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.ColorControl.attributes.ColorTempPhysicalMinMireds:build_test_report_data(mock_device, 1, 165)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.ColorControl.attributes.ColorTempPhysicalMaxMireds:build_test_report_data(mock_device, 1, 365)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.colorTemperature.colorTemperatureRange({minimum = 2800, maximum = 6000}))
    },
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "colorTemperature", component = "main", command = "setColorTemperature", args = {6100} }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.ColorControl.server.commands.MoveToColorTemperature(mock_device, 1, 165, TRANSITION_TIME, OPTIONS_MASK, HANDLE_COMMAND_IF_OFF)
      }
    },
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "colorTemperature", component = "main", command = "setColorTemperature", args = {2700} }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.ColorControl.server.commands.MoveToColorTemperature(mock_device, 1, 365, TRANSITION_TIME, OPTIONS_MASK, HANDLE_COMMAND_IF_OFF)
      }
    }
  }
)

test.register_message_test(
  "Min color temperature outside of range, capability not sent",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.ColorControl.attributes.ColorTempPhysicalMinMireds:build_test_report_data(mock_device, 1, 50)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.ColorControl.attributes.ColorTempPhysicalMaxMireds:build_test_report_data(mock_device, 1, 555)
      }
    }
  }
)

test.register_message_test(
  "Max color temperature outside of range, capability not sent",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.ColorControl.attributes.ColorTempPhysicalMinMireds:build_test_report_data(mock_device, 1, 153)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.ColorControl.attributes.ColorTempPhysicalMaxMireds:build_test_report_data(mock_device, 1, 1100)
      }
    }
  }
)

test.register_message_test(
  "Min and max level attributes set capability constraint",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.LevelControl.attributes.MinLevel:build_test_report_data(mock_device, 1, 5)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.LevelControl.attributes.MaxLevel:build_test_report_data(mock_device, 1, 10)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switchLevel.levelRange({minimum = 2, maximum = 4}))
    }
  }
)

test.register_message_test(
  "Min level attribute outside of range for lighting feature device (min level = 1), capability not sent",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.LevelControl.attributes.MinLevel:build_test_report_data(mock_device, 1, 0)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.LevelControl.attributes.MaxLevel:build_test_report_data(mock_device, 1, 10)
      }
    }
  }
)

test.register_coroutine_test(
  "colorControl capability sent based on CurrentHue and CurrentSaturation due to ColorMode",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        clusters.ColorControl.attributes.ColorMode:build_test_report_data(mock_device, 1, clusters.ColorControl.types.ColorMode.CURRENT_HUE_AND_CURRENT_SATURATION)
      }
    )
    local read_hue_sat = clusters.ColorControl.attributes.CurrentHue:read()
    read_hue_sat:merge(clusters.ColorControl.attributes.CurrentSaturation:read())
    test.socket.matter:__expect_send(
      {
        mock_device.id,
        read_hue_sat
      }
    )
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        clusters.ColorControl.attributes.CurrentHue:build_test_report_data(mock_device, 1, 0xFE),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.colorControl.hue(100)
      )
    )
    test.socket.devices:__expect_send(
      {
        "register_native_capability_attr_handler",
        { device_uuid = mock_device.id, capability_id = "colorControl", capability_attr_id = "hue" }
      }
    )
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        clusters.ColorControl.attributes.CurrentSaturation:build_test_report_data(mock_device, 1, 0xFE),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.colorControl.saturation(100)
      )
    )
    test.socket.devices:__expect_send(
      {
        "register_native_capability_attr_handler",
        { device_uuid = mock_device.id, capability_id = "colorControl", capability_attr_id = "saturation" }
      }
    )
  end,
  { test_init = test_init_x_y_color_mode }
)

test.register_coroutine_test(
  "colorControl capability sent based on CurrentX and CurrentY due to ColorMode",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        clusters.ColorControl.attributes.ColorMode:build_test_report_data(mock_device, 1, clusters.ColorControl.types.ColorMode.CURRENTX_AND_CURRENTY)
      }
    )
    local read_x_y = clusters.ColorControl.attributes.CurrentX:read()
    read_x_y:merge(clusters.ColorControl.attributes.CurrentY:read())
    test.socket.matter:__expect_send(
      {
        mock_device.id,
        read_x_y
      }
    )
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
  end
)

test.register_coroutine_test(
  "Refresh necessary attributes",
  function()
    test.socket.capability:__queue_receive(
      {mock_device.id, {capability = "refresh", component = "main", command = "refresh", args = {}}}
    )
    local read_request = cluster_subscribe_list[1]:read(mock_device)
    for i, attr in ipairs(cluster_subscribe_list) do
      if i > 1 then read_request:merge(attr:read(mock_device)) end
    end
    test.socket.matter:__expect_send({mock_device.id, read_request})
    test.wait_for_events()
  end
)

test.run_registered_tests()
