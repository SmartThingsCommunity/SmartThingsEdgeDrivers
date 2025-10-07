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
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"
local json = require "st.json"
local utils = require "st.utils"
local IasEnrollResponseCode = require "st.zigbee.generated.zcl_clusters.IASZone.types.EnrollResponseCode"

local IASZone = clusters.IASZone
local PowerConfiguration = clusters.PowerConfiguration
local IlluminanceMeasurement = clusters.IlluminanceMeasurement
local ZoneStatusAttribute = IASZone.attributes.ZoneStatus
local ZoneTypeAttribute = IASZone.attributes.ZoneType

local ZONETYPE = "ZoneType"
local Contact_Switch = 21 -- 0x0015
local Motion_Sensor = 13 -- 0x000d
local Water_Sensor = 42 -- 0x002a
local ZIGBEE_GENERIC_SENSOR_PROFILE = "generic-sensor"
local ZIGBEE_GENERIC_CONTACT_SENSOR_PROFILE = "generic-contact-sensor"
local ZIGBEE_GENERIC_MOTION_SENSOR_PROFILE = "generic-motion-sensor"
local ZIGBEE_GENERIC_WATERLEAK_SENSOR_PROFILE = "generic-waterleak-sensor"
local ZIGBEE_GENERIC_MOTION_ILLUMINANCE_PROFILE = "generic-motion-illuminance"

local mock_device_generic_sensor = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition(ZIGBEE_GENERIC_SENSOR_PROFILE .. ".yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        server_clusters = { 0x0500, 0x0001 }
      }
    }
  }
)

local mock_device_contact_sensor = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition(ZIGBEE_GENERIC_CONTACT_SENSOR_PROFILE .. ".yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        server_clusters = { 0x0500, 0x0001 }
      }
    }
  }
)

local mock_device_motion_sensor = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition(ZIGBEE_GENERIC_MOTION_SENSOR_PROFILE .. ".yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        server_clusters = { 0x0500, 0x0001 }
      }
    }
  }
)

local mock_device_waterleak_sensor = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition(ZIGBEE_GENERIC_WATERLEAK_SENSOR_PROFILE .. ".yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        server_clusters = { 0x0500, 0x0001 }
      }
    }
  }
)

local mock_device_motion_illuminance = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition(ZIGBEE_GENERIC_MOTION_ILLUMINANCE_PROFILE .. ".yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        server_clusters = { 0x0500, 0x0001 }
      },
      [2] = {
        id = 2,
        server_clusters = { 0x0400 }
      }
    }
  }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  mock_device_contact_sensor:set_field(ZONETYPE, Contact_Switch, { persist = true })
  mock_device_motion_sensor:set_field(ZONETYPE, Motion_Sensor, { persist = true })
  mock_device_waterleak_sensor:set_field(ZONETYPE, Water_Sensor, { persist = true })
  test.mock_device.add_test_device(mock_device_contact_sensor)
  test.mock_device.add_test_device(mock_device_motion_sensor)
  test.mock_device.add_test_device(mock_device_waterleak_sensor)
  test.mock_device.add_test_device(mock_device_generic_sensor)
  test.mock_device.add_test_device(mock_device_motion_illuminance)end

test.set_test_init_function(test_init)

test.register_coroutine_test(
    "Profile should change to Contact Sensor",
    function ()
      test.socket.zigbee:__queue_receive({mock_device_generic_sensor.id, ZoneTypeAttribute:build_test_attr_report(mock_device_generic_sensor, 0x0015)})
      mock_device_generic_sensor:expect_metadata_update({profile = ZIGBEE_GENERIC_CONTACT_SENSOR_PROFILE})
    end
)

test.register_coroutine_test(
    "Profile should change to Motion Sensor",

    function ()
      test.socket.zigbee:__queue_receive({mock_device_generic_sensor.id, ZoneTypeAttribute:build_test_attr_report(mock_device_generic_sensor, 0x000d)})
      mock_device_generic_sensor:expect_metadata_update({profile = ZIGBEE_GENERIC_MOTION_SENSOR_PROFILE})
    end
)

