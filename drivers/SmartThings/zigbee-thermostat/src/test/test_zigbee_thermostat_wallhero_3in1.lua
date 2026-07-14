-- Copyright 2026 SmartThings
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
local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils = require "integration_test.utils"

local Scenes = clusters.Scenes
local OnOff = clusters.OnOff
local FanControl = clusters.FanControl
local Thermostat = clusters.Thermostat
local ThermostatMode  = capabilities.thermostatMode
local FanMode  = capabilities.fanMode
local button_attr = capabilities.button.button

local SUPPORTED_FAN_MODES = {
  { "auto", "high", "medium", "low"},
}

local mock_device = test.mock_device.build_test_zigbee_device(
  { profile = t_utils.get_profile_definition("thermostat-thirty-buttons-wallhero.yml"),
    zigbee_endpoints = {
      [0x01] = {
        id = 0x01,
        manufacturer = "WALL HERO",
        model = "ACL-403STC1",
        server_clusters = {  0x0005,0x0006,0x0201,0x0202, 0x0203 }
      }
    }
  }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device)
  zigbee_test_utils.init_noop_health_check_timer()
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "added lifecycle event",
  function()
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        ThermostatMode.supportedThermostatModes({"cool", "dryair", "fanonly", "heat"}, { visibility = { displayed = false } })
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        FanMode.supportedFanModes( SUPPORTED_FAN_MODES[1] , { visibility = { displayed = false }})
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "fan",
        FanMode.supportedFanModes( SUPPORTED_FAN_MODES[1] , { visibility = { displayed = false }})
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.temperatureSetpoint.temperatureSetpointRange({ value = { minimum = 16.00, maximum = 32.00 }, unit = "C" })
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "heat",
        capabilities.thermostatHeatingSetpoint.heatingSetpointRange({ value = { minimum = 16.00, maximum = 32.00 }, unit = "C" })
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.switch.switch.off()
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "heat",
        capabilities.switch.switch.off()
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "fan",
        capabilities.switch.switch.off()
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        ThermostatMode.thermostatMode.cool()
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        FanMode.fanMode.auto()
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "fan",
        FanMode.fanMode.auto()
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.temperatureSetpoint.temperatureSetpoint({value = 26, unit = "C"})
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "heat",
        capabilities.thermostatHeatingSetpoint.heatingSetpoint({value = 26, unit = "C"})
      )
    )

    for _, component in pairs(mock_device.profile.components) do
      if component.id ~= "main" and component.id ~= "heat" and component.id ~= "fan" then
        test.socket.capability:__expect_send(
          mock_device:generate_test_message(
            component.id,
            capabilities.button.supportedButtonValues({ "pushed" }, { visibility = { displayed = false } })
          )
        )
        test.socket.capability:__expect_send(
          mock_device:generate_test_message(
            component.id,
            capabilities.button.numberOfButtons({ value = 1 }, { visibility = { displayed = false } })
          )
        )
      end
    end

  test.socket.zigbee:__expect_send(
    {
    mock_device.id,
    OnOff.attributes.OnOff:read(mock_device):to_endpoint(0x01)
    }
  )
  test.socket.zigbee:__expect_send(
    {
    mock_device.id,
    Thermostat.attributes.LocalTemperature:read(mock_device):to_endpoint(0x01)
    }
  )
  test.socket.zigbee:__expect_send(
    {
    mock_device.id,
    Thermostat.attributes.OccupiedCoolingSetpoint:read(mock_device):to_endpoint(0x01)
    }
  )

  test.socket.zigbee:__expect_send(
    {
    mock_device.id,
    Thermostat.attributes.SystemMode:read(mock_device):to_endpoint(0x01)
    }
  )
  test.socket.zigbee:__expect_send(
    {
    mock_device.id,
    FanControl.attributes.FanMode:read(mock_device):to_endpoint(0x01)
    }
  )
  test.socket.zigbee:__expect_send(
    {
    mock_device.id,
    OnOff.attributes.OnOff:read(mock_device):to_endpoint(0x02)
    }
  )
  test.socket.zigbee:__expect_send(
    {
    mock_device.id,
    FanControl.attributes.FanMode:read(mock_device):to_endpoint(0x02)
    }
  )
  test.socket.zigbee:__expect_send(
    {
    mock_device.id,
    OnOff.attributes.OnOff:read(mock_device):to_endpoint(0x03)
    }
  )
  test.socket.zigbee:__expect_send(
    {
    mock_device.id,
    Thermostat.attributes.OccupiedHeatingSetpoint:read(mock_device):to_endpoint(0x03)
    }
  )
    test.socket:set_time_advance_per_select(0.1)
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
    test.wait_for_events()
  end,
  {
     min_api_version = 17
  }
)


