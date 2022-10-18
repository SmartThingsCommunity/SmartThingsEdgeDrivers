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
  profile = t_utils.get_profile_definition("media-video-player.yml"),
  manufacturer_info = {
    vendor_id = 0x0000,
    product_id = 0x0000,
  },
  endpoints = {
    {
      endpoint_id = 1,
      clusters = {
        {
          cluster_id = clusters.OnOff.ID,
          cluster_type = "SERVER",
          cluster_revision = 1,
          feature_map = 0, --u32 bitmap
          attributes = nil, -- attribute id list
          server_commands = nil, --server cmd id list
          client_commands = nil, --client cmd id list
          events = nil, --event id list
        },
        {cluster_id = clusters.LevelControl.ID, cluster_type = "SERVER"},
        {cluster_id = clusters.MediaPlayback.ID, cluster_type = "SERVER"},
        {cluster_id = clusters.KeypadInput.ID, cluster_type = "SERVER"}
      }
    }
  }
})


local function test_init()
  local cluster_subscribe_list = {
    clusters.OnOff.attributes.OnOff,
    clusters.MediaPlayback.attributes.CurrentState
  }
  test.socket.matter:__set_channel_ordering("relaxed")
  local subscribe_request = cluster_subscribe_list[1]:subscribe(mock_device)
  for i, cluster in ipairs(cluster_subscribe_list) do
    print(i)
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(mock_device))
    end
    print(subscribe_request)
  end
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})
  test.mock_device.add_test_device(mock_device)
end
test.set_test_init_function(test_init)

test.register_message_test(
  "On and off command should send the appropriate commands",
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
    },
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
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
          mock_device.id,
          clusters.OnOff.server.commands.Off:build_test_command_response(mock_device, 1)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
          mock_device.id,
          clusters.OnOff.attributes.OnOff:build_test_report_data(mock_device, 1, false )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switch.switch.off())
    },
  }
)

test.register_message_test(
  "Play command should send the appropriate commands",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
          mock_device.id,
          { capability = "mediaPlayback", component = "main", command = "play", args = { } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
          mock_device.id,
          clusters.MediaPlayback.server.commands.Play(mock_device, 1)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
          mock_device.id,
          clusters.MediaPlayback.attributes.CurrentState:build_test_report_data(mock_device, 1, clusters.MediaPlayback.attributes.CurrentState.PLAYING )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.mediaPlayback.playbackStatus.playing())
    },
  }
)

test.register_message_test(
  "Pause command should send the appropriate commands",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
          mock_device.id,
          { capability = "mediaPlayback", component = "main", command = "pause", args = { } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
          mock_device.id,
          clusters.MediaPlayback.server.commands.Pause(mock_device, 1)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
          mock_device.id,
          clusters.MediaPlayback.attributes.CurrentState:build_test_report_data(mock_device, 1, clusters.MediaPlayback.attributes.CurrentState.PAUSED )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.mediaPlayback.playbackStatus.paused())
    },
  }
)

test.register_message_test(
  "Stop command should send the appropriate commands",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
          mock_device.id,
          { capability = "mediaPlayback", component = "main", command = "stop", args = { } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
          mock_device.id,
          clusters.MediaPlayback.server.commands.StopPlayback(mock_device, 1)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
          mock_device.id,
          clusters.MediaPlayback.attributes.CurrentState:build_test_report_data(mock_device, 1, clusters.MediaPlayback.attributes.CurrentState.NOT_PLAYING )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.mediaPlayback.playbackStatus.stopped())
    },
  }
)

test.register_message_test(
  "Rewind and fast forward commands should send the appropriate commands",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
          mock_device.id,
          { capability = "mediaPlayback", component = "main", command = "rewind", args = { } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
          mock_device.id,
          clusters.MediaPlayback.server.commands.Rewind(mock_device, 1)
      }
    },
    {
      channel = "capability",
      direction = "receive",
      message = {
          mock_device.id,
          { capability = "mediaPlayback", component = "main", command = "fastForward", args = { } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
          mock_device.id,
          clusters.MediaPlayback.server.commands.FastForward(mock_device, 1)
      }
    },
  }
)

test.register_message_test(
  "Track control commands should send the appropriate commands",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
          mock_device.id,
          { capability = "mediaTrackControl", component = "main", command = "previousTrack", args = { } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
          mock_device.id,
          clusters.MediaPlayback.server.commands.Previous(mock_device, 1)
      }
    },
    {
      channel = "capability",
      direction = "receive",
      message = {
          mock_device.id,
          { capability = "mediaTrackControl", component = "main", command = "nextTrack", args = { } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
          mock_device.id,
          clusters.MediaPlayback.server.commands.Next(mock_device, 1)
      }
    },
  }
)

test.register_message_test(
  "Keypad commands should send the appropriate commands",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
          mock_device.id,
          { capability = "keypadInput", component = "main", command = "sendKey", args = { "UP" } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
          mock_device.id,
          clusters.KeypadInput.server.commands.SendKey(mock_device, 1, clusters.KeypadInput.types.CecKeyCode.UP)
      }
    },
    {
      channel = "capability",
      direction = "receive",
      message = {
          mock_device.id,
          { capability = "keypadInput", component = "main", command = "sendKey", args = { "DOWN" } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
          mock_device.id,
          clusters.KeypadInput.server.commands.SendKey(mock_device, 1, clusters.KeypadInput.types.CecKeyCode.DOWN)
      }
    },
    {
      channel = "capability",
      direction = "receive",
      message = {
          mock_device.id,
          { capability = "keypadInput", component = "main", command = "sendKey", args = { "LEFT" } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
          mock_device.id,
          clusters.KeypadInput.server.commands.SendKey(mock_device, 1, clusters.KeypadInput.types.CecKeyCode.LEFT)
      }
    },
    {
      channel = "capability",
      direction = "receive",
      message = {
          mock_device.id,
          { capability = "keypadInput", component = "main", command = "sendKey", args = { "RIGHT" } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
          mock_device.id,
          clusters.KeypadInput.server.commands.SendKey(mock_device, 1, clusters.KeypadInput.types.CecKeyCode.RIGHT)
      }
    },
    {
      channel = "capability",
      direction = "receive",
      message = {
          mock_device.id,
          { capability = "keypadInput", component = "main", command = "sendKey", args = { "SELECT" } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
          mock_device.id,
          clusters.KeypadInput.server.commands.SendKey(mock_device, 1, clusters.KeypadInput.types.CecKeyCode.SELECT)
      }
    },
    {
      channel = "capability",
      direction = "receive",
      message = {
          mock_device.id,
          { capability = "keypadInput", component = "main", command = "sendKey", args = { "NUMBER0" } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
          mock_device.id,
          clusters.KeypadInput.server.commands.SendKey(mock_device, 1, clusters.KeypadInput.types.CecKeyCode.NUMBER0_OR_NUMBER10)
      }
    },
    {
      channel = "capability",
      direction = "receive",
      message = {
          mock_device.id,
          { capability = "keypadInput", component = "main", command = "sendKey", args = { "NUMBER1" } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
          mock_device.id,
          clusters.KeypadInput.server.commands.SendKey(mock_device, 1, clusters.KeypadInput.types.CecKeyCode.NUMBERS1)
      }
    },
  }
)


test.run_registered_tests()
