-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local capabilities = require "st.capabilities"
local zw = require "st.zwave"
local zw_test_utils = require "integration_test.zwave_test_utils"
local Basic = (require "st.zwave.CommandClass.Basic")({ version = 1 })
local SoundSwitch = (require "st.zwave.CommandClass.SoundSwitch")({ version = 1 })
local Notification = (require "st.zwave.CommandClass.Notification")({ version = 8 })
local Version = (require "st.zwave.CommandClass.Version")({ version = 1 })
local t_utils = require "integration_test.utils"

local siren_endpoints = {
  {
    command_classes = {
      { value = zw.SOUND_SWITCH },
      { value = zw.NOTIFICATION },
      { value = zw.VERSION },
      { value = zw.BASIC }
    }
  }
}

--- { manufacturerId = 0x027A, productType = 0x0004, productId = 0x0369 } -- Zooz ZSE50 Siren & Chime
local mock_siren = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("zooz-zse50.yml"),
  zwave_endpoints = siren_endpoints,
  zwave_manufacturer_id = 0x027A,
  zwave_product_type = 0x0004,
  zwave_product_id = 0x0369,
})

local tones_list = {
  [1] = { name = "test_tone1", duration = 2 },
  [2] = { name = "test_tone2", duration = 4 }
}

local function test_init()
  -- Initialize some fields to help with testing
  mock_siren:set_field("TONE_DEFAULT", 1, { persist = true })
  mock_siren:set_field("TOTAL_TONES", 2, { persist = true })
  mock_siren:set_field("TONES_LIST", tones_list, { persist = true })

  test.mock_device.add_test_device(mock_siren)
end

test.set_test_init_function(test_init)

test.register_message_test(
      "Version report should update firmware version",
      {
        {
          channel = "zwave",
          direction = "receive",
          message = { mock_siren.id, zw_test_utils.zwave_test_build_receive_command(Version:Report({
            application_version = 2,
            application_sub_version = 5
          })) }
        },
        {
          channel = "capability",
          direction = "send",
          message = mock_siren:generate_test_message("main", capabilities.firmwareUpdate.currentVersion({ value = "2.05" }))
        }
      },
      {
        min_api_version = 17
      }
)

test.register_message_test(
      "Notification report AC_MAINS_DISCONNECTED should set power source to battery",
      {
        {
          channel = "zwave",
          direction = "receive",
          message = { mock_siren.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
            notification_type = Notification.notification_type.POWER_MANAGEMENT,
            event = Notification.event.power_management.AC_MAINS_DISCONNECTED
          })) }
        },
        {
          channel = "capability",
          direction = "send",
          message = mock_siren:generate_test_message("main", capabilities.powerSource.powerSource.battery())
        }
      },
      {
        min_api_version = 17
      }
)

test.register_message_test(
      "Notification report AC_MAINS_RE_CONNECTED should set power source to mains",
      {
        {
          channel = "zwave",
          direction = "receive",
          message = { mock_siren.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
            notification_type = Notification.notification_type.POWER_MANAGEMENT,
            event = Notification.event.power_management.AC_MAINS_RE_CONNECTED
          })) }
        },
        {
          channel = "capability",
          direction = "send",
          message = mock_siren:generate_test_message("main", capabilities.powerSource.powerSource.mains())
        }
      },
      {
        min_api_version = 17
      }
)

test.register_message_test(
      "SoundSwitch ConfigurationReport should update volume",
      {
        {
          channel = "zwave",
          direction = "receive",
          message = { mock_siren.id, zw_test_utils.zwave_test_build_receive_command(SoundSwitch:ConfigurationReport({
            volume = 75,
            default_tone_identifer = 5
          })) }
        },
        {
          channel = "capability",
          direction = "send",
          message = mock_siren:generate_test_message("main", capabilities.audioVolume.volume(75))
        }
      },
      {
        min_api_version = 17
      }
)

