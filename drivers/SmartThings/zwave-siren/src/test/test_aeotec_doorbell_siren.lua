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
local t_utils = require "integration_test.utils"
local capabilities = require "st.capabilities"
local zw = require "st.zwave"
local zw_test_utils = require "integration_test.zwave_test_utils"
local Basic = (require "st.zwave.CommandClass.Basic")({version=1})
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version=4 })
local Notification = (require "st.zwave.CommandClass.Notification")({version=3})
local SoundSwitch =  (require "st.zwave.CommandClass.SoundSwitch")({version=1})

local ON = 0xFF
local OFF = 0x00
local BUTTON_BATTERY_LOW = 5
local BUTTON_BATTERY_NORMAL = 99

local aeotec_doorbell_siren_endpoints = {
  {command_classes = {
    {value = zw.BASIC},
    {value = zw.NOTIFICATION}
  }},
  {command_classes = {
    {value = zw.BASIC},
    {value = zw.NOTIFICATION}
  }},
  {command_classes = {
    {value = zw.BASIC},
    {value = zw.NOTIFICATION}
  }},
  {command_classes = {
    {value = zw.BASIC},
    {value = zw.NOTIFICATION}
  }},
  {command_classes = {
    {value = zw.BASIC},
    {value = zw.NOTIFICATION}
  }},
  {command_classes = {
    {value = zw.BASIC},
    {value = zw.NOTIFICATION}
  }},
  {command_classes = {
    {value = zw.BASIC},
    {value = zw.NOTIFICATION}
  }},
  {command_classes = {
    {value = zw.BASIC},
    {value = zw.NOTIFICATION}
  }},
  {command_classes = {
    {value = zw.BASIC},
    {value = zw.NOTIFICATION}
  }}
}

local mock_siren = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("aeotec-doorbell-siren.yml"),
  zwave_endpoints = aeotec_doorbell_siren_endpoints,
  zwave_manufacturer_id = 0x0371,
  zwave_product_type = 0x0003,
  zwave_product_id = 0x00A2
})

local mock_siren_with_buttons = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("aeotec-doorbell-siren-battery.yml"),
  zwave_endpoints = aeotec_doorbell_siren_endpoints,
  zwave_manufacturer_id = 0x0371,
  zwave_product_type = 0x0003,
  zwave_product_id = 0x00A2
})

local function test_init()
  test.mock_device.add_test_device(mock_siren)
  test.mock_device.add_test_device(mock_siren_with_buttons)
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Notification Report (SIREN / STATE_IDLE) - src_channel: 0  should be handled as alarm off, chime off in the main component",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(5, "oneshot")
    test.socket.zwave:__set_channel_ordering("relaxed")
    test.socket.capability:__set_channel_ordering("relaxed")

    mock_siren:set_field("last_triggered_endpoint", 0)

    test.socket.zwave:__queue_receive({
      mock_siren.id,
      zw_test_utils.zwave_test_build_receive_command(
        Notification:Report(
          {
            notification_type = Notification.notification_type.SIREN,
            event = Notification.event.siren.STATE_IDLE
          },
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels = {0}
          }
        )
      )
    })

    test.socket.capability:__expect_send(
      mock_siren:generate_test_message("main", capabilities.alarm.alarm.off())
    )
    test.socket.capability:__expect_send(
      mock_siren:generate_test_message("main", capabilities.chime.chime.off())
    )
  end
)

test.register_coroutine_test(
  "Notification Report (SIREN / STATE_IDLE) - src_channel: 2  should be handled as alarm off, chime off in the sound2 component",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(5, "oneshot")
    test.socket.zwave:__set_channel_ordering("relaxed")
    test.socket.capability:__set_channel_ordering("relaxed")

    mock_siren:set_field("last_triggered_endpoint", 2)

    test.socket.zwave:__queue_receive({
      mock_siren.id,
      zw_test_utils.zwave_test_build_receive_command(
        Notification:Report(
          {
            notification_type = Notification.notification_type.SIREN,
            event = Notification.event.siren.STATE_IDLE
          },
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 2,
            dst_channels = {0}
          }
        )
      )
    })

    test.socket.capability:__expect_send(
      mock_siren:generate_test_message("sound2", capabilities.alarm.alarm.off())
    )
    test.socket.capability:__expect_send(
      mock_siren:generate_test_message("sound2", capabilities.chime.chime.off())
    )
  end
)

