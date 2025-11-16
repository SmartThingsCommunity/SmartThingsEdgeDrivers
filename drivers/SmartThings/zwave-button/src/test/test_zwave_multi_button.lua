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
local zw = require "st.zwave"
local zw_test_utils = require "integration_test.zwave_test_utils"
local Battery = (require "st.zwave.CommandClass.Battery")({ version=1 })
local CentralScene = (require "st.zwave.CommandClass.CentralScene")({ version=1 })
local SceneActivation = (require "st.zwave.CommandClass.SceneActivation")({ version = 1 })
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version = 4 })
local Association = (require "st.zwave.CommandClass.Association")({ version = 1 })
local t_utils = require "integration_test.utils"

local zwave_multi_2_button_profile = t_utils.get_profile_definition("multi-button-2.yml")
local zwave_multi_4_button_profile = t_utils.get_profile_definition("multi-button-4.yml")
local zwave_multi_6_button_profile = t_utils.get_profile_definition("multi-button-6.yml")

local button_endpoints = {
  {
    command_classes = {
      {value = zw.SCENE_ACTIVATION},
      {value = zw.CENTRAL_SCENE},
      {value = zw.BATTERY}
    }
  }
}

local mock_everspring = test.mock_device.build_test_zwave_device({
  profile = zwave_multi_2_button_profile,
  zwave_endpoints = button_endpoints,
  zwave_manufacturer_id = 0x0060,
  zwave_product_type = 0x000A,
  zwave_product_id = 0x0003
})

local mock_aeotec_keyfob_button = test.mock_device.build_test_zwave_device({
  profile = zwave_multi_4_button_profile,
  zwave_endpoints = button_endpoints,
  zwave_manufacturer_id = 0x0086,
  zwave_product_type = 0x0101,
  zwave_product_id = 0x0058
})

local mock_fibaro_keyfob_button = test.mock_device.build_test_zwave_device({
  profile = zwave_multi_6_button_profile,
  zwave_endpoints = button_endpoints,
  zwave_manufacturer_id = 0x010F,
  zwave_product_type = 0x1001,
  zwave_product_id = 0x1000
})

local mock_aeotec_wallmote_quad = test.mock_device.build_test_zwave_device({
  profile = zwave_multi_4_button_profile,
  zwave_endpoints = button_endpoints,
  zwave_manufacturer_id = 0x0086,
  zwave_product_type = 0x0102,
  zwave_product_id = 0x0082
})

local function  test_init()
  test.mock_device.add_test_device(mock_everspring)
  test.mock_device.add_test_device(mock_aeotec_keyfob_button)
  test.mock_device.add_test_device(mock_fibaro_keyfob_button)
  test.mock_device.add_test_device(mock_aeotec_wallmote_quad)
end
test.set_test_init_function(test_init)

local function added_events(device, numberOfButtons, supportedButtonValues)
  local components = {"main"}
  for i = 1,numberOfButtons do
    table.insert(components, "button"..i)
  end
  for _, component in pairs(components) do
    if (component == "main") then
      test.socket.capability:__expect_send(device:generate_test_message(component, capabilities.button.numberOfButtons({value = numberOfButtons}, {visibility = { displayed = false }})))
    else
      test.socket.capability:__expect_send(device:generate_test_message(component, capabilities.button.numberOfButtons({value = 1}, {visibility = { displayed = false }})))
    end
    test.socket.capability:__expect_send(device:generate_test_message(component, capabilities.button.supportedButtonValues(supportedButtonValues, {visibility = { displayed = false }})))
  end
end

--central scene notification
test.register_message_test(
  "Central scene notification command (scene number 1 & pushed) generate capability to proper component",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_everspring.id,
        zw_test_utils.zwave_test_build_receive_command(
          CentralScene:Notification({ key_attributes=CentralScene.key_attributes.KEY_PRESSED_1_TIME, scene_number = 1})
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_everspring:generate_test_message("button1", capabilities.button.button.pushed({state_change = true}))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_everspring:generate_test_message("main", capabilities.button.button.pushed({state_change = true}))
    }
  }
)

