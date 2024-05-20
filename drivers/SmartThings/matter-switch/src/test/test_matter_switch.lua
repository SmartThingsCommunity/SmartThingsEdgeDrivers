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

local test = require "integration_test"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"

local clusters = require "st.matter.clusters"
local TRANSITION_TIME = 0
local OPTIONS_MASK = 0x01
local OPTIONS_OVERRIDE = 0x01

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

local cluster_subscribe_list = {
  clusters.OnOff.attributes.OnOff,
  clusters.LevelControl.attributes.CurrentLevel,
  clusters.LevelControl.attributes.MaxLevel,
  clusters.LevelControl.attributes.MinLevel,
  clusters.ColorControl.attributes.CurrentHue,
  clusters.ColorControl.attributes.CurrentSaturation,
  clusters.ColorControl.attributes.CurrentX,
  clusters.ColorControl.attributes.CurrentY,
  clusters.ColorControl.attributes.ColorTemperatureMireds,
  clusters.ColorControl.attributes.ColorTempPhysicalMaxMireds,
  clusters.ColorControl.attributes.ColorTempPhysicalMinMireds,
}

local function test_init()
  test.socket.matter:__set_channel_ordering("relaxed")
  local subscribe_request = cluster_subscribe_list[1]:subscribe(mock_device)
  for i, cluster in ipairs(cluster_subscribe_list) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(mock_device))
    end
  end
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})
  test.mock_device.add_test_device(mock_device)

  subscribe_request = cluster_subscribe_list[1]:subscribe(mock_device_no_hue_sat)
  for i, cluster in ipairs(cluster_subscribe_list) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(mock_device_no_hue_sat))
    end
  end
  test.socket.matter:__expect_send({mock_device_no_hue_sat.id, subscribe_request})
  test.mock_device.add_test_device(mock_device_no_hue_sat)
end
test.set_test_init_function(test_init)

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
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.LevelControl.server.commands.MoveToLevelWithOnOff(mock_device, 1, math.floor(20/100.0 * 254), 20, 0 ,0)
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
    }
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
  }
)

test.register_message_test(
  "Set color command should send the appropriate commands",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device_no_hue_sat.id,
        { capability = "colorControl", component = "main", command = "setColor", args = { { hue = 50, saturation = 72 } } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device_no_hue_sat.id,
        clusters.ColorControl.server.commands.MoveToColor(mock_device_no_hue_sat, 1, 15182, 21547, TRANSITION_TIME, OPTIONS_MASK, OPTIONS_OVERRIDE)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device_no_hue_sat.id,
        clusters.ColorControl.server.commands.MoveToColor:build_test_command_response(mock_device_no_hue_sat, 1)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device_no_hue_sat.id,
        clusters.ColorControl.attributes.CurrentX:build_test_report_data(mock_device, 1, 15091)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device_no_hue_sat.id,
        clusters.ColorControl.attributes.CurrentY:build_test_report_data(mock_device, 1, 21547)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device_no_hue_sat:generate_test_message("main", capabilities.colorControl.hue(50))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device_no_hue_sat:generate_test_message("main", capabilities.colorControl.saturation(72))
    }
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
        clusters.ColorControl.server.commands.MoveToHueAndSaturation(mock_device, 1, hue, sat, TRANSITION_TIME, OPTIONS_MASK, OPTIONS_OVERRIDE)
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
    }
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
        clusters.ColorControl.server.commands.MoveToHue(mock_device, 1, hue, 0, TRANSITION_TIME, OPTIONS_MASK, OPTIONS_OVERRIDE)
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
        clusters.ColorControl.server.commands.MoveToSaturation(mock_device, 1, sat, TRANSITION_TIME, OPTIONS_MASK, OPTIONS_OVERRIDE)
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
        clusters.ColorControl.server.commands.MoveToColorTemperature(mock_device, 1, 556, TRANSITION_TIME, OPTIONS_MASK, OPTIONS_OVERRIDE)
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

test.register_message_test(
  "X and Y color values should report hue and saturation once both have been received",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.ColorControl.attributes.CurrentX:build_test_report_data(mock_device, 1, 15091)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.ColorControl.attributes.CurrentY:build_test_report_data(mock_device, 1, 21547)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.colorControl.hue(50))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.colorControl.saturation(72))
    }
  }
)

test.register_message_test(
  "X and Y color values have 0 value",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.ColorControl.attributes.CurrentX:build_test_report_data(mock_device, 1, 0)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.ColorControl.attributes.CurrentY:build_test_report_data(mock_device, 1, 0)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.colorControl.hue(33))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.colorControl.saturation(100))
    }
  }
)


test.register_message_test(
  "Y and X color values should report hue and saturation once both have been received",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.ColorControl.attributes.CurrentY:build_test_report_data(mock_device, 1, 21547)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.ColorControl.attributes.CurrentX:build_test_report_data(mock_device, 1, 15091)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.colorControl.hue(50))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.colorControl.saturation(72))
    }
  }
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

test.run_registered_tests()