test.register_coroutine_test(
  "Notification Report (SIREN / STATE_IDLE) - src_channel: 3  should be handled as alarm off, chime off in the sound3 component",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(5, "oneshot")
    test.socket.zwave:__set_channel_ordering("relaxed")
    test.socket.capability:__set_channel_ordering("relaxed")

    mock_siren:set_field("last_triggered_endpoint", 3)

    test.socket.zwave:__queue_receive({
      mock_siren.id,
      zw_test_utils.zwave_test_build_receive_command(
        Notification:Report(
          {
            notification_type = Notification.notification_type.SIREN,
            event = Notification.event.siren.STATE_IDLE
          },
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 3,
            dst_channels = {0}
          }
        )
      )
    })

    test.socket.capability:__expect_send(
      mock_siren:generate_test_message("sound3", capabilities.alarm.alarm.off())
    )
    test.socket.capability:__expect_send(
      mock_siren:generate_test_message("sound3", capabilities.chime.chime.off())
    )
  end
)

test.register_coroutine_test(
  "Notification Report (SIREN / STATE_IDLE) - src_channel: 4  should be handled as alarm off, chime off in the sound4 component",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(5, "oneshot")
    test.socket.zwave:__set_channel_ordering("relaxed")
    test.socket.capability:__set_channel_ordering("relaxed")

    mock_siren:set_field("last_triggered_endpoint", 4)

    test.socket.zwave:__queue_receive({
      mock_siren.id,
      zw_test_utils.zwave_test_build_receive_command(
        Notification:Report(
          {
            notification_type = Notification.notification_type.SIREN,
            event = Notification.event.siren.STATE_IDLE
          },
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 4,
            dst_channels = {0}
          }
        )
      )
    })

    test.socket.capability:__expect_send(
      mock_siren:generate_test_message("sound4", capabilities.alarm.alarm.off())
    )
    test.socket.capability:__expect_send(
      mock_siren:generate_test_message("sound4", capabilities.chime.chime.off())
    )
  end
)

test.register_coroutine_test(
  "Notification Report (SIREN / STATE_IDLE) - src_channel: 5  should be handled as alarm off, chime off in the sound5 component",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(5, "oneshot")
    test.socket.zwave:__set_channel_ordering("relaxed")
    test.socket.capability:__set_channel_ordering("relaxed")

    mock_siren:set_field("last_triggered_endpoint", 5)

    test.socket.zwave:__queue_receive({
      mock_siren.id,
      zw_test_utils.zwave_test_build_receive_command(
        Notification:Report(
          {
            notification_type = Notification.notification_type.SIREN,
            event = Notification.event.siren.STATE_IDLE
          },
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 5,
            dst_channels = {0}
          }
        )
      )
    })

    test.socket.capability:__expect_send(
      mock_siren:generate_test_message("sound5", capabilities.alarm.alarm.off())
    )
    test.socket.capability:__expect_send(
      mock_siren:generate_test_message("sound5", capabilities.chime.chime.off())
    )
  end
)

test.register_coroutine_test(
  "Notification Report (SIREN / STATE_IDLE) - src_channel: 6  should be handled as alarm off, chime off in the sound6 component",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(5, "oneshot")
    test.socket.zwave:__set_channel_ordering("relaxed")
    test.socket.capability:__set_channel_ordering("relaxed")

    mock_siren:set_field("last_triggered_endpoint", 6)

    test.socket.zwave:__queue_receive({
      mock_siren.id,
      zw_test_utils.zwave_test_build_receive_command(
        Notification:Report(
          {
            notification_type = Notification.notification_type.SIREN,
            event = Notification.event.siren.STATE_IDLE
          },
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 6,
            dst_channels = {0}
          }
        )
      )
    })

    test.socket.capability:__expect_send(
      mock_siren:generate_test_message("sound6", capabilities.alarm.alarm.off())
    )
    test.socket.capability:__expect_send(
      mock_siren:generate_test_message("sound6", capabilities.chime.chime.off())
    )
  end
)