test.register_message_test(
      "SoundSwitch TonesNumberReport should request info on each tone",
      {
        {
          channel = "zwave",
          direction = "receive",
          message = { mock_siren.id, zw_test_utils.zwave_test_build_receive_command(SoundSwitch:TonesNumberReport({
            supported_tones = 2
          })) }
        },
        {
          channel = "zwave",
          direction = "send",
          message = zw_test_utils.zwave_test_build_send_command(
                mock_siren,
                SoundSwitch:ToneInfoGet({ tone_identifier = 1 })
          )
        },
        {
          channel = "zwave",
          direction = "send",
          message = zw_test_utils.zwave_test_build_send_command(
                mock_siren,
                SoundSwitch:ToneInfoGet({ tone_identifier = 2 })
          )
        }
      },
      {
        min_api_version = 17
      }
)

test.register_message_test(
      "SoundSwitch ToneInfoReport should update supported modes when all tones received",
      {
        {
          channel = "zwave",
          direction = "receive",
          message = { mock_siren.id, zw_test_utils.zwave_test_build_receive_command(SoundSwitch:ToneInfoReport({
            tone_identifier = 1,
            name = "test_tone1",
            tone_duration = 2
          })) }
        },
        {
          channel = "zwave",
          direction = "receive",
          message = { mock_siren.id, zw_test_utils.zwave_test_build_receive_command(SoundSwitch:ToneInfoReport({
            tone_identifier = 2,
            name = "test_tone2",
            tone_duration = 4
          })) }
        },
        {
          channel = "capability",
          direction = "send",
          message = mock_siren:generate_test_message("main", capabilities.mode.supportedModes({ "Rebuild List", "Off", "1: test_tone1 (2s)", "2: test_tone2 (4s)" }))
        },
        {
          channel = "capability",
          direction = "send",
          message = mock_siren:generate_test_message("main", capabilities.mode.supportedArguments({ "Off", "1: test_tone1 (2s)", "2: test_tone2 (4s)" }))
        },
        {
          channel = "zwave",
          direction = "send",
          message = zw_test_utils.zwave_test_build_send_command(
                mock_siren,
                SoundSwitch:TonePlayGet({})
          )
        }
      },
      {
        min_api_version = 17
      }
)

test.register_message_test(
      "SoundSwitch TonePlayReport for tone 1 should set alarm on, chime on, and mode to tone name",
      {
        {
          channel = "zwave",
          direction = "receive",
          message = { mock_siren.id, zw_test_utils.zwave_test_build_receive_command(SoundSwitch:TonePlayReport({
            tone_identifier = 1
          })) }
        },
        {
          channel = "capability",
          direction = "send",
          message = mock_siren:generate_test_message("main", capabilities.alarm.alarm.both())
        },
        {
          channel = "capability",
          direction = "send",
          message = mock_siren:generate_test_message("main", capabilities.chime.chime.chime())
        },
        {
          channel = "capability",
          direction = "send",
          message = mock_siren:generate_test_message("main", capabilities.mode.mode("1: test_tone1 (2s)"))
        }
      },
      {
        min_api_version = 17
      }
)

test.register_message_test(
      "SoundSwitch TonePlayReport for tone 0 should set alarm off, chime off, and mode Off",
      {
        {
          channel = "zwave",
          direction = "receive",
          message = { mock_siren.id, zw_test_utils.zwave_test_build_receive_command(SoundSwitch:TonePlayReport({
            tone_identifier = 0
          })) }
        },
        {
          channel = "capability",
          direction = "send",
          message = mock_siren:generate_test_message("main", capabilities.alarm.alarm.off())
        },
        {
          channel = "capability",
          direction = "send",
          message = mock_siren:generate_test_message("main", capabilities.chime.chime.off())
        },
        {
          channel = "capability",
          direction = "send",
          message = mock_siren:generate_test_message("main", capabilities.mode.mode("Off"))
        }
      },
      {
        min_api_version = 17
      }
)

test.register_message_test(
      "Basic report 0x00 should be handled as alarm off, chime off, and mode Off",
      {
        {
          channel = "zwave",
          direction = "receive",
          message = {
            mock_siren.id,
            zw_test_utils.zwave_test_build_receive_command(Basic:Report({ value = 0 })) }
        },
        {
          channel = "capability",
          direction = "send",
          message = mock_siren:generate_test_message("main", capabilities.alarm.alarm.off())
        },
        {
          channel = "capability",
          direction = "send",
          message = mock_siren:generate_test_message("main", capabilities.chime.chime.off())
        },
        {
          channel = "capability",
          direction = "send",
          message = mock_siren:generate_test_message("main", capabilities.mode.mode("Off"))
        }
      },
      {
        min_api_version = 17
      }
)

