-- Copyright 2025 SmartThings
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
local zigbee_test_utils = require "integration_test.zigbee_test_utils"

local clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local capabilities = require "st.capabilities"
local utils = require "st.utils"
local OnOff = clusters.OnOff
local ColorControl = clusters.ColorControl
local Level = clusters.Level

local PRI_CLU = 0xFCC0
local PRI_ATTR = 0x0009
local MFG_CODE = 0x115F
local OP_MODE_ATTR = 0x0509
local COMPONENT_MODE = "mode"
local SUPPORTED_MODES = { "rgbw", "cct" }
local CONVERSION_CONSTANT = 1000000
local CURRENT_X = "current_x_value"
local CURRENT_Y = "current_y_value"
local Y_TRISTIMULUS_VALUE = "y_tristimulus_value"

local mock_device = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("aqara-lightstrip-rgbw.yml"),
    fingerprinted_endpoint_id = 0x01,
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "LUMI",
        model = "lumi.dimmer.rcbac1",
        server_clusters = { 0x0006, 0x0008, 0x0300 }
      }
    }
  }
)

zigbee_test_utils.prepare_zigbee_env_info()

local function test_init()
  test.mock_device.add_test_device(mock_device)
end

test.set_test_init_function(test_init)

-- device_added
test.register_coroutine_test(
  "Handle added lifecycle",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        COMPONENT_MODE,
        capabilities.mode.supportedModes(SUPPORTED_MODES, { visibility = { displayed = false } })
      )
    )
    test.socket.zigbee:__expect_send({ mock_device.id, cluster_base.write_manufacturer_specific_attribute(mock_device,
    PRI_CLU, PRI_ATTR, MFG_CODE, data_types.Uint8, 1) })
    test.socket.zigbee:__expect_send({ mock_device.id, cluster_base.read_manufacturer_specific_attribute(mock_device,
    PRI_CLU, OP_MODE_ATTR, MFG_CODE)})
  end
)

-- device_info_changed
test.register_coroutine_test(
  "Configure should configure all necessary attributes and refresh device",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
    test.socket.zigbee:__set_channel_ordering("relaxed")

    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, OnOff.ID)
    })
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        OnOff.attributes.OnOff:configure_reporting(mock_device, 0, 300, 1)
      }
    )
    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, Level.ID)
    })
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        Level.attributes.CurrentLevel:configure_reporting(mock_device, 1, 3600, 1)
      }
    )
    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, ColorControl.ID)
    })
    test.socket.zigbee:__expect_send({
        mock_device.id,
        ColorControl.attributes.ColorTemperatureMireds:configure_reporting(mock_device, 1, 3600, 16)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      ColorControl.attributes.CurrentSaturation:configure_reporting(mock_device, 1, 3600, 16):to_endpoint(0x01)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      ColorControl.attributes.CurrentHue:configure_reporting(mock_device, 1, 3600, 16):to_endpoint(0x01)
    })

    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, OnOff.ID, 0x01)
    })

    test.socket.zigbee:__expect_send({ mock_device.id, OnOff.attributes.OnOff:read(mock_device):to_endpoint(0x01) })
    test.socket.zigbee:__expect_send({ mock_device.id, Level.attributes.CurrentLevel:read(mock_device):to_endpoint(0x01) })
    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.ColorTemperatureMireds:read(mock_device):to_endpoint(0x01) })
    test.socket.zigbee:__expect_send({ mock_device.id, OnOff.attributes.OnOff:read(mock_device):to_endpoint(0x02) })
    test.socket.zigbee:__expect_send({ mock_device.id, Level.attributes.CurrentLevel:read(mock_device):to_endpoint(0x02) })
    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.ColorTemperatureMireds:read(mock_device):to_endpoint(0x02) })

    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)

-- set_restore_powerState
test.register_coroutine_test(
  "Handle restorePowerState in infochanged",
  function()
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({
      preferences = { ["stse.restorePowerState"] = true }
    }))
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRI_CLU,
        0x0201, MFG_CODE, data_types.Boolean, true) })
  end
)