test.register_message_test(
    "Reported on status should be handled: on ep 1",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, OnOff.attributes.OnOff:build_test_attr_report(mock_device,
                                                                                                true):from_endpoint(0x01) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main",  capabilities.switch.switch.on())
      }
    },
    {
       min_api_version = 17
    }
)

test.register_message_test(
    "Reported off status should be handled: off ep 1",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, OnOff.attributes.OnOff:build_test_attr_report(mock_device,
                                                                                                false):from_endpoint(0x01) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main",  capabilities.switch.switch.off())
      }
    },
    {
       min_api_version = 17
    }
)

test.register_message_test(
    "Temperature reports using the temperatureMeasurement should be handled : ep1",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, Thermostat.attributes.LocalTemperature:build_test_attr_report(mock_device,
                                                                                                  2500):from_endpoint(0x01) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.temperatureMeasurement.temperature({ value = 25.0, unit = "C" }))
      }
    },
    {
       min_api_version = 17
    }
)

test.register_message_test(
    "Cooling setpoint reports temperatureSetpoint are handled : ep1",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, Thermostat.attributes.OccupiedCoolingSetpoint:build_test_attr_report(mock_device,
                                                                                                         2500):from_endpoint(0x01) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.temperatureSetpoint.temperatureSetpoint({ value = 25.0, unit = "C" }))
      }
    },
    {
       min_api_version = 17
    }
)

test.register_message_test(
    "Thermostat running mode reports 3 cool are handled : ep1",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, Thermostat.attributes.ThermostatRunningMode:build_test_attr_report(mock_device,
                                                                                                        3):from_endpoint(0x01) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.thermostatMode.thermostatMode("cool"))
      }
    },
    {
       min_api_version = 17
    }
)

test.register_message_test(
    "Thermostat running mode reports 4 heat are handled : ep1",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, Thermostat.attributes.ThermostatRunningMode:build_test_attr_report(mock_device,
                                                                                                        4):from_endpoint(0x01) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.thermostatMode.thermostatMode("heat"))
      }
    },
    {
       min_api_version = 17
    }
)

test.register_message_test(
    "Thermostat running mode reports 8 dryair are handled : ep1",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, Thermostat.attributes.ThermostatRunningMode:build_test_attr_report(mock_device,
                                                                                                        8):from_endpoint(0x01) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.thermostatMode.thermostatMode("dryair"))
      }
    },
    {
       min_api_version = 17
    }
)

test.register_message_test(
    "Thermostat running mode reports 1 auto are handled : ep1",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, Thermostat.attributes.ThermostatRunningMode:build_test_attr_report(mock_device,
                                                                                                        1):from_endpoint(0x01) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.thermostatMode.thermostatMode("auto"))
      }
    },
    {
       min_api_version = 17
    }
)

test.register_message_test(
    "FanControl fan mode reports 1 low are handled : ep1",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, FanControl.attributes.FanMode:build_test_attr_report(mock_device,
                                                                                                1):from_endpoint(0x01) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.fanMode.fanMode("low"))
      }
    },
    {
       min_api_version = 17
    }
)

test.register_message_test(
    "FanControl fan mode reports 2 medium are handled : ep1",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, FanControl.attributes.FanMode:build_test_attr_report(mock_device,
                                                                                                2):from_endpoint(0x01) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.fanMode.fanMode("medium"))
      }
    },
    {
       min_api_version = 17
    }
)

test.register_message_test(
    "FanControl fan mode reports 3 high are handled : ep1",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, FanControl.attributes.FanMode:build_test_attr_report(mock_device,
                                                                                                3):from_endpoint(0x01) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.fanMode.fanMode("high"))
      }
    },
    {
       min_api_version = 17
    }
)

