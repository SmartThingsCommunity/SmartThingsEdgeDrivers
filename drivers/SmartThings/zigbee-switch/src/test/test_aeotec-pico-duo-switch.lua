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
local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils = require "integration_test.utils"

local OnOff = clusters.OnOff
local SimpleMetering = clusters.SimpleMetering
local ElectricalMeasurement = clusters.ElectricalMeasurement
local Alarm = clusters.Alarms
local DeviceTemperatureConfiguration = clusters.DeviceTemperatureConfiguration
local Scenes = clusters.Scenes

local LAST_REPORT_TIME = "LAST_REPORT_TIME"
local PRIVATE_CLUSTER_ID = 0xFD00
local MFG_CODE = 0x1310

local PREFERENCE_TABLES = {
  s1LocalControlMode = {
    clusterId = PRIVATE_CLUSTER_ID,
    attributeId = 0x0011,
    mfgCode = MFG_CODE,
    dataType = data_types.Enum8,
    payload = 0,
    ep = 0x03
  },
  s2LocalControlMode = {
    clusterId = PRIVATE_CLUSTER_ID,
    attributeId = 0x0011,
    mfgCode = MFG_CODE,
    dataType = data_types.Enum8,
    payload = 0,
    ep = 0x04
  },
  s1Actions = {
    clusterId = PRIVATE_CLUSTER_ID,
    attributeId = 0x0010,
    mfgCode = MFG_CODE,
    dataType = data_types.Enum8,
    payload = 1,
    ep = 0x03
  },
  s2Actions = {
    clusterId = PRIVATE_CLUSTER_ID,
    attributeId = 0x0010,
    mfgCode = MFG_CODE,
    dataType = data_types.Enum8,
    payload = 1,
    ep = 0x04
  },
  s1ExternalSwitchConfig = {
    clusterId = PRIVATE_CLUSTER_ID,
    attributeId = 0x0000,
    mfgCode = MFG_CODE,
    dataType = data_types.Enum8,
    payload = 4,
    ep = 0x03
  },
  s2ExternalSwitchConfig = {
    clusterId = PRIVATE_CLUSTER_ID,
    attributeId = 0x0000,
    mfgCode = MFG_CODE,
    dataType = data_types.Enum8,
    payload = 4,
    ep = 0x04
  }
}

local SCENE_ID_BUTTON_EVENT_MAP = {
  { state_name = "pushed",    button_state = capabilities.button.button.pushed },
  { state_name = "double",    button_state = capabilities.button.button.double },
  { state_name = "pushed_3x", button_state = capabilities.button.button.pushed_3x },
  { state_name = "held",      button_state = capabilities.button.button.held },
  { state_name = "up",        button_state = capabilities.button.button.up }
}

local profile = t_utils.get_profile_definition("aeotec-pico-switch.yml")
local childProfile = t_utils.get_profile_definition("switch-scenes-power-energy-consumption-report-aeotec.yml")

local mock_device = test.mock_device.build_test_zigbee_device(
    {
    label = "Aeotec Pico Duo Switch",
      profile = profile,
      zigbee_endpoints = {
        [1] = {
          id = 1,
          manufacturer = "AEOTEC",
          model = "ZGA003",
          server_clusters = { 0x0006 }
        }
      },
      fingerprinted_endpoint_id = 0x01
    }
)

local mock_parent_device = test.mock_device.build_test_zigbee_device(
    {
    profile = childProfile,
      zigbee_endpoints = {
        [1] = {
          id = 1,
          manufacturer = "AEOTEC",
          model = "ZGA003",
          server_clusters = { 0x0006 }
        }
      },
      fingerprinted_endpoint_id = 0x01
    }
)

local mock_child_device = test.mock_device.build_test_child_device({
  profile = childProfile,
  device_network_id = string.format("%04X:%02X", mock_parent_device:get_short_address(), 2),
  parent_device_id = mock_parent_device.id,
  parent_assigned_child_key = string.format("%02X", 2)
})

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device)
  test.mock_device.add_test_device(mock_parent_device)
  test.mock_device.add_test_device(mock_child_device)
  zigbee_test_utils.init_noop_health_check_timer()
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "added lifecycle event should create children in parent device",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
    mock_device:expect_device_create({
      type = "EDGE_CHILD",
      label = "Aeotec Pico Duo Switch (CH2)",
      profile = "switch-scenes-power-energy-consumption-report-aeotec",
      parent_device_id = mock_device.id,
      parent_assigned_child_key = "02"
    })

    -- do refresh
    test.socket.zigbee:__expect_send({
      mock_device.id,
      OnOff.attributes.OnOff:read(mock_device)
    })

    test.socket.zigbee:__expect_send({
      mock_device.id,
      ElectricalMeasurement.attributes.RMSCurrent:read(mock_device)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      ElectricalMeasurement.attributes.RMSVoltage:read(mock_device)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      Alarm.attributes.AlarmCount:read(mock_device)
    })
  end
)

