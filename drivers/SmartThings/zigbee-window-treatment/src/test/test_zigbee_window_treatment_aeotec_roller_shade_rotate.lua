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

-- Mock out globals
local test = require "integration_test"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"

local WindowCovering = clusters.WindowCovering
local Alarm = clusters.Alarms
local DeviceTemperatureConfiguration = clusters.DeviceTemperatureConfiguration
local Scenes = clusters.Scenes

local SCENE_ID_BUTTON_EVENT_MAP = {
  { state_name = "pushed",    button_state = capabilities.button.button.pushed },
  { state_name = "double",    button_state = capabilities.button.button.double },
  { state_name = "pushed_3x", button_state = capabilities.button.button.pushed_3x },
  { state_name = "held",      button_state = capabilities.button.button.held },
  { state_name = "up",        button_state = capabilities.button.button.up }
}

local profile = t_utils.get_profile_definition("window-treatment-aeotec-pico.yml")
local profileVenetian = t_utils.get_profile_definition("window-treatment-aeotec-pico-venetian.yml")

local mock_device = test.mock_device.build_test_zigbee_device(
  {
    label = "Aeotec Pico Shutter",
    profile = profile,
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "AEOTEC",
        model = "ZGA003",
        server_clusters = { WindowCovering.ID, Alarm.ID, DeviceTemperatureConfiguration.ID, Scenes.ID },
      }
    },
    fingerprinted_endpoint_id = 0x01
  }
)

local mock_device_venetian = test.mock_device.build_test_zigbee_device(
  {
    profile = profileVenetian,
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "AEOTEC",
        model = "ZGA003",
        server_clusters = { WindowCovering.ID, Alarm.ID, DeviceTemperatureConfiguration.ID, Scenes.ID }
      }
    },
    fingerprinted_endpoint_id = 0x01
  }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device)
  test.mock_device.add_test_device(mock_device_venetian)
  zigbee_test_utils.init_noop_health_check_timer()
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
    "Roller - State transition from closing to partially open",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.zigbee:__queue_receive(
        {
          mock_device.id,
          clusters.WindowCovering.attributes.CurrentPositionLiftPercentage:build_test_attr_report(mock_device, 1)
        }
      )
      test.socket.capability:__expect_send(
          {
            mock_device.id,
            {
              capability_id = "windowShadeLevel", component_id = "main",
              attribute_id = "shadeLevel", state = { value = 1 }
            }
          }
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.windowShade.windowShade.closing())
      )
      test.mock_time.advance_time(2)
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.windowShade.windowShade.partially_open())
      )
      test.wait_for_events()
    end
)

 test.register_coroutine_test(
    "Roller - State transition from closing to opening",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.zigbee:__queue_receive(
        {
          mock_device.id,
          clusters.WindowCovering.attributes.CurrentPositionLiftPercentage:build_test_attr_report(mock_device, 10)
        }
      )
      test.socket.capability:__expect_send(
          {
            mock_device.id,
            {
              capability_id = "windowShadeLevel", component_id = "main",
              attribute_id = "shadeLevel", state = { value = 10 }
            }
          }
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.windowShade.windowShade.closing())
      )
      test.mock_time.advance_time(2)
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.windowShade.windowShade.partially_open())
      )
      test.wait_for_events()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.zigbee:__queue_receive({
        mock_device.id,
        clusters.WindowCovering.attributes.CurrentPositionLiftPercentage:build_test_attr_report(mock_device, 5)
      })
      test.socket.capability:__expect_send({
        mock_device.id,
        {
          capability_id = "windowShadeLevel", component_id = "main",
          attribute_id = "shadeLevel", state = { value = 5 }
        }
      })
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.windowShade.windowShade.opening())
      )
      test.mock_time.advance_time(3)
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.windowShade.windowShade.partially_open())
      )
      test.wait_for_events()
    end
)