test.register_coroutine_test(
      "volumeUp should increase volume by 2",
      function()
        test.socket.capability:__queue_receive({
          mock_siren.id,
          { capability = "audioVolume", component = "main", command = "volumeUp", args = {} }
        })
        test.socket.zwave:__expect_send(
              zw_test_utils.zwave_test_build_send_command(
                    mock_siren,
                    SoundSwitch:ConfigurationSet({ volume = 52 })
              )
        )
      end,
      {
        min_api_version = 17
      }
)

test.register_coroutine_test(
      "volumeUp should decrease volume by 2",
      function()
        test.socket.capability:__queue_receive({
          mock_siren.id,
          { capability = "audioVolume", component = "main", command = "volumeDown", args = {} }
        })
        test.socket.zwave:__expect_send(
              zw_test_utils.zwave_test_build_send_command(
                    mock_siren,
                    SoundSwitch:ConfigurationSet({ volume = 48 })
              )
        )
      end,
      {
        min_api_version = 17
      }
)

test.register_coroutine_test(
      "setVolume should set volume to specified value",
      function()
        test.socket.capability:__queue_receive({
          mock_siren.id,
          { capability = "audioVolume", component = "main", command = "setVolume", args = { 75 } }
        })
        test.socket.zwave:__expect_send(
              zw_test_utils.zwave_test_build_send_command(
                    mock_siren,
                    SoundSwitch:ConfigurationSet({ volume = 75 })
              )
        )
      end,
      {
        min_api_version = 17
      }
)

test.register_coroutine_test(
      "alarm.both() should send TonePlaySet with default tone and TonePlayGet",
      function()
        test.socket.capability:__queue_receive({
          mock_siren.id,
          { capability = "alarm", component = "main", command = "both", args = {} }
        })
        test.socket.zwave:__expect_send(
              zw_test_utils.zwave_test_build_send_command(
                    mock_siren,
                    SoundSwitch:TonePlaySet({ tone_identifier = 0xFF })
              )
        )
        test.socket.zwave:__expect_send(
              zw_test_utils.zwave_test_build_send_command(
                    mock_siren,
                    SoundSwitch:TonePlayGet({})
              )
        )
      end,
      {
        min_api_version = 17
      }
)

test.register_coroutine_test(
      "alarm.off() should send TonePlaySet with tone 0x00 and TonePlayGet",
      function()
        test.socket.capability:__queue_receive({
          mock_siren.id,
          { capability = "alarm", component = "main", command = "off", args = {} }
        })
        test.socket.zwave:__expect_send(
              zw_test_utils.zwave_test_build_send_command(
                    mock_siren,
                    SoundSwitch:TonePlaySet({ tone_identifier = 0x00 })
              )
        )
        test.socket.zwave:__expect_send(
              zw_test_utils.zwave_test_build_send_command(
                    mock_siren,
                    SoundSwitch:TonePlayGet({})
              )
        )
      end,
      {
        min_api_version = 17
      }
)

test.register_coroutine_test(
      "chime.chime() should send TonePlaySet with default tone and TonePlayGet",
      function()
        test.socket.capability:__queue_receive({
          mock_siren.id,
          { capability = "chime", component = "main", command = "chime", args = {} }
        })
        test.socket.zwave:__expect_send(
              zw_test_utils.zwave_test_build_send_command(
                    mock_siren,
                    SoundSwitch:TonePlaySet({ tone_identifier = 0xFF })
              )
        )
        test.socket.zwave:__expect_send(
              zw_test_utils.zwave_test_build_send_command(
                    mock_siren,
                    SoundSwitch:TonePlayGet({})
              )
        )
      end,
      {
        min_api_version = 17
      }
)