for i, button_event in ipairs(SCENE_ID_BUTTON_EVENT_MAP) do
  -- i = scene_id and goes from 0x01 to 0x05
  test.register_message_test(
    "Test Scene Control: Parent device - ".. button_event.state_name,
    {
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
        message = mock_device:generate_test_message("main",
          button_event.button_state({ state_change = true }))
      }
    }
  )
end

for i , button_event in ipairs(SCENE_ID_BUTTON_EVENT_MAP) do
  -- i = scene_id + offset of '5' and goes from 0x06 to 0x0A
  test.register_message_test(
    "Test Scene Control: Child device - " .. button_event.state_name,
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id,
          zigbee_test_utils.build_custom_command_id(mock_device, Scenes.ID, Scenes.server.commands.RecallScene.ID, 0x0000,
            "\x00\x01" .. string.char(i + 5) .. "\xFF\xFF", 0x04) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main",
          button_event.button_state({ state_change = true }))
      }
    }
  )
end

test.register_message_test(
    "Reported on off status should be handled by parent device: on",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_parent_device.id, "init" }
      },
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_parent_device.id, OnOff.attributes.OnOff:build_test_attr_report(mock_parent_device,
            true)                               :from_endpoint(0x01) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent_device:generate_test_message("main", capabilities.switch.switch.on())
      }
    }
)

test.register_message_test(
    "Reported on off status should be handled by child device: on",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_child_device.id, "init" }
      },
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_child_device.id, OnOff.attributes.OnOff:build_test_attr_report(mock_parent_device,
            true)                             :from_endpoint(0x02) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_device:generate_test_message("main", capabilities.switch.switch.on())
      }
    }
)

test.register_message_test(
    "Reported on off status should be handled by parent device: off",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_parent_device.id, "init" }
      },
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_parent_device.id, OnOff.attributes.OnOff:build_test_attr_report(mock_parent_device,
            false)                              :from_endpoint(0x01) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent_device:generate_test_message("main", capabilities.switch.switch.off())
      }
    }
)

test.register_message_test(
    "Reported on off status should be handled by child device: off",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_child_device.id, "init" }
      },
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_child_device.id, OnOff.attributes.OnOff:build_test_attr_report(mock_parent_device,
            false)                            :from_endpoint(0x02) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_device:generate_test_message("main", capabilities.switch.switch.off())
      }
    }
)

test.register_message_test(
    "Capability on command switch on should be handled : parent device",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_parent_device.id, { capability = "switch", component = "main", command = "on", args = { } } }
      },
      {
        channel = "zigbee",
        direction = "send",
      message = { mock_parent_device.id, OnOff.server.commands.On(mock_parent_device):to_endpoint(0x01) }
      }
    }
)

test.register_message_test(
    "Capability on command switch on should be handled : child device",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_child_device.id, { capability = "switch", component = "main", command = "on", args = { } } }
      },
      {
        channel = "zigbee",
        direction = "send",
      message = { mock_parent_device.id, OnOff.server.commands.On(mock_parent_device):to_endpoint(0x02) }
      }
    }
)

test.register_message_test(
    "Capability off command switch on should be handled : parent device",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_parent_device.id, { capability = "switch", component = "main", command = "off", args = { } } }
      },
      {
        channel = "zigbee",
        direction = "send",
      message = { mock_parent_device.id, OnOff.server.commands.Off(mock_parent_device):to_endpoint(0x01) }
      }
    }
)

test.register_message_test(
    "Capability off command switch on should be handled : child device",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_child_device.id, { capability = "switch", component = "main", command = "off", args = { } } }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_parent_device.id, OnOff.server.commands.Off(mock_parent_device):to_endpoint(0x02) }
      }
    }
)

test.register_coroutine_test(
  "Power meter handled : parent device",
  function()
    test.socket.zigbee:__queue_receive({
      mock_parent_device.id,
      ElectricalMeasurement.attributes.ActivePower:build_test_attr_report(mock_parent_device, 32):from_endpoint(0x01)
    })
    test.socket.capability:__expect_send(
      mock_parent_device:generate_test_message("main",
        capabilities.powerMeter.power({ value = 3.2, unit = "W" }))
    )
  end
)

test.register_coroutine_test(
  "Power meter handled : child device",
  function()
    test.socket.zigbee:__queue_receive({
      mock_child_device.id,
      ElectricalMeasurement.attributes.ActivePower:build_test_attr_report(mock_child_device, 64):from_endpoint(0x02)
    })
    test.socket.capability:__expect_send(
      mock_child_device:generate_test_message("main",
        capabilities.powerMeter.power({ value = 6.4, unit = "W" }))
    )
  end
)