test.register_message_test(
  "Central scene notification command (scene number 1 & held) generate capability to proper component",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_everspring.id,
        zw_test_utils.zwave_test_build_receive_command(
          CentralScene:Notification({ key_attributes=CentralScene.key_attributes.KEY_RELEASED, scene_number = 1})
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_everspring:generate_test_message("button1", capabilities.button.button.held({state_change = true}))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_everspring:generate_test_message("main", capabilities.button.button.held({state_change = true}))
    }
  }
)

test.register_coroutine_test(
  "Central scene notification command (scene number 1 & double) generate capability to proper component",
  function ()
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({ mock_everspring.id, "added" })
    added_events(mock_everspring, 2, {"pushed", "held", "double"})
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_everspring,
      Battery:Get({})
    ))
    test.wait_for_events()
    test.socket.zwave:__queue_receive({mock_everspring.id,
      CentralScene:Notification({ key_attributes=CentralScene.key_attributes.KEY_PRESSED_2_TIMES, scene_number = 1 })
    })
    test.socket.capability:__expect_send(mock_everspring:generate_test_message(
      "button1",
      capabilities.button.button.double({state_change = true})))
    test.socket.capability:__expect_send(mock_everspring:generate_test_message(
      "main",
      capabilities.button.button.double({state_change = true})))
  end
)

test.register_message_test(
  "Central scene notification command (scene number 2 & pushed) generate capability to proper component",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_everspring.id,
        zw_test_utils.zwave_test_build_receive_command(
          CentralScene:Notification({ key_attributes=CentralScene.key_attributes.KEY_PRESSED_1_TIME, scene_number = 2})
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_everspring:generate_test_message("button2", capabilities.button.button.pushed({state_change = true}))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_everspring:generate_test_message("main", capabilities.button.button.pushed({state_change = true}))
    }
  }
)

test.register_message_test(
  "Central scene notification command (scene number 2 & held) generate capability to proper component",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_everspring.id,
        zw_test_utils.zwave_test_build_receive_command(
          CentralScene:Notification({ key_attributes=CentralScene.key_attributes.KEY_RELEASED, scene_number = 2})
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_everspring:generate_test_message("button2", capabilities.button.button.held({state_change = true}))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_everspring:generate_test_message("main", capabilities.button.button.held({state_change = true}))
    }
  }
)

test.register_coroutine_test(
  "Central scene notification command (scene number 2 & double) generate capability to proper component",
  function ()
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({ mock_everspring.id, "added" })
    added_events(mock_everspring, 2, {"pushed", "held", "double"})
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_everspring,
      Battery:Get({})
    ))
    test.wait_for_events()
    test.socket.zwave:__queue_receive({mock_everspring.id,
      CentralScene:Notification({ key_attributes=CentralScene.key_attributes.KEY_PRESSED_2_TIMES, scene_number = 2 })
    })
    test.socket.capability:__expect_send(mock_everspring:generate_test_message(
      "button2",
      capabilities.button.button.double({state_change = true})))
    test.socket.capability:__expect_send(mock_everspring:generate_test_message(
      "main",
      capabilities.button.button.double({state_change = true})))
  end
)

test.register_message_test(
  "Central scene notification command (scene number 3 & pushed) generate capability to proper component",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_aeotec_wallmote_quad.id,
        zw_test_utils.zwave_test_build_receive_command(
          CentralScene:Notification({ key_attributes=CentralScene.key_attributes.KEY_PRESSED_1_TIME, scene_number = 3})
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_aeotec_wallmote_quad:generate_test_message("button3", capabilities.button.button.pushed({state_change = true}))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_aeotec_wallmote_quad:generate_test_message("main", capabilities.button.button.pushed({state_change = true}))
    }
  }
)