test.register_coroutine_test(
  "Notification Report (SIREN / STATE_IDLE) - src_channel: 7  should be handled as alarm off, chime off in the sound7 component",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(5, "oneshot")
    test.socket.zwave:__set_channel_ordering("relaxed")
    test.socket.capability:__set_channel_ordering("relaxed")

    mock_siren:set_field("last_triggered_endpoint", 7)

    test.socket.zwave:__queue_receive({
      mock_siren.id,
      zw_test_utils.zwave_test_build_receive_command(
        Notification:Report(
          {
            notification_type = Notification.notification_type.SIREN,
            event = Notification.event.siren.STATE_IDLE
          },
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 7,
            dst_channels = {0}
          }
        )
      )
    })

    test.socket.capability:__expect_send(
      mock_siren:generate_test_message("sound7", capabilities.alarm.alarm.off())
    )
    test.socket.capability:__expect_send(
      mock_siren:generate_test_message("sound7", capabilities.chime.chime.off())
    )
  end
)

test.register_coroutine_test(
  "Notification Report (SIREN / STATE_IDLE) - src_channel: 8  should be handled as alarm off, chime off in the sound8 component",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(5, "oneshot")
    test.socket.zwave:__set_channel_ordering("relaxed")
    test.socket.capability:__set_channel_ordering("relaxed")

    mock_siren:set_field("last_triggered_endpoint", 8)

    test.socket.zwave:__queue_receive({
      mock_siren.id,
      zw_test_utils.zwave_test_build_receive_command(
        Notification:Report(
          {
            notification_type = Notification.notification_type.SIREN,
            event = Notification.event.siren.STATE_IDLE
          },
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 8,
            dst_channels = {0}
          }
        )
      )
    })

    test.socket.capability:__expect_send(
      mock_siren:generate_test_message("sound8", capabilities.alarm.alarm.off())
    )
    test.socket.capability:__expect_send(
      mock_siren:generate_test_message("sound8", capabilities.chime.chime.off())
    )
  end
)