test.register_coroutine_test(
    "Profile should change to Motion Illuminance",
    function ()
      test.socket.zigbee:__queue_receive({mock_device_motion_illuminance.id, ZoneTypeAttribute:build_test_attr_report(mock_device_motion_illuminance, 0x000d)})
      mock_device_motion_illuminance:expect_metadata_update({profile = ZIGBEE_GENERIC_MOTION_ILLUMINANCE_PROFILE})
    end
)

test.register_coroutine_test(
    "Profile should change to Waterleak Sensor",
    function ()
      test.socket.zigbee:__queue_receive({mock_device_generic_sensor.id, ZoneTypeAttribute:build_test_attr_report(mock_device_generic_sensor, 0x002a)})
      mock_device_generic_sensor:expect_metadata_update({profile = ZIGBEE_GENERIC_WATERLEAK_SENSOR_PROFILE})
    end
)

test.register_message_test(
    "Battery percentage report should be handled (contact sensor)",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device_contact_sensor.id, PowerConfiguration.attributes.BatteryPercentageRemaining:build_test_attr_report(mock_device_contact_sensor, 55) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device_contact_sensor:generate_test_message("main", capabilities.battery.battery(28))
      }
    }
)

test.register_message_test(
    "Battery percentage report should be handled (motion sensor)",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device_motion_sensor.id, PowerConfiguration.attributes.BatteryPercentageRemaining:build_test_attr_report(mock_device_motion_sensor, 55) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device_motion_sensor:generate_test_message("main", capabilities.battery.battery(28))
      }
    }
)

test.register_message_test(
    "Battery percentage report should be handled (motion illuminance)",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device_motion_illuminance.id, PowerConfiguration.attributes.BatteryPercentageRemaining:build_test_attr_report(mock_device_motion_illuminance, 55) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device_motion_illuminance:generate_test_message("main", capabilities.battery.battery(28))
      }
    }
)

test.register_message_test(
    "Battery percentage report should be handled (water leak sensor)",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device_waterleak_sensor.id, PowerConfiguration.attributes.BatteryPercentageRemaining:build_test_attr_report(mock_device_waterleak_sensor, 55) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device_waterleak_sensor:generate_test_message("main", capabilities.battery.battery(28))
      }
    }
)

test.register_message_test(
    "Reported contact should be handled: open",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device_contact_sensor.id, ZoneStatusAttribute:build_test_attr_report(mock_device_contact_sensor, 0x0001) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device_contact_sensor:generate_test_message("main", capabilities.contactSensor.contact.open())
      }
    }
)

test.register_message_test(
    "Reported contact should be handled: closed",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device_contact_sensor.id, ZoneStatusAttribute:build_test_attr_report(mock_device_contact_sensor, 0x0000) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device_contact_sensor:generate_test_message("main", capabilities.contactSensor.contact.closed())
      }
    }
)

test.register_message_test(
    "ZoneStatusChangeNotification from contact sensor should be handled: open",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device_contact_sensor.id, IASZone.client.commands.ZoneStatusChangeNotification.build_test_rx(mock_device_contact_sensor,
                                                                                                                                          0x0001,
                                                                                                                                            0x00) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device_contact_sensor:generate_test_message("main", capabilities.contactSensor.contact.open())
      }
    }
)

test.register_message_test(
    "ZoneStatusChangeNotification from contact sensor should be handled: closed",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device_contact_sensor.id, IASZone.client.commands.ZoneStatusChangeNotification.build_test_rx(mock_device_contact_sensor,
                                                                                                                                          0x0000,
                                                                                                                                            0x00) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device_contact_sensor:generate_test_message("main", capabilities.contactSensor.contact.closed())
      }
    }
)

test.register_message_test(
    "Reported motion should be handled: active",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device_motion_sensor.id, ZoneStatusAttribute:build_test_attr_report(mock_device_motion_sensor, 0x0001) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device_motion_sensor:generate_test_message("main", capabilities.motionSensor.motion.active())
      }
    }
)