test.register_coroutine_test(
  "Roller Venetian - Set shade level to 10%",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.zigbee:__queue_receive(
      {
        mock_device_venetian.id,
        clusters.WindowCovering.attributes.CurrentPositionTiltPercentage:build_test_attr_report(mock_device_venetian, 10)
      }
    )
    test.socket.capability:__expect_send(
      {
        mock_device_venetian.id,
        {
          capability_id = "windowShadeLevel",
          component_id = "venetianBlind",
          attribute_id = "shadeLevel",
          state = { value = 10 }
        }
      }
    )
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "Roller - Handle Window shade close command - 'close' goes to 100",
  function()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {
          capability = "windowShade", component = "main", command = "close", args = {}
        }
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShade.windowShade.opening())
    )
    test.socket.zigbee:__expect_send({
      mock_device.id,
      clusters.WindowCovering.server.commands.GoToLiftPercentage(mock_device, 100)
    })
  end
)

test.register_coroutine_test(
  "Roller Venetian - Handle Window shade close command - 'close' goes to 0",
  function()
    test.socket.capability:__queue_receive(
      {
        mock_device_venetian.id,
        {
          capability = "windowShade", component = "venetianBlind", command = "close", args = {}
        }
      }
    )
    test.socket.capability:__expect_send(
      mock_device_venetian:generate_test_message("venetianBlind", capabilities.windowShade.windowShade.closing())
    )
    test.socket.zigbee:__expect_send({
      mock_device_venetian.id,
      clusters.WindowCovering.server.commands.GoToTiltPercentage(mock_device_venetian, 0):to_endpoint(0x02)
    })
  end
)

test.register_coroutine_test(
  "Roller - Handle Window shade open command - 'open' goes to 0",
  function()
      test.socket.capability:__queue_receive(
          {
            mock_device.id,
        {
          capability = "windowShade", component = "main", command = "open", args = {}
        }
          }
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.windowShade.windowShade.closing())
      )
    test.socket.zigbee:__expect_send({
        mock_device.id,
      clusters.WindowCovering.server.commands.GoToLiftPercentage(mock_device, 0)
      })
    end
)

test.register_coroutine_test(
  "Roller Venetian - Handle Window shade open command - 'open' goes to 100",
  function()
    test.socket.capability:__queue_receive(
      {
        mock_device_venetian.id,
        {
          capability = "windowShade", component = "venetianBlind", command = "open", args = {}
        }
      }
    )
    test.socket.capability:__expect_send(
      mock_device_venetian:generate_test_message("venetianBlind", capabilities.windowShade.windowShade.opening())
    )
    test.socket.zigbee:__expect_send({
      mock_device_venetian.id,
      clusters.WindowCovering.server.commands.GoToTiltPercentage(mock_device_venetian, 100):to_endpoint(0x02)
    })
  end
)

test.register_coroutine_test(
    "Roller - Handle Window shade pause command",
  function()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {
          capability = "windowShade", component = "main", command = "pause", args = {}
        }
      }
    )
    test.socket.zigbee:__expect_send({
      mock_device.id,
      clusters.WindowCovering.attributes.CurrentPositionLiftPercentage:read(mock_device)
    })
  end
)

test.register_coroutine_test(
  "Roller Venetian - Handle Window shade pause command",
  function()
    test.socket.capability:__queue_receive(
      {
        mock_device_venetian.id,
        {
          capability = "windowShade", component = "venetianBlind", command = "pause", args = {}
        }
      }
    )
    test.socket.zigbee:__expect_send({
      mock_device_venetian.id,
      clusters.WindowCovering.attributes.CurrentPositionTiltPercentage:read(mock_device_venetian):to_endpoint(0x02)
    })
  end
)