test.register_message_test(
  "Notification Report (SIREN / ACTIVE) - src_channel: 0 should be handled as alarm both, chime in the main component",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_siren.id, "init" }
    },
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_siren.id,
        zw_test_utils.zwave_test_build_receive_command(
          Notification:Report(
            {
              notification_type = Notification.notification_type.SIREN,
              event = Notification.event.siren.ACTIVE
            },
            {
              encap = zw.ENCAP.AUTO,
              src_channel = 0,
              dst_channels = {0}
            }
          )
        )
      }
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
    }
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.register_message_test(
  "Notification Report (SIREN / ACTIVE) - src_channel: 2 should be handled as alarm both, chime in the sound2 component",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_siren.id, "init" }
    },
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_siren.id,
        zw_test_utils.zwave_test_build_receive_command(
          Notification:Report(
            {
              notification_type = Notification.notification_type.SIREN,
              event = Notification.event.siren.ACTIVE
            },
            {
              encap = zw.ENCAP.AUTO,
              src_channel = 2,
              dst_channels = {0}
            }
          )
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_siren:generate_test_message("sound2", capabilities.alarm.alarm.both())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_siren:generate_test_message("sound2", capabilities.chime.chime.chime())
    }
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.register_message_test(
  "Notification Report (SIREN / ACTIVE) - src_channel: 3 should be handled as alarm both, chime in the sound3 component",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_siren.id, "init" }
    },
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_siren.id,
        zw_test_utils.zwave_test_build_receive_command(
          Notification:Report(
            {
              notification_type = Notification.notification_type.SIREN,
              event = Notification.event.siren.ACTIVE
            },
            {
              encap = zw.ENCAP.AUTO,
              src_channel = 3,
              dst_channels = {0}
            }
          )
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_siren:generate_test_message("sound3", capabilities.alarm.alarm.both())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_siren:generate_test_message("sound3", capabilities.chime.chime.chime())
    }
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.register_message_test(
  "Notification Report (SIREN / ACTIVE) - src_channel: 4 should be handled as alarm both, chime in the sound4 component",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_siren.id, "init" }
    },
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_siren.id,
        zw_test_utils.zwave_test_build_receive_command(
          Notification:Report(
            {
              notification_type = Notification.notification_type.SIREN,
              event = Notification.event.siren.ACTIVE
            },
            {
              encap = zw.ENCAP.AUTO,
              src_channel = 4,
              dst_channels = {0}
            }
          )
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_siren:generate_test_message("sound4", capabilities.alarm.alarm.both())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_siren:generate_test_message("sound4", capabilities.chime.chime.chime())
    }
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.register_message_test(
  "Notification Report (SIREN / ACTIVE) - src_channel: 5 should be handled as alarm both, chime in the sound5 component",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_siren.id, "init" }
    },
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_siren.id,
        zw_test_utils.zwave_test_build_receive_command(
          Notification:Report(
            {
              notification_type = Notification.notification_type.SIREN,
              event = Notification.event.siren.ACTIVE
            },
            {
              encap = zw.ENCAP.AUTO,
              src_channel = 5,
              dst_channels = {0}
            }
          )
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_siren:generate_test_message("sound5", capabilities.alarm.alarm.both())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_siren:generate_test_message("sound5", capabilities.chime.chime.chime())
    }
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.register_message_test(
  "Notification Report (SIREN / ACTIVE) - src_channel: 6 should be handled as alarm both, chime in the sound6 component",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_siren.id, "init" }
    },
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_siren.id,
        zw_test_utils.zwave_test_build_receive_command(
          Notification:Report(
            {
              notification_type = Notification.notification_type.SIREN,
              event = Notification.event.siren.ACTIVE
            },
            {
              encap = zw.ENCAP.AUTO,
              src_channel = 6,
              dst_channels = {0}
            }
          )
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_siren:generate_test_message("sound6", capabilities.alarm.alarm.both())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_siren:generate_test_message("sound6", capabilities.chime.chime.chime())
    }
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.register_message_test(
  "Notification Report (SIREN / ACTIVE) - src_channel: 7 should be handled as alarm both, chime in the sound7 component",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_siren.id, "init" }
    },
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_siren.id,
        zw_test_utils.zwave_test_build_receive_command(
          Notification:Report(
            {
              notification_type = Notification.notification_type.SIREN,
              event = Notification.event.siren.ACTIVE
            },
            {
              encap = zw.ENCAP.AUTO,
              src_channel = 7,
              dst_channels = {0}
            }
          )
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_siren:generate_test_message("sound7", capabilities.alarm.alarm.both())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_siren:generate_test_message("sound7", capabilities.chime.chime.chime())
    }
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.register_message_test(
  "Notification Report (SIREN / ACTIVE) - src_channel: 8 should be handled as alarm both, chime in the sound8 component",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_siren.id, "init" }
    },
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_siren.id,
        zw_test_utils.zwave_test_build_receive_command(
          Notification:Report(
            {
              notification_type = Notification.notification_type.SIREN,
              event = Notification.event.siren.ACTIVE
            },
            {
              encap = zw.ENCAP.AUTO,
              src_channel = 8,
              dst_channels = {0}
            }
          )
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_siren:generate_test_message("sound8", capabilities.alarm.alarm.both())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_siren:generate_test_message("sound8", capabilities.chime.chime.chime())
    }
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.register_coroutine_test(
  "Capability command Alarm - both should be handled by main component",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_siren.id,
      { capability = "alarm", component = "main", command = "both", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Set({value = ON},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={}
          }
        )
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={}
          }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Capability command Alarm - both should be handled by sound2 component",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_siren.id,
      { capability = "alarm", component = "sound2", command = "both", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Set({value = ON},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={2}
          }
        )
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={2}
          }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Capability command Alarm - both should be handled by sound3 component",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_siren.id,
      { capability = "alarm", component = "sound3", command = "both", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
              mock_siren,
        Basic:Set({value = ON},
            {
              encap = zw.ENCAP.AUTO,
              src_channel = 0,
              dst_channels={3}
            }
        )
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={3}
          }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Capability command Alarm - both should be handled by sound4 component",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_siren.id,
      { capability = "alarm", component = "sound4", command = "both", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
              mock_siren,
        Basic:Set({value = ON},
            {
              encap = zw.ENCAP.AUTO,
              src_channel = 0,
              dst_channels={4}
            }
        )
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={4}
          }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Capability command Alarm - both should be handled by sound5 component",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_siren.id,
      { capability = "alarm", component = "sound5", command = "both", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Set({value = ON},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={5}
          }
        )
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={5}
          }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Capability command Alarm - both should be handled by sound6 component",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_siren.id,
      { capability = "alarm", component = "sound6", command = "both", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Set({value = ON},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={6}
          }
        )
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={6}
          }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Capability command Alarm - both should be handled by sound7 component",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_siren.id,
      { capability = "alarm", component = "sound7", command = "both", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Set({value = ON},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={7}
          }
        )
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={7}
          }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Capability command Alarm - both should be handled by sound8 component",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_siren.id,
      { capability = "alarm", component = "sound8", command = "both", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Set({value = ON},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={8}
          }
        )
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={8}
          }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Capability command Alarm - siren should be handled by main component",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_siren.id,
      { capability = "alarm", component = "main", command = "siren", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Set({value = ON},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={}
          }
        )
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={}
          }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Capability command Alarm - siren should be handled by sound2 component",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_siren.id,
      { capability = "alarm", component = "sound2", command = "siren", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Set({value = ON},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={2}
          }
        )
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={2}
          }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Capability command Alarm - siren should be handled by sound3 component",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_siren.id,
      { capability = "alarm", component = "sound3", command = "siren", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Set({value = ON},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={3}
          }
        )
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={3}
          }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Capability command Alarm - siren should be handled by sound4 component",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_siren.id,
      { capability = "alarm", component = "sound4", command = "siren", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Set({value = ON},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={4}
          }
        )
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={4}
          }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Capability command Alarm - siren should be handled by sound5 component",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_siren.id,
      { capability = "alarm", component = "sound5", command = "siren", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Set({value = ON},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={5}
          }
        )
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={5}
          }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Capability command Alarm - siren should be handled by sound6 component",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_siren.id,
      { capability = "alarm", component = "sound6", command = "siren", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Set({value = ON},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={6}
          }
        )
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={6}
          }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Capability command Alarm - siren should be handled by sound7 component",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_siren.id,
      { capability = "alarm", component = "sound7", command = "siren", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Set({value = ON},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={7}
          }
        )
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={7}
          }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Capability command Alarm - siren should be handled by sound8 component",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_siren.id,
      { capability = "alarm", component = "sound8", command = "siren", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Set({value = ON},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={8}
          }
        )
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={8}
          }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Capability command Alarm - strobe should be handled by main component",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_siren.id,
      { capability = "alarm", component = "main", command = "strobe", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Set({value = ON},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={}
          }
        )
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={}
          }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Capability command Alarm - strobe should be handled by sound2 component",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_siren.id,
      { capability = "alarm", component = "sound2", command = "strobe", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Set({value = ON},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={2}
          }
        )
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={2}
          }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Capability command Alarm - strobe should be handled by sound3 component",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_siren.id,
      { capability = "alarm", component = "sound3", command = "strobe", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Set({value = ON},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={3}
          }
        )
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={3}
          }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Capability command Alarm - strobe should be handled by sound4 component",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_siren.id,
      { capability = "alarm", component = "sound4", command = "strobe", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Set({value = ON},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={4}
          }
        )
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={4}
          }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Capability command Alarm - strobe should be handled by sound5 component",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_siren.id,
      { capability = "alarm", component = "sound5", command = "strobe", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Set({value = ON},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={5}
          }
        )
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={5}
          }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Capability command Alarm - strobe should be handled by sound6 component",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_siren.id,
      { capability = "alarm", component = "sound6", command = "strobe", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Set({value = ON},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={6}
          }
        )
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={6}
          }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Capability command Alarm - strobe should be handled by sound7 component",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_siren.id,
      { capability = "alarm", component = "sound7", command = "strobe", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Set({value = ON},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={7}
          }
        )
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={7}
          }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Capability command Alarm - strobe should be handled by sound8 component",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_siren.id,
      { capability = "alarm", component = "sound8", command = "strobe", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Set({value = ON},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={8}
          }
        )
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={8}
          }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Capability command Alarm - off should be handled by main component",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_siren.id,
      { capability = "alarm", component = "main", command = "off", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Set({value = OFF},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={}
          }
        )
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={}
          }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Capability command Alarm - off should be handled by sound2 component",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_siren.id,
      { capability = "alarm", component = "sound2", command = "off", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Set({value = OFF},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={2}
          }
        )
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={2}
          }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Capability command Alarm - off should be handled by sound3 component",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_siren.id,
      { capability = "alarm", component = "sound3", command = "off", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Set({value = OFF},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={3}
          }
        )
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={3}
          }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Capability command Alarm - off should be handled by sound4 component",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_siren.id,
      { capability = "alarm", component = "sound4", command = "off", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Set({value = OFF},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={4}
          }
        )
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={4}
          }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Capability command Alarm - off should be handled by sound5 component",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_siren.id,
      { capability = "alarm", component = "sound5", command = "off", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Set({value = OFF},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={5}
          }
        )
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={5}
          }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Capability command Alarm - off should be handled by sound6 component",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_siren.id,
      { capability = "alarm", component = "sound6", command = "off", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Set({value = OFF},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={6}
          }
        )
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={6}
          }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Capability command Alarm - off should be handled by sound7 component",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_siren.id,
      { capability = "alarm", component = "sound7", command = "off", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Set({value = OFF},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={7}
          }
        )
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={7}
          }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Capability command Alarm - off should be handled by sound8 component",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_siren.id,
      { capability = "alarm", component = "sound8", command = "off", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Set({value = OFF},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={8}
          }
        )
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={8}
          }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Capability command chime should be handled by main component",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_siren.id,
      { capability = "chime", component = "main", command = "chime", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Set({value = ON},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={}
          }
        )
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={}
          }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Capability command chime should be handled by sound2 component",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_siren.id,
      { capability = "chime", component = "sound2", command = "chime", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Set({value = ON},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={2}
          }
        )
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={2}
          }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Capability command chime should be handled by sound3 component",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_siren.id,
      { capability = "chime", component = "sound3", command = "chime", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Set({value = ON},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={3}
          }
        )
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={3}
          }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Capability command chime should be handled by sound4 component",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_siren.id,
      { capability = "chime", component = "sound4", command = "chime", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Set({value = ON},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={4}
          }
        )
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={4}
          }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Capability command chime should be handled by sound5 component",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_siren.id,
      { capability = "chime", component = "sound5", command = "chime", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Set({value = ON},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={5}
          }
        )
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={5}
          }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Capability command chime should be handled by sound6 component",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_siren.id,
      { capability = "chime", component = "sound6", command = "chime", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Set({value = ON},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={6}
          }
        )
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={6}
          }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Capability command chime should be handled by sound7 component",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_siren.id,
      { capability = "chime", component = "sound7", command = "chime", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Set({value = ON},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={7}
          }
        )
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={7}
          }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Capability command chime should be handled by sound8 component",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_siren.id,
      { capability = "chime", component = "sound8", command = "chime", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Set({value = ON},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={8}
          }
        )
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={8}
          }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Capability command chime off should be handled by main component",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_siren.id,
      { capability = "chime", component = "main", command = "off", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Set({value = OFF},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={}
          }
        )
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={}
          }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Capability command chime off should be handled by sound2 component",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_siren.id,
      { capability = "chime", component = "sound2", command = "off", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Set({value = OFF},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={2}
          }
        )
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={2}
          }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Capability command chime off should be handled by sound3 component",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_siren.id,
      { capability = "chime", component = "sound3", command = "off", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Set({value = OFF},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={3}
          }
        )
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={3}
          }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Capability command chime off should be handled by sound4 component",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_siren.id,
      { capability = "chime", component = "sound4", command = "off", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Set({value = OFF},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={4}
          }
        )
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={4}
          }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Capability command chime off should be handled by sound5 component",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_siren.id,
      { capability = "chime", component = "sound5", command = "off", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Set({value = OFF},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={5}
          }
        )
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={5}
          }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Capability command chime off should be handled by sound6 component",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_siren.id,
      { capability = "chime", component = "sound6", command = "off", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Set({value = OFF},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={6}
          }
        )
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={6}
          }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Capability command chime off should be handled by sound7 component",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_siren.id,
      { capability = "chime", component = "sound7", command = "off", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Set({value = OFF},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={7}
          }
        )
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={7}
          }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Capability command chime off should be handled by sound8 component",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_siren.id,
      { capability = "chime", component = "sound8", command = "off", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Set({value = OFF},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={8}
          }
        )
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={8}
          }
        )
      )
    )
  end
)