test.register_message_test(
  "Central scene notification command (scene number 3 & held) generate capability to proper component",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_aeotec_wallmote_quad.id,
        zw_test_utils.zwave_test_build_receive_command(
          CentralScene:Notification({ key_attributes=CentralScene.key_attributes.KEY_RELEASED, scene_number = 3})
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_aeotec_wallmote_quad:generate_test_message("button3", capabilities.button.button.held({state_change = true}))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_aeotec_wallmote_quad:generate_test_message("main", capabilities.button.button.held({state_change = true}))
    }
  }
)

test.register_message_test(
  "Central scene notification command (scene number 4 & pushed) generate capability to proper component",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_aeotec_wallmote_quad.id,
        zw_test_utils.zwave_test_build_receive_command(
          CentralScene:Notification({ key_attributes=CentralScene.key_attributes.KEY_PRESSED_1_TIME, scene_number = 4})
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_aeotec_wallmote_quad:generate_test_message("button4", capabilities.button.button.pushed({state_change = true}))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_aeotec_wallmote_quad:generate_test_message("main", capabilities.button.button.pushed({state_change = true}))
    }
  }
)

test.register_coroutine_test(
  "Central scene notification command (scene number 4 & held) generate capability to proper component",
  function ()
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({ mock_aeotec_wallmote_quad.id, "added" })
    added_events(mock_aeotec_wallmote_quad, 4, {"pushed", "held"})
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_aeotec_wallmote_quad,
      Battery:Get({})
    ))
    test.socket.zwave:__queue_receive({mock_aeotec_wallmote_quad.id,
      CentralScene:Notification({ key_attributes=CentralScene.key_attributes.KEY_RELEASED, scene_number = 4 })
    })
    test.socket.capability:__expect_send(mock_aeotec_wallmote_quad:generate_test_message(
      "button4",
      capabilities.button.button.held({state_change = true})))
    test.socket.capability:__expect_send(mock_aeotec_wallmote_quad:generate_test_message(
      "main",
      capabilities.button.button.held({state_change = true})))
  end
)

test.register_message_test(
  "Central scene notification command for an unsupported action should not generate an event",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_aeotec_wallmote_quad.id,
        zw_test_utils.zwave_test_build_receive_command(
          CentralScene:Notification({ key_attributes=CentralScene.key_attributes.KEY_HELD_DOWN, scene_number = 4})
        )
      }
    }
  }
)

--scene activation set
test.register_message_test(
  "Scene Activation set command (scene id 1) generate capability to proper component",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_aeotec_keyfob_button.id,
        zw_test_utils.zwave_test_build_receive_command(
          SceneActivation:Set({ scene_id = 1 })
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_aeotec_keyfob_button:generate_test_message("button1", capabilities.button.button.pushed({state_change = true}))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_aeotec_keyfob_button:generate_test_message("main", capabilities.button.button.pushed({state_change = true}))
    }
  }
)

test.register_message_test(
  "Scene Activation set command (scene id 2) generate capability to proper component",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_aeotec_keyfob_button.id,
        zw_test_utils.zwave_test_build_receive_command(
          SceneActivation:Set({ scene_id = 2 })
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_aeotec_keyfob_button:generate_test_message("button1", capabilities.button.button.held({state_change = true}))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_aeotec_keyfob_button:generate_test_message("main", capabilities.button.button.held({state_change = true}))
    }
  }
)

test.register_message_test(
  "Scene Activation set command (scene id 3) generate capability to proper component",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_aeotec_keyfob_button.id,
        zw_test_utils.zwave_test_build_receive_command(
          SceneActivation:Set({ scene_id = 3 })
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_aeotec_keyfob_button:generate_test_message("button2", capabilities.button.button.pushed({state_change = true}))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_aeotec_keyfob_button:generate_test_message("main", capabilities.button.button.pushed({state_change = true}))
    }
  }
)

test.register_message_test(
  "Scene Activation set command (scene id 4) generate capability to proper component",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_aeotec_keyfob_button.id,
        zw_test_utils.zwave_test_build_receive_command(
          SceneActivation:Set({ scene_id = 4 })
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_aeotec_keyfob_button:generate_test_message("button2", capabilities.button.button.held({state_change = true}))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_aeotec_keyfob_button:generate_test_message("main", capabilities.button.button.held({state_change = true}))
    }
  }
)