test.register_message_test(
    "Reported motion should be handled: inactive",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device_motion_sensor.id, ZoneStatusAttribute:build_test_attr_report(mock_device_motion_sensor, 0x0000) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device_motion_sensor:generate_test_message("main", capabilities.motionSensor.motion.inactive())
      }
    }
)

test.register_message_test(
    "ZoneStatusChangeNotification from motion sensor should be handled: active",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device_motion_sensor.id, IASZone.client.commands.ZoneStatusChangeNotification.build_test_rx(mock_device_motion_sensor, 0x0001, 0x00) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device_motion_sensor:generate_test_message("main", capabilities.motionSensor.motion.active())
      }
    }
)

test.register_message_test(
    "ZoneStatusChangeNotification from motion sensor should be handled: inactive",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device_motion_sensor.id, IASZone.client.commands.ZoneStatusChangeNotification.build_test_rx(mock_device_motion_sensor, 0x0000, 0x00) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device_motion_sensor:generate_test_message("main", capabilities.motionSensor.motion.inactive())
      }
    }
)

test.register_message_test(
    "Reported motion illuminance should be handled: active",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device_motion_illuminance.id, ZoneStatusAttribute:build_test_attr_report(mock_device_motion_illuminance, 0x0001) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device_motion_illuminance:generate_test_message("main", capabilities.motionSensor.motion.active())
      }
    }
)

test.register_message_test(
    "Reported motion illuminance should be handled: inactive",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device_motion_illuminance.id, ZoneStatusAttribute:build_test_attr_report(mock_device_motion_illuminance, 0x0000) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device_motion_illuminance:generate_test_message("main", capabilities.motionSensor.motion.inactive())
      }
    }
)

test.register_message_test(
  "Illuminance report should be handled",
  {
     {
        channel = "zigbee",
        direction = "receive",
        message = {
          mock_device_motion_illuminance.id,
          IlluminanceMeasurement.attributes.MeasuredValue:build_test_attr_report(mock_device_motion_illuminance, 21370)
        }
     },
     {
        channel = "capability",
        direction = "send",
        message = mock_device_motion_illuminance:generate_test_message("main", capabilities.illuminanceMeasurement.illuminance({ value = 137 }))
     }
  }
)

test.register_message_test(
    "ZoneStatusChangeNotification from motion illuminance should be handled: active",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device_motion_illuminance.id, IASZone.client.commands.ZoneStatusChangeNotification.build_test_rx(mock_device_motion_illuminance, 0x0001, 0x00) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device_motion_illuminance:generate_test_message("main", capabilities.motionSensor.motion.active())
      }
    }
)

test.register_message_test(
    "ZoneStatusChangeNotification from motion illuminance should be handled: inactive",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device_motion_illuminance.id, IASZone.client.commands.ZoneStatusChangeNotification.build_test_rx(mock_device_motion_illuminance, 0x0000, 0x00) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device_motion_illuminance:generate_test_message("main", capabilities.motionSensor.motion.inactive())
      }
    }
)

test.register_message_test(
    "Reported water should be handled: wet",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device_waterleak_sensor.id, ZoneStatusAttribute:build_test_attr_report(mock_device_waterleak_sensor, 0x0001) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device_waterleak_sensor:generate_test_message("main", capabilities.waterSensor.water.wet())
      }
    }
)

test.register_message_test(
    "Reported water should be handled: dry",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device_waterleak_sensor.id, ZoneStatusAttribute:build_test_attr_report(mock_device_waterleak_sensor, 0x0000) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device_waterleak_sensor:generate_test_message("main", capabilities.waterSensor.water.dry())
      }
    }
)

test.register_message_test(
    "ZoneStatusChangeNotification from waterleak sensor should be handled: wet",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device_waterleak_sensor.id, IASZone.client.commands.ZoneStatusChangeNotification.build_test_rx(mock_device_waterleak_sensor, 0x0001, 0x00) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device_waterleak_sensor:generate_test_message("main", capabilities.waterSensor.water.wet())
      }
    }
)

