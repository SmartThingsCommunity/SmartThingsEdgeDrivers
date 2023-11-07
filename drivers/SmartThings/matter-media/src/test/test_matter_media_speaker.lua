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

local mock_device = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("media-speaker.yml"),
  manufacturer_info = {
    vendor_id = 0x0000,
    product_id = 0x0000,
  },
  endpoints = {
    {
      endpoint_id = 2,
      clusters = {
        {cluster_id = clusters.Basic.ID, cluster_type = "SERVER"},
      },
      device_types = {
        device_type_id = 0x0016, device_type_revision = 1, -- RootNode
      }
    },
    {
      endpoint_id = 10,
      clusters = {
        {
          cluster_id = clusters.OnOff.ID,
          cluster_type = "SERVER",
          cluster_revision = 1,
          feature_map = 0, --u32 bitmap
        },
        {cluster_id = clusters.LevelControl.ID, cluster_type = "SERVER"}
      }
    }
  }
})


local function test_init()
  local cluster_subscribe_list = {
    clusters.OnOff.attributes.OnOff,
    clusters.LevelControl.attributes.CurrentLevel
  }
  test.socket.matter:__set_channel_ordering("relaxed")
  local subscribe_request = cluster_subscribe_list[1]:subscribe(mock_device)
  for i, cluster in ipairs(cluster_subscribe_list) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(mock_device))
    end
  end
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})
  test.mock_device.add_test_device(mock_device)
end
test.set_test_init_function(test_init)

test.register_message_test(
    "Mute and unmute commands should send the appropriate commands",
    {
        {
            channel = "capability",
            direction = "receive",
            message = {
                mock_device.id,
                { capability = "audioMute", component = "main", command = "mute", args = { } }
            }
        },
        {
            channel = "matter",
            direction = "send",
            message = {
                mock_device.id,
                clusters.OnOff.server.commands.Off(mock_device, 10)
            }
        },
        {
            channel = "capability",
            direction = "receive",
            message = {
                mock_device.id,
                { capability = "audioMute", component = "main", command = "unmute", args = { } }
            }
        },
        {
            channel = "matter",
            direction = "send",
            message = {
                mock_device.id,
                clusters.OnOff.server.commands.On(mock_device, 10)
            }
        },
        {
            channel = "matter",
            direction = "receive",
            message = {
                mock_device.id,
                clusters.OnOff.attributes.OnOff:build_test_report_data(mock_device, 10, true)
            }
        },
        {
            channel = "capability",
            direction = "send",
            message = mock_device:generate_test_message("main", capabilities.audioMute.mute.unmuted())
        },
        {
            channel = "matter",
            direction = "receive",
            message = {
                mock_device.id,
                clusters.OnOff.attributes.OnOff:build_test_report_data(mock_device, 10, false)
            }
        },
        {
            channel = "capability",
            direction = "send",
            message = mock_device:generate_test_message("main", capabilities.audioMute.mute.muted())
        }
      }
)

test.register_message_test(
    "Set mute command should send the appropriate commands",
      {
        {
            channel = "capability",
            direction = "receive",
            message = {
                mock_device.id,
                { capability = "audioMute", component = "main", command = "setMute", args = { "muted" } }
            }
        },
        {
            channel = "matter",
            direction = "send",
            message = {
                mock_device.id,
                clusters.OnOff.server.commands.Off(mock_device, 10)
            }
        },
        {
            channel = "capability",
            direction = "receive",
            message = {
                mock_device.id,
                { capability = "audioMute", component = "main", command = "setMute", args = { "unmuted" } }
            }
        },
        {
            channel = "matter",
            direction = "send",
            message = {
                mock_device.id,
                clusters.OnOff.server.commands.On(mock_device, 10)
            }
        }
    }
)

test.register_message_test(
    "Set volume command should send the appropriate commands",
    {
        {
            channel = "capability",
            direction = "receive",
            message = {
                mock_device.id,
                { capability = "audioVolume", component = "main", command = "setVolume", args = { 20 } }
            }
        },
        {
            channel = "matter",
            direction = "send",
            message = {
                mock_device.id,
                clusters.LevelControl.server.commands.MoveToLevelWithOnOff(mock_device, 10, math.floor(20/100.0 * 254), 0, 0, 0)
            }
        },
        {
            channel = "matter",
            direction = "receive",
            message = {
                mock_device.id,
                clusters.LevelControl.server.commands.MoveToLevelWithOnOff:build_test_command_response(mock_device, 10)
            }
        },
        {
            channel = "matter",
            direction = "receive",
            message = {
                mock_device.id,
                clusters.LevelControl.attributes.CurrentLevel:build_test_report_data(mock_device, 10, 50)
            }
        },
        {
            channel = "capability",
            direction = "send",
            message = mock_device:generate_test_message("main", capabilities.audioVolume.volume(20))
        }
    }
)

