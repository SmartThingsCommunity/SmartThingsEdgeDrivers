-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

-- tests/test_pad19.lua

local test = require "integration_test"
local t_utils = require "integration_test.utils"
local capabilities = require "st.capabilities"
local zw = require "st.zwave"
local Basic = (require "st.zwave.CommandClass.Basic")({version=1})
local SwitchMultilevel = (require "st.zwave.CommandClass.SwitchMultilevel")({version=1})

local zwave_endpoints = {
    {
      command_classes = {
        {value = zw.BASIC},
        {value = zw.SWITCH_MULTILEVEL}
      }
    }
}

local mock_device = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("switch-level.yml"),
  zwave_endpoints = zwave_endpoints,
  zwave_manufacturer_id = 0x013C,
  zwave_product_type = 0x0005,
  zwave_product_id = 0x008A
})

local function test_init()
  test.mock_device.add_test_device(mock_device)
end

test.set_test_init_function(test_init)

--------------------------------------------------------
-- Lifecycle added
--------------------------------------------------------
test.register_coroutine_test(
  "Device added initializes off + level 0",
  function()
    test.socket.lifecycle:__queue_receive({ mock_device.id, "added" })

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.switch.switch.off()
      )
    )

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.switchLevel.level(0)
      )
    )
  end
)

--------------------------------------------------------
-- TEST 1 : switch on command
--------------------------------------------------------
test.register_message_test(
  "Switch On sends Basic:Set 0xFF",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        capability = "switch",
        component = "main",
        command = "on",
        args = {}
      }
    },
    {
      channel = "zwave",
      direction = "send",
      message = mock_device:generate_test_message("main",
        Basic:Set({value=0xFF})
      )
    }
  }
)

--------------------------------------------------------
-- TEST 2 : switch off command
--------------------------------------------------------
test.register_message_test(
  "Switch Off sends Basic:Set 0x00",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        capability = "switch",
        component = "main",
        command = "off",
        args = {}
      }
    },
    {
      channel = "zwave",
      direction = "send",
      message = mock_device:generate_test_message("main",
        Basic:Set({value=0x00})
      )
    }
  }
)

--------------------------------------------------------
-- TEST 3 : setLevel 50
--------------------------------------------------------
test.register_message_test(
  "SetLevel 50 sends SwitchMultilevel:Set",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        capability = "switchLevel",
        component = "main",
        command = "setLevel",
        args = {50}
      }
    },
    {
      channel = "zwave",
      direction = "send",
      message = mock_device:generate_test_message("main",
        SwitchMultilevel:Set({value=50, duration=0})
      )
    }
  }
)

--------------------------------------------------------
-- setLevel with rate=\"default\"
--------------------------------------------------------
test.register_message_test(
  "SetLevel handles rate default safely",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        capability = "switchLevel",
        component = "main",
        command = "setLevel",
        args = {60, "default"}
      }
    },
    {
      channel = "zwave",
      direction = "send",
      message = mock_device:generate_test_message("main",
        SwitchMultilevel:Set({value=60, duration=0})
      )
    }
  }
)

--------------------------------------------------------
-- TEST 4 : Basic Report 99 -> switch on
--------------------------------------------------------
test.register_message_test(
  "Basic Report 99 emits switch on",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = mock_device:generate_test_message("main",
        Basic:Report({value=99})
      )
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",
        capabilities.switch.switch.on()
      )
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",
        capabilities.switchLevel.level(99)
      )
    }
  }
)

--------------------------------------------------------
-- TEST 5 : Basic Report 0 -> switch off
--------------------------------------------------------
test.register_message_test(
  "Basic Report 0 emits switch off",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = mock_device:generate_test_message("main",
        Basic:Report({value=0})
      )
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",
        capabilities.switch.switch.off()
      )
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",
        capabilities.switchLevel.level(0)
      )
    }
  }
)

--------------------------------------------------------
-- TEST 6 : Refresh command
--------------------------------------------------------
test.register_message_test(
  "Refresh sends Basic:Get and SwitchMultilevel:Get",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        capability = "refresh",
        component = "main",
        command = "refresh",
        args = {}
      }
    },
    {
      channel = "zwave",
      direction = "send",
      message = mock_device:generate_test_message("main",
        Basic:Get({})
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = mock_device:generate_test_message("main",
        SwitchMultilevel:Get({})
      )
    }
  }
)

--------------------------------------------------------
-- Basic Report OFF_DISABLE
--------------------------------------------------------
test.register_message_test(
  "Basic Report OFF_DISABLE -> off",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = mock_device:generate_test_message("main",
        Basic:Report({value="OFF_DISABLE"})
      )
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",
        capabilities.switch.switch.off()
      )
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",
        capabilities.switchLevel.level(0)
      )
    }
  }
)

--------------------------------------------------------
-- SwitchMultilevel Report 30
--------------------------------------------------------
test.register_message_test(
  "SwitchMultilevel Report 30",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = mock_device:generate_test_message("main",
        SwitchMultilevel:Report({value=30})
      )
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",
        capabilities.switch.switch.on()
      )
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",
        capabilities.switchLevel.level(30)
      )
    }
  }
)

test.run_registered_tests()