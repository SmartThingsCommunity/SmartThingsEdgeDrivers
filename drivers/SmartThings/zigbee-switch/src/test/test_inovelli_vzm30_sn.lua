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
local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local cluster_base = require "st.zigbee.cluster_base"
local utils = require "st.utils"
local OTAUpgrade = require("st.zigbee.zcl.clusters").OTAUpgrade
local device_management = require "st.zigbee.device_management"
local zigbee_constants = require "st.zigbee.constants"

local OnOff = clusters.OnOff
local Level = clusters.Level
local TemperatureMeasurement = clusters.TemperatureMeasurement
local RelativeHumidity = clusters.RelativeHumidity

-- Inovelli VZM30-SN device identifiers
local INOVELLI_MANUFACTURER_ID = "Inovelli"
local INOVELLI_VZM30_SN_MODEL = "VZM30-SN"

-- Device endpoints with supported clusters
local inovelli_vzm30_sn_endpoints = {
  [1] = {
    id = 1,
    manufacturer = INOVELLI_MANUFACTURER_ID,
    model = INOVELLI_VZM30_SN_MODEL,
    server_clusters = {0x0006, 0x0008, 0x0300, 0x0402, 0x0405} -- OnOff, Level, ColorControl, TemperatureMeasurement, RelativeHumidity
  }
}

local mock_inovelli_vzm30_sn = test.mock_device.build_test_zigbee_device({
  profile = t_utils.get_profile_definition("inovelli-vzm30-sn.yml"),
  zigbee_endpoints = inovelli_vzm30_sn_endpoints,
  fingerprinted_endpoint_id = 0x01
})

zigbee_test_utils.prepare_zigbee_env_info()

local function test_init()
  test.mock_device.add_test_device(mock_inovelli_vzm30_sn)
end
test.set_test_init_function(test_init)

local supported_button_values = {
    ["button1"] = {"pushed","held","down_hold","pushed_2x","pushed_3x","pushed_4x","pushed_5x"},
    ["button2"] = {"pushed","held","down_hold","pushed_2x","pushed_3x","pushed_4x","pushed_5x"},
    ["button3"] = {"pushed","held","down_hold","pushed_2x","pushed_3x","pushed_4x","pushed_5x"}
  }

-- Test device initialization
test.register_message_test(
  "Device should initialize properly on added lifecycle event",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_inovelli_vzm30_sn.id, "added" },
    },
    {
      channel = "zigbee",
      direction = "send",
      message = {
        mock_inovelli_vzm30_sn.id,
        Level.attributes.CurrentLevel:read(mock_inovelli_vzm30_sn)
      }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = {
        mock_inovelli_vzm30_sn.id,
        OnOff.attributes.OnOff:read(mock_inovelli_vzm30_sn)
      }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = {
        mock_inovelli_vzm30_sn.id,
        TemperatureMeasurement.attributes.MeasuredValue:read(mock_inovelli_vzm30_sn)
      }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = {
        mock_inovelli_vzm30_sn.id,
        RelativeHumidity.attributes.MeasuredValue:read(mock_inovelli_vzm30_sn)
      }
    },
  },
  {
    inner_block_ordering = "relaxed"
  }
)

-- Test refresh capability
test.register_message_test(
  "Refresh capability should send read commands",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_inovelli_vzm30_sn.id,
        { capability = "refresh", command = "refresh", args = {} }
      }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = { mock_inovelli_vzm30_sn.id, OnOff.attributes.OnOff:read(mock_inovelli_vzm30_sn) }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = { mock_inovelli_vzm30_sn.id, Level.attributes.CurrentLevel:read(mock_inovelli_vzm30_sn) }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = { mock_inovelli_vzm30_sn.id, TemperatureMeasurement.attributes.MeasuredValue:read(mock_inovelli_vzm30_sn) }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = { mock_inovelli_vzm30_sn.id, RelativeHumidity.attributes.MeasuredValue:read(mock_inovelli_vzm30_sn) }
    },
  },
  {
    inner_block_ordering = "relaxed"
  }
)