test.register_message_test(
  "Notification report home security type TAMPERING_PRODUCT_MOVED should be handled as tamper detected",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_siren.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
        notification_type = Notification.notification_type.HOME_SECURITY,
        event = Notification.event.home_security.TAMPERING_PRODUCT_MOVED
      })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_siren:generate_test_message("main", capabilities.tamperAlert.tamper.detected())
    }
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.register_message_test(
  "Notification report home security type STATE_IDLE should be handled as tamper clear, alarm off, chime off",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_siren.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
        notification_type = Notification.notification_type.HOME_SECURITY,
        event = Notification.event.home_security.STATE_IDLE
      })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_siren:generate_test_message("main", capabilities.tamperAlert.tamper.clear())
    }
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.register_coroutine_test(
  "Device should be configured if parameter configureSoundAndVolume is true",
  function()
    local _preferences = {}
    _preferences.componentName = "sound8"
    _preferences.tone = 11
    _preferences.volume = 50
    _preferences.configureSoundAndVolume = true

    test.socket.device_lifecycle:__queue_receive(mock_siren:generate_info_changed({ preferences = _preferences}))

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
              mock_siren,
        SoundSwitch:ConfigurationSet(
          {
            default_tone_identifier = 11,
            volume = 50
          },
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={8}
          }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Device shouldn't be configured if parameter configureSoundAndVolume is false",
  function()
    local _preferences = {}
    _preferences.componentName = "sound8"
    _preferences.tone = 11
    _preferences.volume = 50
    _preferences.configureSoundAndVolume = false

    test.socket.device_lifecycle:__queue_receive(mock_siren:generate_info_changed({ preferences = _preferences}))
  end
)