test.register_message_test(
    "Volume up/down command should send the appropriate commands",
    {
        {
            channel = "capability",
            direction = "receive",
            message = {
                mock_device.id,
                { capability = "audioVolume", component = "main", command = "setVolume", args = { 20 } }
            }
        },
        {
            channel = "matter",
            direction = "send",
            message = {
                mock_device.id,
                clusters.LevelControl.server.commands.MoveToLevelWithOnOff(mock_device, 10, math.floor(20/100.0 * 254), 0, 0, 0)
            }
        },
        {
            channel = "matter",
            direction = "receive",
            message = {
                mock_device.id,
                clusters.LevelControl.server.commands.MoveToLevelWithOnOff:build_test_command_response(mock_device, 10)
            }
        },
        {
            channel = "matter",
            direction = "receive",
            message = {
                mock_device.id,
                clusters.LevelControl.attributes.CurrentLevel:build_test_report_data(mock_device, 10, 50 )
            }
        },
        {
            channel = "capability",
            direction = "send",
            message = mock_device:generate_test_message("main", capabilities.audioVolume.volume(20))
        },
        -- volume up
        {
            channel = "capability",
            direction = "receive",
            message = {
                mock_device.id,
                { capability = "audioVolume", component = "main", command = "volumeUp", args = { } }
            }
        },
        {
            channel = "matter",
            direction = "send",
            message = {
                mock_device.id,
                clusters.LevelControl.server.commands.MoveToLevelWithOnOff(mock_device, 10, math.floor(25/100.0 * 254), 0, 0, 0)
            }
        },
        {
            channel = "matter",
            direction = "receive",
            message = {
                mock_device.id,
                clusters.LevelControl.server.commands.MoveToLevelWithOnOff:build_test_command_response(mock_device, 10)
            }
        },
        {
            channel = "matter",
            direction = "receive",
            message = {
                mock_device.id,
                clusters.LevelControl.attributes.CurrentLevel:build_test_report_data(mock_device, 10, 63 )
            }
        },
        {
            channel = "capability",
            direction = "send",
            message = mock_device:generate_test_message("main", capabilities.audioVolume.volume(25))
        },
        -- volume down
        {
            channel = "capability",
            direction = "receive",
            message = {
                mock_device.id,
                { capability = "audioVolume", component = "main", command = "volumeDown", args = { } }
            }
        },
        {
            channel = "matter",
            direction = "send",
            message = {
                mock_device.id,
                clusters.LevelControl.server.commands.MoveToLevelWithOnOff(mock_device, 10, math.floor(20/100.0 * 254), 0, 0, 0)
            }
        },
        {
            channel = "matter",
            direction = "receive",
            message = {
                mock_device.id,
                clusters.LevelControl.server.commands.MoveToLevelWithOnOff:build_test_command_response(mock_device, 10)
            }
        },
        {
            channel = "matter",
            direction = "receive",
            message = {
                mock_device.id,
                clusters.LevelControl.attributes.CurrentLevel:build_test_report_data(mock_device, 10, 50 )
            }
        },
        {
            channel = "capability",
            direction = "send",
            message = mock_device:generate_test_message("main", capabilities.audioVolume.volume(20))
        },
    }
)

local function refresh_commands(dev)
  local req = clusters.OnOff.attributes.OnOff:read(dev)
  req:merge(clusters.LevelControl.attributes.CurrentLevel:read(dev))
  return req
end

test.register_message_test(
    "Handle received refresh.",
    {
      {
        channel = "capability",
        direction = "receive",
        message = {
          mock_device.id,
          { capability = "refresh", component = "main", command = "refresh", args = { } }
        }
      },
      {
        channel = "matter",
        direction = "send",
        message = {
          mock_device.id,
          refresh_commands(mock_device)
        }
      },
    }
)

test.run_registered_tests()