-- Test switch on command
test.register_message_test(
  "Switch on command should send OnOff On command",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_inovelli_vzm30_sn.id,
        { capability = "switch", command = "on", args = {} }
      }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = { mock_inovelli_vzm30_sn.id, clusters.OnOff.server.commands.On(mock_inovelli_vzm30_sn) }
    },
  },
  {
    inner_block_ordering = "relaxed"
  }
)

-- Test switch off command
test.register_message_test(
  "Switch off command should send OnOff Off command",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_inovelli_vzm30_sn.id,
        { capability = "switch", command = "off", args = {} }
      }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = { mock_inovelli_vzm30_sn.id, clusters.OnOff.server.commands.Off(mock_inovelli_vzm30_sn) }
    },
  },
  {
    inner_block_ordering = "relaxed"
  }
)

-- Test switch level command
test.register_message_test(
  "Switch level command should send Level MoveToLevelWithOnOff command",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_inovelli_vzm30_sn.id,
        { capability = "switchLevel", command = "setLevel", args = { 50 } }
      }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = {
        mock_inovelli_vzm30_sn.id,
        clusters.Level.server.commands.MoveToLevelWithOnOff(mock_inovelli_vzm30_sn, math.floor(50/100.0 * 254), 0xFFFF)
      }
    },
  },
  {
    inner_block_ordering = "relaxed"
  }
)

-- Build test message for Inovelli private cluster button press
local function build_inovelli_button_message(device, button_number, key_attribute)
  local messages = require "st.zigbee.messages"
  local zcl_messages = require "st.zigbee.zcl"
  local zb_const = require "st.zigbee.constants"
  local data_types = require "st.zigbee.data_types"
  local frameCtrl = require "st.zigbee.zcl.frame_ctrl"

  -- Combine button_number and key_attribute into a single value
  -- button_number in lower byte, key_attribute in upper byte
  local combined_value = (key_attribute * 256) + button_number

  -- Create the command body using serialize_int
  local command_body = zcl_messages.ZclMessageBody({
    zcl_header = zcl_messages.ZclHeader({
      frame_ctrl = frameCtrl(0x15), -- Manufacturer specific, client to server
      mfg_code = data_types.Uint16(0x122F), -- Inovelli manufacturer code
      seqno = data_types.Uint8(0x6D),
      cmd = data_types.ZCLCommandId(0x00) -- Scene command
    }),
    zcl_body = data_types.Uint16(combined_value)
  })

  local addrh = messages.AddressHeader(
    device:get_short_address(),
    0x02, -- src_endpoint from real device log
    zb_const.HUB.ADDR,
    zb_const.HUB.ENDPOINT,
    zb_const.HA_PROFILE_ID,
    0xFC31 -- PRIVATE_CLUSTER_ID
  )

  return messages.ZigbeeMessageRx({
    address_header = addrh,
    body = command_body
  })
end

-- Test button1 pushed
test.register_message_test(
  "Button1 pushed should emit button event",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_inovelli_vzm30_sn.id, build_inovelli_button_message(mock_inovelli_vzm30_sn, 0x01, 0x00) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_inovelli_vzm30_sn:generate_test_message("button1", capabilities.button.button.pushed({ state_change = true }))
    }
  }
)

-- Test button2 pressed 4 times
test.register_message_test(
  "Button2 pressed 4 times should emit button event",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_inovelli_vzm30_sn.id, build_inovelli_button_message(mock_inovelli_vzm30_sn, 0x02, 0x05) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_inovelli_vzm30_sn:generate_test_message("button2", capabilities.button.button.pushed_4x({ state_change = true }))
    }
  }
)

-- Test temperature measurement
test.register_message_test(
  "Temperature measurement should emit temperature events",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = {
        mock_inovelli_vzm30_sn.id,
        TemperatureMeasurement.attributes.MeasuredValue:build_test_attr_report(mock_inovelli_vzm30_sn, 2500)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_inovelli_vzm30_sn:generate_test_message("main", capabilities.temperatureMeasurement.temperature({value = 25.0, unit = "C"}))
    }
  }
)