test.register_message_test(
    "FanControl fan mode reports 5 auto are handled : ep1",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, FanControl.attributes.FanMode:build_test_attr_report(mock_device,
                                                                                                5):from_endpoint(0x01) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.fanMode.fanMode("auto"))
      }
    },
    {
       min_api_version = 17
    }
)

test.register_message_test(
    "Reported on status should be handled: on ep 3",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, OnOff.attributes.OnOff:build_test_attr_report(mock_device,
                                                                                                true):from_endpoint(0x03) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("heat",  capabilities.switch.switch.on())
      }
    },
    {
       min_api_version = 17
    }
)

test.register_message_test(
    "Reported off status should be handled: off ep 3",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, OnOff.attributes.OnOff:build_test_attr_report(mock_device,
                                                                                                false):from_endpoint(0x03) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("heat",  capabilities.switch.switch.off())
      }
    },
    {
       min_api_version = 17
    }
)

test.register_message_test(
    "Heating setpoint reports  heatingSetpoint are handled : ep3",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, Thermostat.attributes.OccupiedHeatingSetpoint:build_test_attr_report(mock_device,
                                                                                                         2500):from_endpoint(0x03) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("heat", capabilities.thermostatHeatingSetpoint.heatingSetpoint({ value = 25.0, unit = "C" }))
      }
    },
    {
       min_api_version = 17
    }
)

test.register_message_test(
    "Reported on status should be handled: on ep 2",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, OnOff.attributes.OnOff:build_test_attr_report(mock_device,
                                                                                                true):from_endpoint(0x02) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("fan",  capabilities.switch.switch.on())
      }
    },
    {
       min_api_version = 17
    }
)

test.register_message_test(
    "Reported off status should be handled: off ep 2",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, OnOff.attributes.OnOff:build_test_attr_report(mock_device,
                                                                                                false):from_endpoint(0x02) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("fan",  capabilities.switch.switch.off())
      }
    },
    {
       min_api_version = 17
    }
)

test.register_message_test(
    "FanControl fan mode reports are handled : ep2",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, FanControl.attributes.FanMode:build_test_attr_report(mock_device,
                                                                                                1):from_endpoint(0x02) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("fan", capabilities.fanMode.fanMode("low"))
      }
    },
    {
       min_api_version = 17
    }
)

test.register_message_test(
    "FanControl fan mode reports are handled : ep2",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, FanControl.attributes.FanMode:build_test_attr_report(mock_device,
                                                                                                2):from_endpoint(0x02) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("fan", capabilities.fanMode.fanMode("medium"))
      }
    },
    {
       min_api_version = 17
    }
)

test.register_message_test(
    "FanControl fan mode reports are handled : ep2",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, FanControl.attributes.FanMode:build_test_attr_report(mock_device,
                                                                                                3):from_endpoint(0x02) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("fan", capabilities.fanMode.fanMode("high"))
      }
    },
    {
       min_api_version = 17
    }
)

test.register_message_test(
    "FanControl fan mode reports 5 auto are handled : ep2",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, FanControl.attributes.FanMode:build_test_attr_report(mock_device,
                                                                                                5):from_endpoint(0x02) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("fan", capabilities.fanMode.fanMode("auto"))
      }
    },
    {
       min_api_version = 17
    }
)

test.register_message_test(
    "Capability on command switch on should be handled : ep1",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_device.id, { capability = "switch", component = "main", command = "on", args = { } } }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_device.id, OnOff.server.commands.On(mock_device):to_endpoint(0x01) }
      }
    },
    {
       min_api_version = 17
    }
)

test.register_message_test(
    "Capability off command switch off should be handled : ep1",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_device.id, { capability = "switch", component = "main", command = "off", args = { } } }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_device.id, OnOff.server.commands.Off(mock_device):to_endpoint(0x01) }
      }
    },
    {
       min_api_version = 17
    }
)

test.register_message_test(
    "Capability on command switch on should be handled : ep3",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_device.id, { capability = "switch", component = "heat", command = "on", args = { } } }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_device.id, OnOff.server.commands.On(mock_device):to_endpoint(0x03) }
      }
    },
    {
       min_api_version = 17
    }
)