test.register_coroutine_test(
  "Energy meter and PowerConsumptionReport handled : parent device",
  function()
    local current_time = os.time() - 60 * 15
    mock_parent_device:set_field(LAST_REPORT_TIME, current_time)
    test.socket.zigbee:__queue_receive({
      mock_parent_device.id,
      SimpleMetering.attributes.CurrentSummationDelivered:build_test_attr_report(mock_parent_device, 27):from_endpoint(0x01)
    })
    test.socket.capability:__expect_send(
      mock_parent_device:generate_test_message("main",
        capabilities.energyMeter.energy({ value = 0.027, unit = "kWh" }))
    )
    test.socket.capability:__expect_send(
      mock_parent_device:generate_test_message("main",
        capabilities.powerConsumptionReport.powerConsumption({ deltaEnergy = 0.0, energy = 27 }))
    )
  end
)

test.register_coroutine_test(
  "Energy meter and PowerConsumptionReport handled : child device",
  function()
    local current_time = os.time() - 60 * 15
    mock_child_device:set_field(LAST_REPORT_TIME, current_time)
    test.socket.zigbee:__queue_receive({
      mock_child_device.id,
      SimpleMetering.attributes.CurrentSummationDelivered:build_test_attr_report(mock_child_device, 54):from_endpoint(0x02)
    })
    test.socket.capability:__expect_send(
      mock_child_device:generate_test_message("main",
        capabilities.energyMeter.energy({ value = 0.054, unit = "kWh" }))
    )
    test.socket.capability:__expect_send(
      mock_child_device:generate_test_message("main",
        capabilities.powerConsumptionReport.powerConsumption({ deltaEnergy = 0.0, energy = 54 }))
    )
  end
)

 for name, preference in pairs(PREFERENCE_TABLES) do
  test.register_coroutine_test(
    "Handle preference: " .. name .." in infoChanged: parent device only",
    function()
      test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({
        preferences = { [name] = preference.payload }
      }))
      test.socket.zigbee:__expect_send({ mock_device.id,
        cluster_base.write_manufacturer_specific_attribute(mock_device, preference.clusterId,
          preference.attributeId, preference.mfgCode, preference.dataType, preference.payload):to_endpoint(preference.ep) })
    end
  )
end

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
      Alarm.server.commands.ResetAllAlarms(mock_device):to_endpoint(0x01)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      Alarm.attributes.AlarmCount:read(mock_device):to_endpoint(0x01)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.temperatureAlarm.temperatureAlarm.cleared())
    )
  end
)

test.register_coroutine_test(
  "lifecycle configure event should configure device",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })

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
      DeviceTemperatureConfiguration.attributes.CurrentTemperature:configure_reporting(mock_device, 1, 65534, 1)
    })

    for endpoint = 1, 2 do
      test.socket.zigbee:__expect_send({
        mock_device.id,
        zigbee_test_utils.build_bind_request(mock_device,
          zigbee_test_utils.mock_hub_eui,
          SimpleMetering.ID, endpoint)
      })

      test.socket.zigbee:__expect_send({
        mock_device.id,
        zigbee_test_utils.build_bind_request(mock_device,
          zigbee_test_utils.mock_hub_eui,
          ElectricalMeasurement.ID, endpoint)
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        SimpleMetering.attributes.CurrentSummationDelivered:configure_reporting(mock_device, 5, 3600, 1):to_endpoint(endpoint)
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        ElectricalMeasurement.attributes.ActivePower:configure_reporting(mock_device, 10, 3600, 1):to_endpoint(endpoint)
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        ElectricalMeasurement.attributes.RMSCurrent:configure_reporting(mock_device, 10, 3600, 10):to_endpoint(endpoint)
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        ElectricalMeasurement.attributes.RMSVoltage:configure_reporting(mock_device, 10, 3600, 10):to_endpoint(endpoint)
      })
    end

    for endpoint = 1,4 do
        test.socket.zigbee:__expect_send({
          mock_device.id,
          zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, Scenes.ID, endpoint)
        })
    end

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.temperatureAlarm.temperatureAlarm.cleared())
    )

    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)

test.register_coroutine_test(
  "Refresh device should read all necessary attributes",
  function()
    test.socket.capability:__queue_receive({ mock_device.id,
      { capability = "refresh", component = "main", command = "refresh", args = {} } })

    test.socket.zigbee:__expect_send({
      mock_device.id,
      OnOff.attributes.OnOff:read(mock_device)
    })

    test.socket.zigbee:__expect_send({
      mock_device.id,
      ElectricalMeasurement.attributes.RMSCurrent:read(mock_device)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      ElectricalMeasurement.attributes.RMSVoltage:read(mock_device)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      Alarm.attributes.AlarmCount:read(mock_device)
    })
  end
)

test.run_registered_tests()