test.register_message_test(
    "ZoneStatusChangeNotification from waterleak sensor should be handled: dry",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device_waterleak_sensor.id, IASZone.client.commands.ZoneStatusChangeNotification.build_test_rx(mock_device_waterleak_sensor, 0x0000, 0x00) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device_waterleak_sensor:generate_test_message("main", capabilities.waterSensor.water.dry())
      }
    }
)

-- test.register_coroutine_test(
--     "Health check should check all relevant attributes(contact)",
--     function()
--       test.socket.device_lifecycle:__queue_receive({ mock_device_contact_sensor.id, "added" })
--       test.socket.zigbee:__expect_send({
--         mock_device_contact_sensor.id,
--         ZoneTypeAttribute:read(mock_device_contact_sensor)
--       })
--       test.wait_for_events()

--       test.mock_time.advance_time(50000)
--       test.socket.zigbee:__set_channel_ordering("relaxed")
--       test.socket.zigbee:__expect_send({ mock_device_contact_sensor.id, PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device_contact_sensor) })
--       test.wait_for_events()
--     end,
--     {
--       test_init = function()
--         test.mock_device.add_test_device(mock_device_contact_sensor)
--         test.timer.__create_and_queue_test_time_advance_timer(30, "interval", "health_check")
--       end
--     }
-- )

-- test.register_coroutine_test(
--     "Health check should check all relevant attributes(motion)",
--     function()
--       test.socket.device_lifecycle:__queue_receive({ mock_device_motion_sensor.id, "added" })
--       test.socket.zigbee:__expect_send({
--         mock_device_motion_sensor.id,
--         ZoneTypeAttribute:read(mock_device_motion_sensor)
--       })
--       test.wait_for_events()

--       test.mock_time.advance_time(50000)
--       test.socket.zigbee:__set_channel_ordering("relaxed")
--       test.socket.zigbee:__expect_send({ mock_device_motion_sensor.id, PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device_motion_sensor) })
--       test.wait_for_events()
--     end,
--     {
--       test_init = function()
--         test.mock_device.add_test_device(mock_device_motion_sensor)
--         test.timer.__create_and_queue_test_time_advance_timer(30, "interval", "health_check")
--       end
--     }
-- )

-- test.register_coroutine_test(
--     "Health check should check all relevant attributes(motion illuminance)",
--     function()
--       test.socket.device_lifecycle:__queue_receive({ mock_device_motion_illuminance.id, "added" })
--       test.socket.zigbee:__expect_send({
--         mock_device_motion_illuminance.id,
--         ZoneTypeAttribute:read(mock_device_motion_illuminance)
--       })
--       test.wait_for_events()

--       test.mock_time.advance_time(50000)
--       test.socket.zigbee:__set_channel_ordering("relaxed")
--       test.socket.zigbee:__expect_send({ mock_device_motion_illuminance.id, PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device_motion_illuminance) })
--       test.wait_for_events()
--     end,
--     {
--       test_init = function()
--         test.mock_device.add_test_device(mock_device_motion_illuminance)
--         test.timer.__create_and_queue_test_time_advance_timer(30, "interval", "health_check")
--       end
--     }
-- )

-- test.register_coroutine_test(
--     "Health check should check all relevant attributes(waterleak)",
--     function()
--       test.socket.device_lifecycle:__queue_receive({ mock_device_waterleak_sensor.id, "added" })
--       test.socket.zigbee:__expect_send({
--         mock_device_waterleak_sensor.id,
--         ZoneTypeAttribute:read(mock_device_waterleak_sensor)
--       })
--       test.wait_for_events()

--       test.mock_time.advance_time(50000)
--       test.socket.zigbee:__set_channel_ordering("relaxed")
--       test.socket.zigbee:__expect_send({ mock_device_waterleak_sensor.id, PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device_waterleak_sensor) })
--       test.wait_for_events()
--     end,
--     {
--       test_init = function()
--         test.mock_device.add_test_device(mock_device_waterleak_sensor)
--         test.timer.__create_and_queue_test_time_advance_timer(30, "interval", "health_check")
--       end
--     }
-- )