-- Test humidity measurement
test.register_message_test(
  "Humidity measurement should emit humidity events",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = {
        mock_inovelli_vzm30_sn.id,
        RelativeHumidity.attributes.MeasuredValue:build_test_attr_report(mock_inovelli_vzm30_sn, 6500)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_inovelli_vzm30_sn:generate_test_message("main", capabilities.relativeHumidityMeasurement.humidity(65))
    }
  }
)

-- Test power meter from ElectricalMeasurement
test.register_coroutine_test(
  "Power meter from ElectricalMeasurement should emit power events",
  function()
    -- Set the divisor field (default handlers use 10 if not set, but we can set it for consistency)
    -- The default handler will use 10 if ELECTRICAL_MEASUREMENT_DIVISOR_KEY is not set
    -- Since the test expects 2000 -> 200.0 W, that means divisor of 10 is being used
    mock_inovelli_vzm30_sn:set_field(zigbee_constants.ELECTRICAL_MEASUREMENT_DIVISOR_KEY, 10, {persist = true})

    test.socket.zigbee:__queue_receive({
      mock_inovelli_vzm30_sn.id,
      clusters.ElectricalMeasurement.attributes.ActivePower:build_test_attr_report(mock_inovelli_vzm30_sn, 2000)
    })
    test.socket.capability:__expect_send(
      mock_inovelli_vzm30_sn:generate_test_message("main", capabilities.powerMeter.power({value = 200.0, unit = "W"}))
    )
  end
)

-- Test energy meter
test.register_coroutine_test(
  "Energy meter should emit energy events",
  function()
    -- Set the divisor field as the device does during configuration
    -- For VZM30-SN, the divisor is set to 1000 (like VZM32-SN)
    mock_inovelli_vzm30_sn:set_field(zigbee_constants.SIMPLE_METERING_DIVISOR_KEY, 1000, {persist = true})
    
    test.socket.zigbee:__queue_receive({
      mock_inovelli_vzm30_sn.id,
      clusters.SimpleMetering.attributes.CurrentSummationDelivered:build_test_attr_report(mock_inovelli_vzm30_sn, 212)
    })
    test.socket.capability:__expect_send(
      mock_inovelli_vzm30_sn:generate_test_message("main", capabilities.energyMeter.energy({value = 0.212, unit = "kWh"}))
    )
  end
)

-- Test energy meter reset command
test.register_message_test(
  "Energy meter reset command should send reset commands",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_inovelli_vzm30_sn.id,
        { capability = "energyMeter", command = "resetEnergyMeter", args = {} }
      }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = {
        mock_inovelli_vzm30_sn.id,
        cluster_base.build_manufacturer_specific_command(
          mock_inovelli_vzm30_sn,
          0xFC31, -- PRIVATE_CLUSTER_ID
          0x02,   -- PRIVATE_CMD_ENERGY_RESET_ID
          0x122F, -- MFG_CODE
          utils.serialize_int(0, 1, false, false)
        )
      }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = {
        mock_inovelli_vzm30_sn.id,
        clusters.SimpleMetering.attributes.CurrentSummationDelivered:read(mock_inovelli_vzm30_sn)
      }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = {
        mock_inovelli_vzm30_sn.id,
        clusters.ElectricalMeasurement.attributes.ActivePower:read(mock_inovelli_vzm30_sn)
      }
    }
  },
  {
    inner_block_ordering = "relaxed"
  }
)