test.register_message_test(
    "Capability off command switch off should be handled : ep3",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_device.id, { capability = "switch", component = "heat", command = "off", args = { } } }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_device.id, OnOff.server.commands.Off(mock_device):to_endpoint(0x03) }
      }
    },
    {
       min_api_version = 17
    }
)

test.register_message_test(
    "Capability on command switch on should be handled : ep2",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_device.id, { capability = "switch", component = "fan", command = "on", args = { } } }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_device.id, OnOff.server.commands.On(mock_device):to_endpoint(0x02) }
      }
    },
    {
       min_api_version = 17
    }
)

test.register_message_test(
    "Capability off command switch off should be handled : ep2",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_device.id, { capability = "switch", component = "fan", command = "off", args = { } } }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_device.id, OnOff.server.commands.Off(mock_device):to_endpoint(0x02) }
      }
    },
    {
       min_api_version = 17
    }
)

test.register_message_test(
    "Capability temperatureSetpoint command setpoint 27 ep1",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_device.id, { capability = "temperatureSetpoint", component = "main", command = "setTemperatureSetpoint", args = { 27 } } }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_device.id, Thermostat.attributes.OccupiedCoolingSetpoint:write(mock_device, 2700):to_endpoint(0x01) }
      }
    },
    {
       min_api_version = 17
    }
)

test.register_message_test(
    "Capability thermostat command cool ep1",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_device.id, { capability = "thermostatMode", component = "main", command = "setThermostatMode", args = {"cool" } } }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_device.id, Thermostat.attributes.SystemMode:write(mock_device, 3):to_endpoint(0x01) }
      }
    },
    {
       min_api_version = 17
    }
)

test.register_message_test(
    "Capability thermostat command dryair ep1",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_device.id, { capability = "thermostatMode", component = "main", command = "setThermostatMode", args = {"dryair" } } }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_device.id, Thermostat.attributes.SystemMode:write(mock_device, 8):to_endpoint(0x01) }
      }
    },
    {
       min_api_version = 17
    }
)

test.register_message_test(
    "Capability thermostat command fanonly ep1",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_device.id, { capability = "thermostatMode", component = "main", command = "setThermostatMode", args = {"fanonly" } } }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_device.id, Thermostat.attributes.SystemMode:write(mock_device, 7):to_endpoint(0x01) }
      }
    },
    {
       min_api_version = 17
    }
)

test.register_message_test(
    "Capability thermostat command heat ep1",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_device.id, { capability = "thermostatMode", component = "main", command = "setThermostatMode", args = { "heat"} } }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_device.id, Thermostat.attributes.SystemMode:write(mock_device, 4):to_endpoint(0x01) }
      }
    },
    {
       min_api_version = 17
    }
)

test.register_message_test(
    "Capability fanMode command auto ep1",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_device.id, { capability = "fanMode", component = "main", command = "setFanMode", args = {"auto"} } }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_device.id, FanControl.attributes.FanMode:write(mock_device, 5):to_endpoint(0x01) }
      }
    },
    {
       min_api_version = 17
    }
)

test.register_message_test(
    "Capability fanMode command low ep1",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_device.id, { capability = "fanMode", component = "main", command = "setFanMode", args = {"low"} } }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_device.id, FanControl.attributes.FanMode:write(mock_device, 1):to_endpoint(0x01) }
      }
    },
    {
       min_api_version = 17
    }
)

test.register_message_test(
    "Capability fanMode command medium ep1",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_device.id, { capability = "fanMode", component = "main", command = "setFanMode", args = {"medium"} } }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_device.id, FanControl.attributes.FanMode:write(mock_device, 2):to_endpoint(0x01) }
      }
    },
    {
       min_api_version = 17
    }
)

test.register_message_test(
    "Capability fanMode command high ep1",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_device.id, { capability = "fanMode", component = "main", command = "setFanMode" , args = {"high"} } }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_device.id, FanControl.attributes.FanMode:write(mock_device, 3):to_endpoint(0x01) }
      }
    },
    {
       min_api_version = 17
    }
)