test.register_coroutine_test(
    "Refresh necessary attributes(contact)",
    function()
      test.wait_for_events()

      test.socket.zigbee:__set_channel_ordering("relaxed")
      test.socket.capability:__queue_receive({ mock_device_contact_sensor.id, { capability = "refresh", component = "main", command = "refresh", args = {} } })
      test.socket.zigbee:__expect_send(
        {
          mock_device_contact_sensor.id,
          PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device_contact_sensor)
        }
      )
      test.socket.zigbee:__expect_send({ mock_device_contact_sensor.id, ZoneStatusAttribute:read(mock_device_contact_sensor) })

    end
)

test.register_coroutine_test(
    "Refresh necessary attributes(motion)",
    function()
      test.wait_for_events()

      test.socket.zigbee:__set_channel_ordering("relaxed")
      test.socket.capability:__queue_receive({ mock_device_motion_sensor.id, { capability = "refresh", component = "main", command = "refresh", args = {} } })
      test.socket.zigbee:__expect_send(
        {
          mock_device_motion_sensor.id,
          PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device_motion_sensor)
        }
      )
      test.socket.zigbee:__expect_send({ mock_device_motion_sensor.id, ZoneStatusAttribute:read(mock_device_motion_sensor) })
    end
)

test.register_coroutine_test(
    "Refresh necessary attributes(motion illuminance)",
    function()
      test.wait_for_events()

      test.socket.zigbee:__set_channel_ordering("relaxed")
      test.socket.capability:__queue_receive({ mock_device_motion_illuminance.id, { capability = "refresh", component = "main", command = "refresh", args = {} } })
      test.socket.zigbee:__expect_send(
        {
          mock_device_motion_illuminance.id,
          PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device_motion_illuminance)
        }
      )
      test.socket.zigbee:__expect_send({ mock_device_motion_illuminance.id, ZoneStatusAttribute:read(mock_device_motion_illuminance) })
    end
)

test.register_coroutine_test(
    "Refresh necessary attributes(waterleak)",
    function()
      test.wait_for_events()

      test.socket.zigbee:__set_channel_ordering("relaxed")
      test.socket.capability:__queue_receive({ mock_device_waterleak_sensor.id, { capability = "refresh", component = "main", command = "refresh", args = {} } })
      test.socket.zigbee:__expect_send(
        {
          mock_device_waterleak_sensor.id,
          PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device_waterleak_sensor)
        }
      )
      test.socket.zigbee:__expect_send({ mock_device_waterleak_sensor.id, ZoneStatusAttribute:read(mock_device_waterleak_sensor) })
    end
)

test.register_coroutine_test(
    "Configure should configure all necessary attributes(contact)",
    function()
      test.socket.device_lifecycle:__queue_receive({ mock_device_contact_sensor.id, "added" })
      test.socket.zigbee:__expect_send({
        mock_device_contact_sensor.id,
        ZoneTypeAttribute:read(mock_device_contact_sensor)
      })
      local device_info_copy = utils.deep_copy(mock_device_contact_sensor.raw_st_data)
      device_info_copy.profile.id = "generic-contact-sensor"
      local device_info_json = json.encode(device_info_copy)
      test.wait_for_events()

      test.socket.zigbee:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle:__queue_receive({ mock_device_contact_sensor.id, "doConfigure" })
      test.socket.zigbee:__expect_send(
          {
            mock_device_contact_sensor.id,
            zigbee_test_utils.build_bind_request(mock_device_contact_sensor,
                                                 zigbee_test_utils.mock_hub_eui,
                                                 PowerConfiguration.ID)
          }
      )
      test.socket.zigbee:__expect_send(
        {
          mock_device_contact_sensor.id,
          PowerConfiguration.attributes.BatteryPercentageRemaining:configure_reporting(mock_device_contact_sensor,
                                                                   30,
                                                                   21600,
                                                                   1)
        }
      )
      test.socket.zigbee:__expect_send(
        {
          mock_device_contact_sensor.id,
          PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device_contact_sensor)
      })
      test.socket.zigbee:__expect_send({
        mock_device_contact_sensor.id,
        IASZone.attributes.IASCIEAddress:write(mock_device_contact_sensor, zigbee_test_utils.mock_hub_eui)
      })
      test.socket.zigbee:__expect_send({
        mock_device_contact_sensor.id,
        IASZone.server.commands.ZoneEnrollResponse(mock_device_contact_sensor, IasEnrollResponseCode.SUCCESS, 0x00)
      })


      test.socket.zigbee:__expect_send(
          {
            mock_device_contact_sensor.id,
            IASZone.attributes.ZoneStatus:configure_reporting(mock_device_contact_sensor,
                                                                     30,
                                                                     300,
                                                                     0)
          }
      )
      test.socket.zigbee:__expect_send(
          {
            mock_device_contact_sensor.id,
            zigbee_test_utils.build_bind_request(mock_device_contact_sensor,
                                                 zigbee_test_utils.mock_hub_eui,
                                                 IASZone.ID)
          }
      )
      test.socket.device_lifecycle:__queue_receive({ mock_device_contact_sensor.id, "infoChanged", device_info_json })
      test.socket.zigbee:__expect_send({ mock_device_contact_sensor.id, IASZone.attributes.ZoneStatus:read(mock_device_contact_sensor) })

      mock_device_contact_sensor:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    end
)