-- set_light_fadeInTimeState
test.register_coroutine_test(
  "Handle lightFadeInTimeInSec in infochanged",
  function()
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({
      preferences = { ["stse.lightFadeInTimeInSec"] = 1 }
    }))
    test.socket.zigbee:__expect_send({ mock_device.id, Level.attributes.OnTransitionTime:write(mock_device, 10):to_endpoint(0x01) })
    test.socket.zigbee:__expect_send({ mock_device.id, Level.attributes.OnTransitionTime:write(mock_device, 10):to_endpoint(0x02) })
  end
)
-- set_light_fadeOutTimeState
test.register_coroutine_test(
  "Handle lightFadeOutTimeInSec in infochanged",
  function()
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({
      preferences = { ["stse.lightFadeOutTimeInSec"] = 1 }
    }))
    test.socket.zigbee:__expect_send({ mock_device.id, Level.attributes.OffTransitionTime:write(mock_device, 10):to_endpoint(0x01)})
    test.socket.zigbee:__expect_send({ mock_device.id, Level.attributes.OffTransitionTime:write(mock_device, 10):to_endpoint(0x02)})
  end
)

-- switch_on_handler
test.register_coroutine_test(
  "Switch On handler test",
  function()
    test.socket.capability:__queue_receive({ mock_device.id,
      { capability = "switch", component = "main", command = "on", args = {} } })
    test.socket.zigbee:__expect_send({ mock_device.id,
      OnOff.server.commands.On(mock_device):to_endpoint(0x01)})
    test.socket.zigbee:__expect_send({ mock_device.id,
      OnOff.server.commands.On(mock_device):to_endpoint(0x02)})
  end
)
-- switch_off_handler
test.register_coroutine_test(
  "Switch Off handler test",
  function()
    test.socket.capability:__queue_receive({ mock_device.id,
      { capability = "switch", component = "main", command = "off", args = {} } })
    test.socket.zigbee:__expect_send({ mock_device.id,
      OnOff.server.commands.Off(mock_device):to_endpoint(0x01)})
    test.socket.zigbee:__expect_send({ mock_device.id,
      OnOff.server.commands.Off(mock_device):to_endpoint(0x02)})
  end
)

-- set_level_handler
test.register_coroutine_test(
  "Set Level handler test",
  function()
    test.socket.capability:__queue_receive({ mock_device.id,
      { capability = "switchLevel", component = "main", command = "setLevel", args = { 50 }}})
    local level = math.floor(50 / 100.0 * 254)
    test.socket.zigbee:__expect_send({ mock_device.id,
      Level.commands.MoveToLevelWithOnOff(mock_device, level):to_endpoint(0x01)})
    test.socket.zigbee:__expect_send({ mock_device.id,
      Level.commands.MoveToLevelWithOnOff(mock_device, level):to_endpoint(0x02)})
  end
)

-- set_color_temp_handler
test.register_coroutine_test(
  "Set ColorTemperature handler test",
  function()
    test.socket.capability:__queue_receive({ mock_device.id,
      { capability = "colorTemperature", component = "main", command = "setColorTemperature", args = { 4000 }}})
    local temp_in_mired = utils.round(1000000 / 4000)
    test.socket.zigbee:__expect_send({ mock_device.id,
      ColorControl.commands.MoveToColorTemperature(mock_device, temp_in_mired):to_endpoint(0x01)})
    test.socket.zigbee:__expect_send({ mock_device.id,
      ColorControl.commands.MoveToColorTemperature(mock_device, temp_in_mired):to_endpoint(0x02)})
  end
)

-- set_color_handler
test.register_coroutine_test(
  "Set Color command test",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.socket.capability:__queue_receive({mock_device.id, { capability = "colorControl", component = "main", command = "setColor", args = { { hue = 75, saturation = 65 } } } })

    test.socket.zigbee:__expect_send({ mock_device.id, OnOff.server.commands.On(mock_device) })

    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        ColorControl.commands.MoveToColor(mock_device, 0x3E51, 0x255D, 0x0000)
      }
    )

    test.wait_for_events()

    test.mock_time.advance_time(2)
    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.CurrentX:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.CurrentY:read(mock_device) })
  end
)

-- set_mode_handler
test.register_coroutine_test(
  "Set Mode handler test - RGBW Mode",
  function()
    test.socket.capability:__queue_receive({ mock_device.id,
      { capability = "mode", component = "main", command = "setMode", args = { "rgbw" }}})
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRI_CLU, 0x0509, MFG_CODE, data_types.Uint32, 3) })
  end
)
test.register_coroutine_test(
  "Set Mode handler test - Color Temperature Mode",
  function()
    test.socket.capability:__queue_receive({ mock_device.id,
      { capability = "mode", component = "main", command = "setMode", args = { "cct" }}})
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRI_CLU, 0x0509, MFG_CODE, data_types.Uint32, 1) })
  end
)