test.register_coroutine_test(
  "Button unpairing mode should be configured if parameter triggerButtonUnpairing is true",
  function()
    local _preferences = {}
    _preferences.buttonUnpairingMode = 1
    _preferences.triggerButtonUnpairing = true

    test.socket.device_lifecycle:__queue_receive(mock_siren:generate_info_changed({ preferences = _preferences}))

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
              mock_siren,
        Configuration:Set({
          parameter_number = 48,
          configuration_value = 1,
          size=1
        })
      )
    )
  end
)

test.register_coroutine_test(
  "Button unpairing mode shouldn't be configured if parameter triggerButtonUnpairing is false",
  function()
    local _preferences = {}
    _preferences.buttonUnpairingMode = 1
    _preferences.triggerButtonUnpairing = false

    test.socket.device_lifecycle:__queue_receive(mock_siren:generate_info_changed({ preferences = _preferences}))
  end
)

test.register_coroutine_test(
  "Button pairing mode should be configured if parameter triggerButtonPairing is true",
  function()
    local _preferences = {}
    _preferences.buttonPairingMode = 1
    _preferences.triggerButtonPairing = true

    test.socket.device_lifecycle:__queue_receive(mock_siren:generate_info_changed({ preferences = _preferences}))

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
              mock_siren,
        Configuration:Set({
          parameter_number = 49,
          configuration_value = 1,
          size=1
        })
      )
    )
  end
)