--configuration for aeotec keyfob
test.register_coroutine_test(
  "doConfigure lifecycle event should generate proper configuration command for aeotec keyfob device",
  function()
    test.socket.zwave:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({ mock_aeotec_keyfob_button.id, "doConfigure" })
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_aeotec_keyfob_button,
        Battery:Get({})
    ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_aeotec_keyfob_button,
        Configuration:Set({parameter_number = 250, size = 1, configuration_value = 1})
    ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_aeotec_keyfob_button,
        Association:Set({grouping_identifier = 1, node_ids = {}})
    ))
    mock_aeotec_keyfob_button:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)

test.register_coroutine_test(
  "Device added event should make proper event for aeotec keyfob",
  function()
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({ mock_aeotec_keyfob_button.id, "added" })

    test.socket.capability:__expect_send(
      mock_aeotec_keyfob_button:generate_test_message(
        "main",
        capabilities.button.numberOfButtons({ value = 4 }, {visibility = { displayed = false }})
      )
    )

    test.socket.capability:__expect_send(
      mock_aeotec_keyfob_button:generate_test_message(
        "main",
        capabilities.button.supportedButtonValues({"pushed", "held"}, {visibility = { displayed = false }})
      )
    )

    test.socket.capability:__expect_send(
      mock_aeotec_keyfob_button:generate_test_message(
        "button1",
        capabilities.button.numberOfButtons({ value = 1 }, {visibility = { displayed = false }})
      )
    )

    test.socket.capability:__expect_send(
      mock_aeotec_keyfob_button:generate_test_message(
        "button1",
        capabilities.button.supportedButtonValues({"pushed", "held"}, {visibility = { displayed = false }})
      )
    )

    test.socket.capability:__expect_send(
      mock_aeotec_keyfob_button:generate_test_message(
        "button2",
        capabilities.button.numberOfButtons({ value = 1 }, { visibility = { displayed = false }})
      )
    )

    test.socket.capability:__expect_send(
      mock_aeotec_keyfob_button:generate_test_message(
        "button2",
        capabilities.button.supportedButtonValues({ "pushed", "held" }, { visibility = { displayed = false }})
      )
    )

    test.socket.capability:__expect_send(
      mock_aeotec_keyfob_button:generate_test_message(
        "button3",
        capabilities.button.numberOfButtons({ value = 1 }, { visibility = { displayed = false }})
      )
    )

    test.socket.capability:__expect_send(
      mock_aeotec_keyfob_button:generate_test_message(
        "button3",
        capabilities.button.supportedButtonValues({ "pushed", "held" }, { visibility = { displayed = false }})
      )
    )

    test.socket.capability:__expect_send(
      mock_aeotec_keyfob_button:generate_test_message(
        "button4",
        capabilities.button.numberOfButtons({ value = 1 }, { visibility = { displayed = false }})
      )
    )

    test.socket.capability:__expect_send(
      mock_aeotec_keyfob_button:generate_test_message(
        "button4",
        capabilities.button.supportedButtonValues({ "pushed", "held" }, { visibility = { displayed = false }})
      )
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_aeotec_keyfob_button,
        Battery:Get({})
      )
    )
  end
)

--configuration for fibaro keyfob
test.register_coroutine_test(
  "doConfigure lifecycle event should generate proper configuration command for fibaro keyfob device",
  function()
    test.socket.zwave:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({ mock_fibaro_keyfob_button.id, "doConfigure" })
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_fibaro_keyfob_button,
      Battery:Get({})
    ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_fibaro_keyfob_button,
          Configuration:Set({parameter_number = 21, size = 1, configuration_value = 15})
    ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_keyfob_button,
        Configuration:Set({parameter_number = 22, size = 1, configuration_value = 15})
    ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_keyfob_button,
        Configuration:Set({parameter_number = 23, size = 1, configuration_value = 15})
    ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_keyfob_button,
        Configuration:Set({parameter_number = 24, size = 1, configuration_value = 15})
    ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_keyfob_button,
        Configuration:Set({parameter_number = 25, size = 1, configuration_value = 15})
    ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_keyfob_button,
        Configuration:Set({parameter_number = 26, size = 1, configuration_value = 15})
    ))
    mock_fibaro_keyfob_button:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)