-- do_refresh
test.register_coroutine_test(
  "Refresh handler test",
  function()
    test.socket.capability:__queue_receive({ mock_device.id,
      { capability = "refresh", component = "main", command = "refresh", args = {}}})
    test.socket.zigbee:__expect_send({ mock_device.id, OnOff.attributes.OnOff:read(mock_device):to_endpoint(0x01) })
    test.socket.zigbee:__expect_send({ mock_device.id, Level.attributes.CurrentLevel:read(mock_device):to_endpoint(0x01) })
    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.ColorTemperatureMireds:read(mock_device):to_endpoint(0x01) })
    test.socket.zigbee:__expect_send({ mock_device.id, OnOff.attributes.OnOff:read(mock_device):to_endpoint(0x02) })
    test.socket.zigbee:__expect_send({ mock_device.id, Level.attributes.CurrentLevel:read(mock_device):to_endpoint(0x02) })
    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.ColorTemperatureMireds:read(mock_device):to_endpoint(0x02) })
  end
)

-- onoff_handler
test.register_coroutine_test(
  "OnOff handler test",
  function()
    -- Setup: switch to RGBW mode so handler won't try to emit to non-existent lamp1
    local attr_report_data = { { OP_MODE_ATTR, 0x23, 0x03 } }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRI_CLU, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("mode", capabilities.mode.mode("rgbw")))
    mock_device:expect_metadata_update({ profile = "aqara-lightstrip-rgbw" })

    test.socket.zigbee:__queue_receive({ mock_device.id, OnOff.attributes.OnOff:build_test_attr_report(mock_device, true) })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.switch.switch.on()))
  end
)

-- current_level_handler
test.register_coroutine_test(
  "CurrentLevel handler test",
  function()
    local attr_report_data = { { OP_MODE_ATTR, 0x23, 0x03 } }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRI_CLU, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("mode", capabilities.mode.mode("rgbw")))
    mock_device:expect_metadata_update({ profile = "aqara-lightstrip-rgbw" })

    test.socket.zigbee:__queue_receive({mock_device.id, Level.attributes.CurrentLevel:build_test_attr_report(mock_device, math.floor(50 / 100 * 254))})
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.switchLevel.level(50)))
  end
)

-- current_color_temp_mireds_handler
test.register_coroutine_test(
  "CurrentColor handler test",
  function()
    local attr_report_data = { { OP_MODE_ATTR, 0x23, 0x03 } }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRI_CLU, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("mode", capabilities.mode.mode("rgbw")))
    mock_device:expect_metadata_update({ profile = "aqara-lightstrip-rgbw" })

    test.socket.zigbee:__queue_receive({mock_device.id, ColorControl.attributes.ColorTemperatureMireds:build_test_attr_report(mock_device,
        utils.clamp_value(utils.round(CONVERSION_CONSTANT / 6500), 2700, 6500))})
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.colorTemperature.colorTemperature(2700)))
  end
)

-- current_x_attr_handler
test.register_coroutine_test(
  "CurrentX attr handler test",
  function()
    mock_device:set_field(CURRENT_Y, 9565)
    mock_device:set_field(Y_TRISTIMULUS_VALUE, 0.23191276511572)
    test.socket.zigbee:__queue_receive({ mock_device.id, ColorControl.attributes.CurrentX:build_test_attr_report(mock_device, 15953) })

    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.colorControl.hue(75)))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.colorControl.saturation(65)))
  end
)

-- current_y_attr_handler
test.register_coroutine_test(
  "CurrentY attr handler test",
  function()
    mock_device:set_field(CURRENT_X, 15953)
    mock_device:set_field(Y_TRISTIMULUS_VALUE, 0.23191276511572)
    test.socket.zigbee:__queue_receive({ mock_device.id, ColorControl.attributes.CurrentY:build_test_attr_report(mock_device, 9565) })

    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.colorControl.hue(75)))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.colorControl.saturation(65)))
  end
)

-- op_mode_handler
test.register_coroutine_test(
  "changePluginMode handled",
  function()
    local attr_report_data = {
      { OP_MODE_ATTR, 0x23, 0x03 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRI_CLU, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("mode", capabilities.mode.mode("rgbw")))
    mock_device:expect_metadata_update({ profile = "aqara-lightstrip-rgbw" })
  end
)

test.run_registered_tests()