test.register_coroutine_test(
  "Button pairing mode shouldn't be configured if parameter triggerButtonPairing is false",
  function()
    local _preferences = {}
    _preferences.buttonPairingMode = 1
    _preferences.triggerButtonPairing = false

    test.socket.device_lifecycle:__queue_receive(mock_siren:generate_info_changed({ preferences = _preferences}))
  end
)

test.register_message_test(
  "Notification report POWER_MANAGEMENT type REPLACE_BATTERY_SOON should be handled as battery 5% for button 1",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_siren_with_buttons.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
        notification_type = Notification.notification_type.POWER_MANAGEMENT,
        event = Notification.event.power_management.REPLACE_BATTERY_SOON
      },
        {
          encap = zw.ENCAP.AUTO,
          src_channel = 3,
          dst_channels={0}
        }
      ))}
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_siren_with_buttons:generate_test_message("sound3", capabilities.battery.battery(BUTTON_BATTERY_LOW))
    }
  }
)

test.register_message_test(
  "Notification report POWER_MANAGEMENT type STATE_IDLE should be handled as battery 99% for button 1",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_siren_with_buttons.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
        notification_type = Notification.notification_type.POWER_MANAGEMENT,
        event = Notification.event.power_management.STATE_IDLE,
      },
        {
          encap = zw.ENCAP.AUTO,
          src_channel = 3,
          dst_channels={0}
        }
      ))}
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_siren_with_buttons:generate_test_message("sound3", capabilities.battery.battery(BUTTON_BATTERY_NORMAL))
    }
  }
)