test.register_message_test(
  "Roller - Handle Window Shade level command",
    {
      {
        channel = "capability",
        direction = "receive",
        message = {
          mock_device.id,
          {
            capability = "windowShadeLevel", component = "main",
            command = "setShadeLevel", args = { 33 }
          }
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = {
          mock_device.id,
          clusters.WindowCovering.server.commands.GoToLiftPercentage(mock_device, 33)
        }
      }
    }
)

test.register_message_test(
  "Roller Venetian - Handle Window Shade level command",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device_venetian.id,
        {
          capability = "windowShadeLevel",
          component = "venetianBlind",
          command = "setShadeLevel",
          args = { 33 }
        }
      }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = {
        mock_device_venetian.id,
        clusters.WindowCovering.server.commands.GoToTiltPercentage(mock_device_venetian, 33):to_endpoint(0x02)
      }
    }
  }
)

test.register_message_test(
  "Roller - Handle Window Shade Preset command",
    {
      {
        channel = "capability",
        direction = "receive",
        message = {
          mock_device.id,
          {
            capability = "windowShadePreset", component = "main",
            command = "presetPosition", args = {}
          }
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = {
          mock_device.id,
          clusters.WindowCovering.server.commands.GoToLiftPercentage(mock_device, 50)
        }
      }
    }
)

test.register_message_test(
  "Roller Venetian - Handle Window Shade Preset command",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device_venetian.id,
        {
          capability = "windowShadePreset",
          component = "venetianBlind",
          command = "presetPosition",
          args = {}
        }
      }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = {
        mock_device_venetian.id,
        clusters.WindowCovering.server.commands.GoToTiltPercentage(mock_device_venetian, 50):to_endpoint(0x02)
      }
    }
  }
)

test.register_coroutine_test(
  "Roller - Refresh necessary attributes",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
    for _, component in pairs(mock_device.profile.components) do
      if component["id"]:match("button(%d)") then
        test.socket.capability:__expect_send(
          mock_device:generate_test_message(component["id"],
            capabilities.button.supportedButtonValues({ "pushed", "double", "pushed_3x", "held", "up" },
              { visibility = { displayed = false } }))
        )
        test.socket.capability:__expect_send(
          mock_device:generate_test_message(component["id"],
            capabilities.button.numberOfButtons({ value = 1 },
              { visibility = { displayed = false } }))
        )
      end
    end
  end
)

test.register_coroutine_test(
  "Roller Venetian - Refresh necessary attributes",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device_venetian.id, "added" })
    for _, component in pairs(mock_device_venetian.profile.components) do
      if component["id"]:match("button(%d)") then
        test.socket.capability:__expect_send(
          mock_device_venetian:generate_test_message(component["id"],
            capabilities.button.supportedButtonValues({ "pushed", "double", "pushed_3x", "held", "up" },
              { visibility = { displayed = false } }))
        )
        test.socket.capability:__expect_send(
          mock_device_venetian:generate_test_message(component["id"],
            capabilities.button.numberOfButtons({ value = 1 },
              { visibility = { displayed = false } }))
        )
      end
    end
  end
)

test.register_coroutine_test(
  "lifecycle configure event should configure device",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
    test.socket.zigbee:__set_channel_ordering("relaxed")

    test.socket.zigbee:__expect_send({
      mock_device.id,
      clusters.WindowCovering.attributes.CurrentPositionLiftPercentage:configure_reporting(mock_device, 0, 600, 1)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device,
        zigbee_test_utils.mock_hub_eui,
        clusters.WindowCovering.ID)
    })

    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device,
        zigbee_test_utils.mock_hub_eui,
        Alarm.ID)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      Alarm.attributes.AlarmCount:configure_reporting(mock_device, 0, 21600, 0)
    })

    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device,
        zigbee_test_utils.mock_hub_eui,
        DeviceTemperatureConfiguration.ID)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      DeviceTemperatureConfiguration.attributes.CurrentTemperature:configure_reporting(mock_device, 1, 600, 10)
    })

    for endpoint = 1, 4 do
      if endpoint <=2 then
        test.socket.zigbee:__expect_send({
          mock_device.id,
          zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, WindowCovering.ID, endpoint)
        })
      else
        test.socket.zigbee:__expect_send({
          mock_device.id,
          zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, Scenes.ID, endpoint)
        })
      end
    end

    for endpoint = 1,2 do
      test.socket.zigbee:__expect_send({
        mock_device.id,
        clusters.WindowCovering.attributes.CurrentPositionLiftPercentage:read(mock_device):to_endpoint(endpoint)
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        clusters.WindowCovering.attributes.CurrentPositionTiltPercentage:read(mock_device):to_endpoint(endpoint)
      })
    end

    test.socket.zigbee:__expect_send({
      mock_device.id,
      clusters.Alarms.attributes.AlarmCount:read(mock_device)
    })

    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)