test.register_coroutine_test(
  "Device added event should make proper event for fibaro keyfob",
  function()
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({ mock_fibaro_keyfob_button.id, "added" })

    test.socket.capability:__expect_send(
      mock_fibaro_keyfob_button:generate_test_message(
        "main",
        capabilities.button.numberOfButtons({ value = 6 }, {visibility = { displayed = false }})
      )
    )

    test.socket.capability:__expect_send(
      mock_fibaro_keyfob_button:generate_test_message(
        "main",
        capabilities.button.supportedButtonValues({"pushed", "held", "double", "down_hold", "pushed_3x"}, {visibility = { displayed = false }})
      )
    )

    test.socket.capability:__expect_send(
      mock_fibaro_keyfob_button:generate_test_message(
        "button1",
        capabilities.button.numberOfButtons({ value = 1 }, {visibility = { displayed = false }})
      )
    )

    test.socket.capability:__expect_send(
      mock_fibaro_keyfob_button:generate_test_message(
        "button1",
        capabilities.button.supportedButtonValues({"pushed", "held", "double", "down_hold", "pushed_3x"}, {visibility = { displayed = false }})
      )
    )

    test.socket.capability:__expect_send(
      mock_fibaro_keyfob_button:generate_test_message(
        "button2",
        capabilities.button.numberOfButtons({ value = 1 }, { visibility = { displayed = false }})
      )
    )

    test.socket.capability:__expect_send(
      mock_fibaro_keyfob_button:generate_test_message(
        "button2",
        capabilities.button.supportedButtonValues({"pushed", "held", "double", "down_hold", "pushed_3x"}, { visibility = { displayed = false }})
      )
    )

    test.socket.capability:__expect_send(
      mock_fibaro_keyfob_button:generate_test_message(
        "button3",
        capabilities.button.numberOfButtons({ value = 1 }, { visibility = { displayed = false }})
      )
    )

    test.socket.capability:__expect_send(
      mock_fibaro_keyfob_button:generate_test_message(
        "button3",
        capabilities.button.supportedButtonValues({"pushed", "held", "double", "down_hold", "pushed_3x"}, { visibility = { displayed = false }})
      )
    )

    test.socket.capability:__expect_send(
      mock_fibaro_keyfob_button:generate_test_message(
        "button4",
        capabilities.button.numberOfButtons({ value = 1 }, { visibility = { displayed = false }})
      )
    )

    test.socket.capability:__expect_send(
      mock_fibaro_keyfob_button:generate_test_message(
        "button4",
        capabilities.button.supportedButtonValues({"pushed", "held", "double", "down_hold", "pushed_3x"}, { visibility = { displayed = false }})
      )
    )

    test.socket.capability:__expect_send(
      mock_fibaro_keyfob_button:generate_test_message(
        "button5",
        capabilities.button.numberOfButtons({ value = 1 }, { visibility = { displayed = false }})
      )
    )

    test.socket.capability:__expect_send(
      mock_fibaro_keyfob_button:generate_test_message(
        "button5",
        capabilities.button.supportedButtonValues({"pushed", "held", "double", "down_hold", "pushed_3x"}, { visibility = { displayed = false }})
      )
    )

    test.socket.capability:__expect_send(
      mock_fibaro_keyfob_button:generate_test_message(
        "button6",
        capabilities.button.numberOfButtons({ value = 1 }, { visibility = { displayed = false }})
      )
    )

    test.socket.capability:__expect_send(
      mock_fibaro_keyfob_button:generate_test_message(
        "button6",
        capabilities.button.supportedButtonValues({"pushed", "held", "double", "down_hold", "pushed_3x"}, { visibility = { displayed = false }})
      )
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_keyfob_button,
        Battery:Get({})
      )
    )
  end
)