test.register_coroutine_test(
    "Configure should configure all necessary attributes(motion)",
    function()
      test.socket.device_lifecycle:__queue_receive({ mock_device_motion_sensor.id, "added" })
      test.socket.zigbee:__expect_send({
        mock_device_motion_sensor.id,
        ZoneTypeAttribute:read(mock_device_motion_sensor)
      })
      test.wait_for_events()

      test.socket.zigbee:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle:__queue_receive({ mock_device_motion_sensor.id, "doConfigure" })
      test.socket.zigbee:__expect_send(
          {
            mock_device_motion_sensor.id,
            zigbee_test_utils.build_bind_request(mock_device_motion_sensor,
                                                 zigbee_test_utils.mock_hub_eui,
                                                 PowerConfiguration.ID)
          }
      )
      test.socket.zigbee:__expect_send(
        {
          mock_device_motion_sensor.id,
          PowerConfiguration.attributes.BatteryPercentageRemaining:configure_reporting(mock_device_motion_sensor,
                                                                   30,
                                                                   21600,
                                                                   1)
        }
      )
      test.socket.zigbee:__expect_send(
        {
          mock_device_motion_sensor.id,
          PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device_motion_sensor)
      })
      test.socket.zigbee:__expect_send({
        mock_device_motion_sensor.id,
        IASZone.attributes.IASCIEAddress:write(mock_device_motion_sensor, zigbee_test_utils.mock_hub_eui)
      })
      test.socket.zigbee:__expect_send({
        mock_device_motion_sensor.id,
        IASZone.server.commands.ZoneEnrollResponse(mock_device_motion_sensor, IasEnrollResponseCode.SUCCESS, 0x00)
      })
      test.socket.zigbee:__expect_send(
          {
            mock_device_motion_sensor.id,
            IASZone.attributes.ZoneStatus:configure_reporting(mock_device_motion_sensor,
                                                                     30,
                                                                     300,
                                                                     0)
          }
      )
      test.socket.zigbee:__expect_send(
          {
            mock_device_motion_sensor.id,
            zigbee_test_utils.build_bind_request(mock_device_motion_sensor,
                                                 zigbee_test_utils.mock_hub_eui,
                                                 IASZone.ID)
          }
      )
      mock_device_motion_sensor:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    end
)