test.register_message_test(
  "Notification report POWER_MANAGEMENT type REPLACE_BATTERY_SOON should be handled as battery 5% for button 2",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_siren_with_buttons.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
        notification_type = Notification.notification_type.POWER_MANAGEMENT,
        event = Notification.event.power_management.REPLACE_BATTERY_SOON
      },
        {
          encap = zw.ENCAP.AUTO,
          src_channel = 4,
          dst_channels={0}
        }
      ))}
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_siren_with_buttons:generate_test_message("sound4", capabilities.battery.battery(BUTTON_BATTERY_LOW))
    }
  }
)

test.register_message_test(
  "Notification report POWER_MANAGEMENT type STATE_IDLE should be handled as battery 99% for button 2",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_siren_with_buttons.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
        notification_type = Notification.notification_type.POWER_MANAGEMENT,
        event = Notification.event.power_management.STATE_IDLE,
      },
        {
          encap = zw.ENCAP.AUTO,
          src_channel = 4,
          dst_channels={0}
        }
      ))}
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_siren_with_buttons:generate_test_message("sound4", capabilities.battery.battery(BUTTON_BATTERY_NORMAL))
    }
  }
)

test.register_message_test(
  "Notification report POWER_MANAGEMENT type REPLACE_BATTERY_SOON should be handled as battery 5% for button 3",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_siren_with_buttons.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
        notification_type = Notification.notification_type.POWER_MANAGEMENT,
        event = Notification.event.power_management.REPLACE_BATTERY_SOON
      },
        {
          encap = zw.ENCAP.AUTO,
          src_channel = 5,
          dst_channels={0}
        }
      ))}
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_siren_with_buttons:generate_test_message("sound5", capabilities.battery.battery(BUTTON_BATTERY_LOW))
    }
  }
)

test.register_message_test(
  "Notification report POWER_MANAGEMENT type STATE_IDLE should be handled as battery 99% for button 3",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_siren_with_buttons.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
        notification_type = Notification.notification_type.POWER_MANAGEMENT,
        event = Notification.event.power_management.STATE_IDLE,
      },
        {
          encap = zw.ENCAP.AUTO,
          src_channel = 5,
          dst_channels={0}
        }
      ))}
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_siren_with_buttons:generate_test_message("sound5", capabilities.battery.battery(BUTTON_BATTERY_NORMAL))
    }
  }
)

test.register_coroutine_test(
  "Selecting stop siren parameter should switch the sound off",
  function()
    local _preferences = {}
    _preferences.stopSiren = true

    test.socket.device_lifecycle:__queue_receive(mock_siren:generate_info_changed({ preferences = _preferences}))
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Set({value = OFF},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={}
          }
        )
      )
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={}
          })
      )
    )
  end
)

test.register_coroutine_test(
        "PROFILE CHANGE - 1 - should be handled as battery 5% for button 5",
        function()
            test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
            mock_siren:set_field("device_profile_change_in_progress", true, { persist = true})
            mock_siren:set_field("next_button_battery_event_details", { endpoint = 5, batteryStatus = BUTTON_BATTERY_LOW}, { persist = true})
            local updates = {
                profile = t_utils.get_profile_definition("aeotec-doorbell-siren-battery.yml")
            }
            test.socket.device_lifecycle:__queue_receive(mock_siren:generate_info_changed(updates))
            test.mock_time.advance_time(1)
            test.socket.capability:__expect_send(
                    mock_siren:generate_test_message("sound5", capabilities.battery.battery(BUTTON_BATTERY_LOW))
            )
        end
)

test.run_registered_tests()