test.register_coroutine_test(
  "Alarms counter heat handled",
  function()
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      Alarm.client.commands.Alarm.build_test_rx(mock_device, 0x86, 0x0702)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.temperatureAlarm.temperatureAlarm.heat())
    )
  end
)

test.register_coroutine_test(
  "Alarms counter idle handled",
  function()
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      Alarm.client.commands.Alarm.build_test_rx(mock_device, 0x00, 0x0000)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.temperatureAlarm.temperatureAlarm.cleared())
    )
  end
)

test.register_coroutine_test(
  "Temperature Alarm Reset handled",
  function()
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      DeviceTemperatureConfiguration.attributes.CurrentTemperature:build_test_attr_report(mock_device, 70)
    })
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      Alarm.client.commands.Alarm.build_test_rx(mock_device, 0x86, 0x0702)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.temperatureAlarm.temperatureAlarm.heat())
    )

    test.wait_for_events()

    test.socket.zigbee:__queue_receive({
      mock_device.id,
      DeviceTemperatureConfiguration.attributes.CurrentTemperature:build_test_attr_report(mock_device, 65)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      Alarm.server.commands.ResetAllAlarms(mock_device)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      Alarm.attributes.AlarmCount:read(mock_device)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.temperatureAlarm.temperatureAlarm.cleared())
    )
  end
)

for i, button_event in ipairs(SCENE_ID_BUTTON_EVENT_MAP) do
  -- i = scene_id and goes from 0x01 to 0x05
  test.register_message_test(
    "Test Scene Control: Roller - " .. button_event.state_name,
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id,
          zigbee_test_utils.build_custom_command_id(mock_device, Scenes.ID, Scenes.server.commands.RecallScene.ID, 0x0000,
            "\x00\x01" .. string.char(i) .. "\xFF\xFF", 0x04) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("button1",
          button_event.button_state({ state_change = true }))
      },
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id,
          zigbee_test_utils.build_custom_command_id(mock_device, Scenes.ID, Scenes.server.commands.RecallScene.ID, 0x0000,
            "\x00\x01" .. string.char(i) .. "\xFF\xFF", 0x03) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("button2",
          button_event.button_state({ state_change = true }))
      }
    }
  )
end

for i, button_event in ipairs(SCENE_ID_BUTTON_EVENT_MAP) do
  -- i = scene_id and goes from 0x01 to 0x05
  test.register_message_test(
    "Test Scene Control: Roller Venetian - " .. button_event.state_name,
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device_venetian.id,
          zigbee_test_utils.build_custom_command_id(mock_device_venetian, Scenes.ID,
            Scenes.server.commands.RecallScene.ID, 0x0000,
            "\x00\x01" .. string.char(i) .. "\xFF\xFF", 0x04) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device_venetian:generate_test_message("button1",
          button_event.button_state({ state_change = true }))
      },
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device_venetian.id,
          zigbee_test_utils.build_custom_command_id(mock_device_venetian, Scenes.ID,
            Scenes.server.commands.RecallScene.ID, 0x0000,
            "\x00\x01" .. string.char(i) .. "\xFF\xFF", 0x03) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device_venetian:generate_test_message("button2",
          button_event.button_state({ state_change = true }))
      }
    }
  )
end

test.run_registered_tests()