test.register_message_test(
    "Capability thermostatHeatingSetpoint command setHeatingSetpoint 27 ep3",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_device.id, { capability = "thermostatHeatingSetpoint", component = "heat", command = "setHeatingSetpoint", args = { 27 } } }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_device.id, Thermostat.attributes.OccupiedHeatingSetpoint:write(mock_device, 2700):to_endpoint(0x03) }
      }
    },
    {
       min_api_version = 17
    }
)

test.register_message_test(
    "Capability fanMode command auto ep2",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_device.id, { capability = "fanMode", component = "fan", command = "setFanMode", args = {"auto"} } }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_device.id, FanControl.attributes.FanMode:write(mock_device, 5):to_endpoint(0x02) }
      }
    },
    {
       min_api_version = 17
    }
)

test.register_message_test(
    "Capability fanMode command low ep2",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_device.id, { capability = "fanMode", component = "fan", command = "setFanMode", args = {"low"} } }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_device.id, FanControl.attributes.FanMode:write(mock_device, 1):to_endpoint(0x02) }
      }
    },
    {
       min_api_version = 17
    }
)

test.register_message_test(
    "Capability fanMode command medium ep2",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_device.id, { capability = "fanMode", component = "fan", command = "setFanMode", args = {"medium"} } }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_device.id, FanControl.attributes.FanMode:write(mock_device, 2):to_endpoint(0x02) }
      }
    },
    {
       min_api_version = 17
    }
)

test.register_message_test(
    "Capability fanMode command high ep2",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_device.id, { capability = "fanMode", component = "fan", command = "setFanMode" , args = {"high"} } }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_device.id, FanControl.attributes.FanMode:write(mock_device, 3):to_endpoint(0x02) }
      }
    },
    {
       min_api_version = 17
    }
)