test.register_coroutine_test(
  "doConfigure runs base + VZM30 extras",
  function()
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({ mock_inovelli_vzm30_sn.id, "doConfigure" })
    
    -- Button capability messages from base_device_configure
    for _, component in pairs(mock_inovelli_vzm30_sn.profile.components) do
      if component.id ~= "main" then
        test.socket.capability:__expect_send(
          mock_inovelli_vzm30_sn:generate_test_message(
            component.id,
            capabilities.button.supportedButtonValues(
              supported_button_values[component.id],
              { visibility = { displayed = false } }
            )
          )
        )
        test.socket.capability:__expect_send(
          mock_inovelli_vzm30_sn:generate_test_message(
            component.id,
            capabilities.button.numberOfButtons({value = 1}, { visibility = { displayed = false } })
          )
        )
      end
    end
    
    -- device:configure() sends bind requests and configure reporting (default handler)
    test.socket.zigbee:__expect_send({ mock_inovelli_vzm30_sn.id, require("integration_test.zigbee_test_utils").build_bind_request(mock_inovelli_vzm30_sn, require("integration_test.zigbee_test_utils").mock_hub_eui, clusters.Level.ID) })
    test.socket.zigbee:__expect_send({ mock_inovelli_vzm30_sn.id, clusters.Level.attributes.CurrentLevel:configure_reporting(mock_inovelli_vzm30_sn, 1, 3600, 1) })
    test.socket.zigbee:__expect_send({ mock_inovelli_vzm30_sn.id, device_management.build_bind_request(mock_inovelli_vzm30_sn, RelativeHumidity.ID, require("integration_test.zigbee_test_utils").mock_hub_eui) })
    test.socket.zigbee:__expect_send({ mock_inovelli_vzm30_sn.id, RelativeHumidity.attributes.MeasuredValue:configure_reporting(mock_inovelli_vzm30_sn, 30, 3600, 100) })
    test.socket.zigbee:__expect_send({ mock_inovelli_vzm30_sn.id, require("integration_test.zigbee_test_utils").build_bind_request(mock_inovelli_vzm30_sn, require("integration_test.zigbee_test_utils").mock_hub_eui, clusters.OnOff.ID) })
    test.socket.zigbee:__expect_send({ mock_inovelli_vzm30_sn.id, clusters.OnOff.attributes.OnOff:configure_reporting(mock_inovelli_vzm30_sn, 0, 300) })
    test.socket.zigbee:__expect_send({ mock_inovelli_vzm30_sn.id, device_management.build_bind_request(mock_inovelli_vzm30_sn, TemperatureMeasurement.ID, require("integration_test.zigbee_test_utils").mock_hub_eui) })
    test.socket.zigbee:__expect_send({ mock_inovelli_vzm30_sn.id, TemperatureMeasurement.attributes.MeasuredValue:configure_reporting(mock_inovelli_vzm30_sn, 30, 600, 100) })
    
    -- base_device_configure sends OTA ImageNotify and private cluster bind
    test.socket.zigbee:__expect_send({ mock_inovelli_vzm30_sn.id, OTAUpgrade.commands.ImageNotify(mock_inovelli_vzm30_sn, 0x00, 100, 0x122F, 0xFFFF, 0xFFFFFFFF) })
    test.socket.zigbee:__expect_send({ mock_inovelli_vzm30_sn.id, device_management.build_bind_request(mock_inovelli_vzm30_sn, 0xFC31, require("integration_test.zigbee_test_utils").mock_hub_eui, 2) })
    
    -- Read divisors/multipliers
    test.socket.zigbee:__expect_send({ mock_inovelli_vzm30_sn.id, clusters.SimpleMetering.attributes.Multiplier:read(mock_inovelli_vzm30_sn) })
    test.socket.zigbee:__expect_send({ mock_inovelli_vzm30_sn.id, clusters.ElectricalMeasurement.attributes.ACPowerDivisor:read(mock_inovelli_vzm30_sn) })
    test.socket.zigbee:__expect_send({ mock_inovelli_vzm30_sn.id, clusters.ElectricalMeasurement.attributes.ACPowerMultiplier:read(mock_inovelli_vzm30_sn) })
    
    -- VZM30-specific: temperature and humidity reporting configuration
    test.socket.zigbee:__expect_send({ mock_inovelli_vzm30_sn.id, TemperatureMeasurement.attributes.MeasuredValue:configure_reporting(mock_inovelli_vzm30_sn, 30, 3600, 50) })
    test.socket.zigbee:__expect_send({ mock_inovelli_vzm30_sn.id, RelativeHumidity.attributes.MeasuredValue:configure_reporting(mock_inovelli_vzm30_sn, 30, 3600, 50) })
    
    mock_inovelli_vzm30_sn:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)

test.run_registered_tests()