test.register_coroutine_test(
      "chime.off() should send TonePlaySet with tone 0x00 and TonePlayGet",
      function()
        test.socket.capability:__queue_receive({
          mock_siren.id,
          { capability = "chime", component = "main", command = "off", args = {} }
        })
        test.socket.zwave:__expect_send(
              zw_test_utils.zwave_test_build_send_command(
                    mock_siren,
                    SoundSwitch:TonePlaySet({ tone_identifier = 0x00 })
              )
        )
        test.socket.zwave:__expect_send(
              zw_test_utils.zwave_test_build_send_command(
                    mock_siren,
                    SoundSwitch:TonePlayGet({})
              )
        )
      end,
      {
        min_api_version = 17
      }
)

test.register_coroutine_test(
      "setMode should play the specified tone",
      function()
        test.socket.capability:__queue_receive({
          mock_siren.id,
          { capability = "mode", component = "main", command = "setMode", args = { "1: test_tone1 (2s)" } }
        })
        test.socket.zwave:__expect_send(
              zw_test_utils.zwave_test_build_send_command(
                    mock_siren,
                    SoundSwitch:TonePlaySet({ tone_identifier = 1 })
              )
        )
        test.socket.zwave:__expect_send(
              zw_test_utils.zwave_test_build_send_command(
                    mock_siren,
                    SoundSwitch:TonePlayGet({})
              )
        )
      end,
      {
        min_api_version = 17
      }
)

test.register_coroutine_test(
      "setMode to Off should turn off the tone",
      function()
        test.socket.capability:__queue_receive({
          mock_siren.id,
          { capability = "mode", component = "main", command = "setMode", args = { "Off" } }
        })
        test.socket.zwave:__expect_send(
              zw_test_utils.zwave_test_build_send_command(
                    mock_siren,
                    SoundSwitch:TonePlaySet({ tone_identifier = 0x00 })
              )
        )
        test.socket.zwave:__expect_send(
              zw_test_utils.zwave_test_build_send_command(
                    mock_siren,
                    SoundSwitch:TonePlayGet({})
              )
        )
      end,
      {
        min_api_version = 17
      }
)

test.register_coroutine_test(
      "setMode to Rebuild List should emit mode and send TonesNumberGet",
      function()
        test.socket.capability:__queue_receive({
          mock_siren.id,
          { capability = "mode", component = "main", command = "setMode", args = { "Rebuild List" } }
        })
        test.socket.capability:__expect_send(
              mock_siren:generate_test_message("main", capabilities.mode.mode("Rebuild List"))
        )
        test.socket.zwave:__expect_send(
              zw_test_utils.zwave_test_build_send_command(
                    mock_siren,
                    SoundSwitch:TonesNumberGet({})
              )
        )
      end,
      {
        min_api_version = 17
      }
)

test.register_coroutine_test(
      "refresh should send a series of Z-Wave Gets",
      function()
        test.socket.capability:__queue_receive({
          mock_siren.id,
          { capability = "refresh", component = "main", command = "refresh", args = {} }
        })
        test.socket.zwave:__expect_send(
              zw_test_utils.zwave_test_build_send_command(
                    mock_siren,
                    Basic:Get({})
              )
        )
        test.socket.zwave:__expect_send(
              zw_test_utils.zwave_test_build_send_command(
                    mock_siren,
                    Version:Get({})
              )
        )
        test.socket.zwave:__expect_send(
              zw_test_utils.zwave_test_build_send_command(
                    mock_siren,
                    Notification:Get({
                      notification_type = Notification.notification_type.POWER_MANAGEMENT,
                      event = Notification.event.power_management.STATE_IDLE,
                      v1_alarm_type = 0
                    })
              )
        )
        test.socket.zwave:__expect_send(
              zw_test_utils.zwave_test_build_send_command(
                    mock_siren,
                    SoundSwitch:ConfigurationGet({})
              )
        )
        test.socket.zwave:__expect_send(
              zw_test_utils.zwave_test_build_send_command(
                    mock_siren,
                    SoundSwitch:TonePlayGet({})
              )
        )
      end,
      {
        min_api_version = 17
      }
)

test.run_registered_tests()