test.register_coroutine_test(
    "Configure should configure all necessary attributes(motion illuminance)",
    function()
      test.socket.device_lifecycle:__queue_receive({ mock_device_motion_illuminance.id, "added" })
      test.socket.zigbee:__expect_send({
        mock_device_motion_illuminance.id,
        ZoneTypeAttribute:read(mock_device_motion_illuminance)
      })
      test.wait_for_events()

      test.socket.zigbee:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle:__queue_receive({ mock_device_motion_illuminance.id, "doConfigure" })
      test.socket.zigbee:__expect_send(
          {
            mock_device_motion_illuminance.id,
            zigbee_test_utils.build_bind_request(mock_device_motion_illuminance,
                                                 zigbee_test_utils.mock_hub_eui,
                                                 PowerConfiguration.ID)
          }
      )
      test.socket.zigbee:__expect_send(
        {
          mock_device_motion_illuminance.id,
          PowerConfiguration.attributes.BatteryPercentageRemaining:configure_reporting(mock_device_motion_illuminance,
                                                                   30,
                                                                   21600,
                                                                   1)
        }
      )
      test.socket.zigbee:__expect_send(
        {
          mock_device_motion_illuminance.id,
          PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device_motion_illuminance)
      })
      test.socket.zigbee:__expect_send({
        mock_device_motion_illuminance.id,
        IASZone.attributes.IASCIEAddress:write(mock_device_motion_illuminance, zigbee_test_utils.mock_hub_eui)
      })
      test.socket.zigbee:__expect_send({
        mock_device_motion_illuminance.id,
        IASZone.server.commands.ZoneEnrollResponse(mock_device_motion_illuminance, IasEnrollResponseCode.SUCCESS, 0x00)
      })
      test.socket.zigbee:__expect_send(
          {
            mock_device_motion_illuminance.id,
            IASZone.attributes.ZoneStatus:configure_reporting(mock_device_motion_illuminance,
                                                                     30,
                                                                     300,
                                                                     0)
          }
      )
      test.socket.zigbee:__expect_send(
          {
            mock_device_motion_illuminance.id,
            zigbee_test_utils.build_bind_request(mock_device_motion_illuminance,
                                                 zigbee_test_utils.mock_hub_eui,
                                                 IASZone.ID)
          }
      )
      mock_device_motion_illuminance:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    end
)

test.register_coroutine_test(
    "Configure should configure all necessary attributes(waterleak)",
    function()
      test.socket.device_lifecycle:__queue_receive({ mock_device_waterleak_sensor.id, "added" })
      test.socket.zigbee:__expect_send({
        mock_device_waterleak_sensor.id,
        ZoneTypeAttribute:read(mock_device_waterleak_sensor)
      })
      test.wait_for_events()

      test.socket.zigbee:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle:__queue_receive({ mock_device_waterleak_sensor.id, "doConfigure" })
      test.socket.zigbee:__expect_send(
          {
            mock_device_waterleak_sensor.id,
            zigbee_test_utils.build_bind_request(mock_device_waterleak_sensor,
                                                 zigbee_test_utils.mock_hub_eui,
                                                 PowerConfiguration.ID)
          }
      )
      test.socket.zigbee:__expect_send(
        {
          mock_device_waterleak_sensor.id,
          PowerConfiguration.attributes.BatteryPercentageRemaining:configure_reporting(mock_device_waterleak_sensor,
                                                                   30,
                                                                   21600,
                                                                   1)
        }
      )
      test.socket.zigbee:__expect_send(
        {
          mock_device_waterleak_sensor.id,
          PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device_waterleak_sensor)
      }
    )
      test.socket.zigbee:__expect_send({
        mock_device_waterleak_sensor.id,
        IASZone.attributes.IASCIEAddress:write(mock_device_waterleak_sensor, zigbee_test_utils.mock_hub_eui)
      })
      test.socket.zigbee:__expect_send({
        mock_device_waterleak_sensor.id,
        IASZone.server.commands.ZoneEnrollResponse(mock_device_waterleak_sensor, IasEnrollResponseCode.SUCCESS, 0x00)
      })
      test.socket.zigbee:__expect_send(
          {
            mock_device_waterleak_sensor.id,
            IASZone.attributes.ZoneStatus:configure_reporting(mock_device_waterleak_sensor,
                                                                     30,
                                                                     300,
                                                                     0)
          }
      )
      test.socket.zigbee:__expect_send(
          {
            mock_device_waterleak_sensor.id,
            zigbee_test_utils.build_bind_request(mock_device_waterleak_sensor,
                                                 zigbee_test_utils.mock_hub_eui,
                                                 IASZone.ID)
          }
      )
      mock_device_waterleak_sensor:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    end
)

test.run_registered_tests()