test.register_coroutine_test(
  "Device added event should make proper event for aeotec wallmote quad",
  function()
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({ mock_aeotec_wallmote_quad.id, "added" })

    test.socket.capability:__expect_send(
      mock_aeotec_wallmote_quad:generate_test_message(
        "main",
        capabilities.button.numberOfButtons({ value = 4 }, {visibility = { displayed = false }})
      )
    )

    test.socket.capability:__expect_send(
      mock_aeotec_wallmote_quad:generate_test_message(
        "main",
        capabilities.button.supportedButtonValues({"pushed", "held"}, {visibility = { displayed = false }})
      )
    )

    test.socket.capability:__expect_send(
      mock_aeotec_wallmote_quad:generate_test_message(
        "button1",
        capabilities.button.numberOfButtons({ value = 1 }, {visibility = { displayed = false }})
      )
    )

    test.socket.capability:__expect_send(
      mock_aeotec_wallmote_quad:generate_test_message(
        "button1",
        capabilities.button.supportedButtonValues({"pushed", "held"}, {visibility = { displayed = false }})
      )
    )

    test.socket.capability:__expect_send(
      mock_aeotec_wallmote_quad:generate_test_message(
        "button2",
        capabilities.button.numberOfButtons({ value = 1 }, { visibility = { displayed = false }})
      )
    )

    test.socket.capability:__expect_send(
      mock_aeotec_wallmote_quad:generate_test_message(
        "button2",
        capabilities.button.supportedButtonValues({ "pushed", "held" }, { visibility = { displayed = false }})
      )
    )

    test.socket.capability:__expect_send(
      mock_aeotec_wallmote_quad:generate_test_message(
        "button3",
        capabilities.button.numberOfButtons({ value = 1 }, { visibility = { displayed = false }})
      )
    )

    test.socket.capability:__expect_send(
      mock_aeotec_wallmote_quad:generate_test_message(
        "button3",
        capabilities.button.supportedButtonValues({ "pushed", "held" }, { visibility = { displayed = false }})
      )
    )

    test.socket.capability:__expect_send(
      mock_aeotec_wallmote_quad:generate_test_message(
        "button4",
        capabilities.button.numberOfButtons({ value = 1 }, { visibility = { displayed = false }})
      )
    )

    test.socket.capability:__expect_send(
      mock_aeotec_wallmote_quad:generate_test_message(
        "button4",
        capabilities.button.supportedButtonValues({ "pushed", "held" }, { visibility = { displayed = false }})
      )
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_aeotec_wallmote_quad,
        Battery:Get({})
      )
    )
  end
)

test.register_coroutine_test(
  "Device added event should make proper event for everspring wall switch",
  function()
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({ mock_everspring.id, "added" })

    test.socket.capability:__expect_send(
      mock_everspring:generate_test_message(
        "main",
        capabilities.button.numberOfButtons({ value = 2 }, {visibility = { displayed = false }})
      )
    )

    test.socket.capability:__expect_send(
      mock_everspring:generate_test_message(
        "main",
        capabilities.button.supportedButtonValues({"pushed", "held", "double"}, {visibility = { displayed = false }})
      )
    )

    test.socket.capability:__expect_send(
      mock_everspring:generate_test_message(
        "button1",
        capabilities.button.numberOfButtons({ value = 1 }, {visibility = { displayed = false }})
      )
    )

    test.socket.capability:__expect_send(
      mock_everspring:generate_test_message(
        "button1",
        capabilities.button.supportedButtonValues({"pushed", "held", "double"}, {visibility = { displayed = false }})
      )
    )

    test.socket.capability:__expect_send(
      mock_everspring:generate_test_message(
        "button2",
        capabilities.button.numberOfButtons({ value = 1 }, { visibility = { displayed = false }})
      )
    )

    test.socket.capability:__expect_send(
      mock_everspring:generate_test_message(
        "button2",
        capabilities.button.supportedButtonValues({"pushed", "held", "double"}, { visibility = { displayed = false }})
      )
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
          mock_everspring,
          Battery:Get({})
      )
    )
  end
)

test.run_registered_tests()