test.register_coroutine_test(
  "RecallScene command should be handled",
  function()
    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, Scenes.ID, Scenes.server.commands.RecallScene.ID, 0x0000, "\x05\x00\x00\x00\x05\x00", 4) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button1", button_attr.pushed({ state_change = true }))
    )

    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, Scenes.ID, Scenes.server.commands.RecallScene.ID, 0x0000, "\x05\x00\x00\x00\x05\x00", 5) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button2", button_attr.pushed({ state_change = true }))
    )

    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, Scenes.ID, Scenes.server.commands.RecallScene.ID, 0x0000, "\x05\x00\x00\x00\x05\x00", 6) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button3", button_attr.pushed({ state_change = true }))
    )

    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, Scenes.ID, Scenes.server.commands.RecallScene.ID, 0x0000, "\x05\x00\x00\x00\x05\x00", 7) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button4", button_attr.pushed({ state_change = true }))
    )

    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, Scenes.ID, Scenes.server.commands.RecallScene.ID, 0x0000, "\x05\x00\x00\x00\x05\x00", 8) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button5", button_attr.pushed({ state_change = true }))
    )

    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, Scenes.ID, Scenes.server.commands.RecallScene.ID, 0x0000, "\x05\x00\x00\x00\x05\x00", 9) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button6", button_attr.pushed({ state_change = true }))
    )

    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, Scenes.ID, Scenes.server.commands.RecallScene.ID, 0x0000, "\x05\x00\x00\x00\x05\x00", 10) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button7", button_attr.pushed({ state_change = true }))
    )

    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, Scenes.ID, Scenes.server.commands.RecallScene.ID, 0x0000, "\x05\x00\x00\x00\x05\x00", 11) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button8", button_attr.pushed({ state_change = true }))
    )

    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, Scenes.ID, Scenes.server.commands.RecallScene.ID, 0x0000, "\x05\x00\x00\x00\x05\x00", 12) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button9", button_attr.pushed({ state_change = true }))
    )

    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, Scenes.ID, Scenes.server.commands.RecallScene.ID, 0x0000, "\x05\x00\x00\x00\x05\x00", 13) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button10", button_attr.pushed({ state_change = true }))
    )

    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, Scenes.ID, Scenes.server.commands.RecallScene.ID, 0x0000, "\x05\x00\x00\x00\x05\x00", 14) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button11", button_attr.pushed({ state_change = true }))
    )

    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, Scenes.ID, Scenes.server.commands.RecallScene.ID, 0x0000, "\x05\x00\x00\x00\x05\x00", 15) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button12", button_attr.pushed({ state_change = true }))
    )

    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, Scenes.ID, Scenes.server.commands.RecallScene.ID, 0x0000, "\x05\x00\x00\x00\x05\x00", 16) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button13", button_attr.pushed({ state_change = true }))
    )

    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, Scenes.ID, Scenes.server.commands.RecallScene.ID, 0x0000, "\x05\x00\x00\x00\x05\x00", 17) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button14", button_attr.pushed({ state_change = true }))
    )

    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, Scenes.ID, Scenes.server.commands.RecallScene.ID, 0x0000, "\x05\x00\x00\x00\x05\x00", 18) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button15", button_attr.pushed({ state_change = true }))
    )

    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, Scenes.ID, Scenes.server.commands.RecallScene.ID, 0x0000, "\x05\x00\x00\x00\x05\x00", 19) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button16", button_attr.pushed({ state_change = true }))
    )

    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, Scenes.ID, Scenes.server.commands.RecallScene.ID, 0x0000, "\x05\x00\x00\x00\x05\x00", 20) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button17", button_attr.pushed({ state_change = true }))
    )

    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, Scenes.ID, Scenes.server.commands.RecallScene.ID, 0x0000, "\x05\x00\x00\x00\x05\x00", 21) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button18", button_attr.pushed({ state_change = true }))
    )

    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, Scenes.ID, Scenes.server.commands.RecallScene.ID, 0x0000, "\x05\x00\x00\x00\x05\x00", 22) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button19", button_attr.pushed({ state_change = true }))
    )

    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, Scenes.ID, Scenes.server.commands.RecallScene.ID, 0x0000, "\x05\x00\x00\x00\x05\x00", 23) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button20", button_attr.pushed({ state_change = true }))
    )

    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, Scenes.ID, Scenes.server.commands.RecallScene.ID, 0x0000, "\x05\x00\x00\x00\x05\x00", 24) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button21", button_attr.pushed({ state_change = true }))
    )

    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, Scenes.ID, Scenes.server.commands.RecallScene.ID, 0x0000, "\x05\x00\x00\x00\x05\x00", 25) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button22", button_attr.pushed({ state_change = true }))
    )

    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, Scenes.ID, Scenes.server.commands.RecallScene.ID, 0x0000, "\x05\x00\x00\x00\x05\x00", 26) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button23", button_attr.pushed({ state_change = true }))
    )

    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, Scenes.ID, Scenes.server.commands.RecallScene.ID, 0x0000, "\x05\x00\x00\x00\x05\x00", 27) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button24", button_attr.pushed({ state_change = true }))
    )

    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, Scenes.ID, Scenes.server.commands.RecallScene.ID, 0x0000, "\x05\x00\x00\x00\x05\x00", 28) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button25", button_attr.pushed({ state_change = true }))
    )

    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, Scenes.ID, Scenes.server.commands.RecallScene.ID, 0x0000, "\x05\x00\x00\x00\x05\x00", 29) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button26", button_attr.pushed({ state_change = true }))
    )

    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, Scenes.ID, Scenes.server.commands.RecallScene.ID, 0x0000, "\x05\x00\x00\x00\x05\x00", 30) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button27", button_attr.pushed({ state_change = true }))
    )

    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, Scenes.ID, Scenes.server.commands.RecallScene.ID, 0x0000, "\x05\x00\x00\x00\x05\x00", 31) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button28", button_attr.pushed({ state_change = true }))
    )

    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, Scenes.ID, Scenes.server.commands.RecallScene.ID, 0x0000, "\x05\x00\x00\x00\x05\x00", 32) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button29", button_attr.pushed({ state_change = true }))
    )

    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, Scenes.ID, Scenes.server.commands.RecallScene.ID, 0x0000, "\x05\x00\x00\x00\x05\x00", 33) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button30", button_attr.pushed({ state_change = true }))
    )

    test.wait_for_events()
    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, Scenes.ID, Scenes.server.commands.RecallScene.ID, 0x0000, "\x05\x00\x00\x00\x05\x00", 34) })
    test.wait_for_events()
  end,
  {
     min_api_version = 17
  }
)

test.run_registered_tests()
