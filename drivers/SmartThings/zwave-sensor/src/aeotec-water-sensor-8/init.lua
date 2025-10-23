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

local capabilities = require "st.capabilities"
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.Notification
local Notification = (require "st.zwave.CommandClass.Notification")({ version = 3 })
--- @type st.zwave.CommandClass.Battery
local Battery = (require "st.zwave.CommandClass.Battery")({ version = 1 })
--- @type st.zwave.CommandClass.SensorBinary
local SensorBinary = (require "st.zwave.CommandClass.SensorBinary")({ version = 2 })
--- @type st.zwave.CommandClass.Configuration
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version = 4 })

local log = require "log"
local utils = require "st.utils"

local MoldHealthConcern = capabilities.moldHealthConcern
local CarbonDioxideHealthConcern = capabilities.carbonDioxideHealthConcern
local SoundDetection = capabilities.soundDetection

local AEOTEC_WATER_SENSOR_8_FINGERPRINTS = {
  { manufacturerId = 0x0371, productId = 0x0038 } -- Aeotec Water Sensor 8 EU/US/AU
}


DEVICE_PROFILES = {
  [0] = { profile = "aeotec-water-sensor-8", sensor_type = SensorBinary.sensor_type.WATER },
  [1] = { profile = "aeotec-water-sensor-8-smoke", sensor_type = SensorBinary.sensor_type.SMOKE },
  [2] = { profile = "aeotec-water-sensor-8-co", sensor_type = SensorBinary.sensor_type.CO },
  [3] = { profile = "aeotec-water-sensor-8-co2", sensor_type = SensorBinary.sensor_type.CO2 },
  [4] = { profile = "aeotec-water-sensor-8-contact", sensor_type = SensorBinary.sensor_type.DOOR_WINDOW },
  [5] = { profile = "aeotec-water-sensor-8-contact", sensor_type = SensorBinary.sensor_type.TILT },
  [6] = { profile = "aeotec-water-sensor-8-motion", sensor_type = SensorBinary.sensor_type.MOTION },
  [7] = { profile = "aeotec-water-sensor-8-glass-break", sensor_type = SensorBinary.sensor_type.GLASS_BREAK },
  [8] = { profile = "aeotec-water-sensor-8-panic", sensor_type = SensorBinary.sensor_type.GENERAL } -- fallback
}

local function can_handle_aeotec_water_sensor_8(opts, driver, device, ...)
  for _, fingerprint in ipairs(AEOTEC_WATER_SENSOR_8_FINGERPRINTS) do
    if device:id_match(fingerprint.manufacturerId, fingerprint.productType, fingerprint.productId) then
      local subdriver = require("aeotec-water-sensor-8")
      return true, subdriver
    end
  end
  return false
end

local function set_profile(device, profile)
  local current = device:get_field("active_profile")
  if current ~= profile.profile then
    log.info(string.format("Switching profile to: %s", profile.profile))
    device:try_update_metadata({ profile = profile.profile })
    device:set_field("active_profile", profile.profile)

    if profile.profile == "aeotec-water-sensor-8-glass-break" then
      device:emit_event(SoundDetection.supportedSoundTypes({"noSound ", "glassBreaking"}))
    elseif profile.profile == "aeotec-water-sensor-8-co2" then
      device:emit_event(CarbonDioxideHealthConcern.supportedCarbonDioxideValues({"good", "moderate"}))
    end

  end
end

local function added_handler(driver, device)
  for key,value in pairs(DEVICE_PROFILES) do
    local field_name = "initial_state_set_" .. value.sensor_type
    device:set_field(field_name, false)
  end

  device:send(Configuration:Get({ parameter_number = 10 }))

  -- Enable binary sensor report
  device:send(Configuration:Set({
    parameter_number = 22,
    size = 1,
    configuration_value = 1
  }))

  device:emit_event(MoldHealthConcern.supportedMoldValues({"good", "moderate"}))

  device:send(SensorBinary:Get({sensor_type = SensorBinary.sensor_type.GENERAL})) -- Mold
  device:send(Battery:Get({}))

  device:emit_event(capabilities.refresh.refresh())
end

local function do_refresh(driver, device)
  for key,value in pairs(DEVICE_PROFILES) do
    local field_name = "initial_state_set_" .. value.sensor_type
    device:set_field(field_name, false)
  end

  device:send(SensorBinary:Get({sensor_type = SensorBinary.sensor_type.GENERAL})) --Mold

  device:send(Battery:Get({}))

  device:send(Configuration:Get({ parameter_number = 10 }))
end

local function notification_report_handler(self, device, cmd)
  local event
  if cmd.args.notification_type == Notification.notification_type.POWER_MANAGEMENT then
    if cmd.args.event == Notification.event.power_management.AC_MAINS_DISCONNECTED then
      event = capabilities.powerSource.powerSource.battery()
    elseif cmd.args.event == Notification.event.power_management.AC_MAINS_RE_CONNECTED then
      event = capabilities.powerSource.powerSource.mains()
    elseif cmd.args.event == Notification.event.power_management.POWER_HAS_BEEN_APPLIED then
      device:send(Battery:Get({}))
    end
  end

  -- WATER
  if cmd.args.notification_type == Notification.notification_type.WATER then
    if cmd.args.event == Notification.event.water.STATE_IDLE then
      event = capabilities.waterSensor.water.dry()
    elseif cmd.args.event == Notification.event.water.LEAK_DETECTED then
      event = capabilities.waterSensor.water.wet()
    end
  end

  -- MOLD
  if cmd.args.notification_type == Notification.notification_type.WEATHER_ALARM then
    if cmd.args.event == Notification.event.weather_alarm.STATE_IDLE then
      event = capabilities.moldHealthConcern.moldHealthConcern.good()
    elseif cmd.args.event == Notification.event.weather_alarm.MOISTURE_ALARM then
      event = capabilities.moldHealthConcern.moldHealthConcern.moderate()
    end
  end

  -- SMOKE
  if cmd.args.notification_type == Notification.notification_type.SMOKE then
    if cmd.args.event == Notification.event.smoke.STATE_IDLE then
      event = capabilities.smokeDetector.smoke.clear()
    elseif cmd.args.event == Notification.event.smoke.DETECTED then
      event = capabilities.smokeDetector.smoke.detected()
    end
  end

  -- CO
  if cmd.args.notification_type == Notification.notification_type.CO then
    if cmd.args.event == Notification.event.co.STATE_IDLE then
      event = capabilities.carbonMonoxideDetector.carbonMonoxide.clear()
    elseif cmd.args.event == Notification.event.co.CARBON_MONOXIDE_DETECTED then
      event = capabilities.carbonMonoxideDetector.carbonMonoxide.detected()
    end
  end

  -- CO2
  if cmd.args.notification_type == Notification.notification_type.CO2 then
    if cmd.args.event == Notification.event.co2.STATE_IDLE then
      event = capabilities.carbonDioxideHealthConcern.carbonDioxideHealthConcern.good()
    elseif cmd.args.event == Notification.event.co2.CARBON_DIOXIDE_DETECTED then
      event = capabilities.carbonDioxideHealthConcern.carbonDioxideHealthConcern.moderate()
    end
  end

  -- DOOR_WINDOW/TILT
  if cmd.args.notification_type == Notification.notification_type.ACCESS_CONTROL then
    if cmd.args.event == Notification.event.access_control.WINDOW_DOOR_IS_CLOSED then
      event = capabilities.contactSensor.contact.closed()
    elseif cmd.args.event == Notification.event.access_control.WINDOW_DOOR_IS_OPEN then
      event = capabilities.contactSensor.contact.open()
    end
  end

  -- MOTION
   if cmd.args.notification_type == Notification.notification_type.HOME_SECURITY then
    if cmd.args.event == Notification.event.home_security.STATE_IDLE then
      event = capabilities.motionSensor.motion.inactive()
    elseif cmd.args.event == Notification.event.home_security.MOTION_DETECTION then
      event = capabilities.motionSensor.motion.active()
    end
  end

  -- GLASS_BREAK
  if cmd.args.notification_type == Notification.notification_type.HOME_SECURITY then
    if cmd.args.event == Notification.event.home_security.STATE_IDLE then
      event = capabilities.soundDetection.soundDetected.noSound()
    elseif cmd.args.event == Notification.event.home_security.GLASS_BREAKAGE then
      event = capabilities.soundDetection.soundDetected.glassBreaking()
    end
  end

  -- PANIC
  if cmd.args.notification_type == Notification.notification_type.EMERGENCY then
    if cmd.args.event == Notification.event.emergency.STATE_IDLE then
      event = capabilities.panicAlarm.panicAlarm.clear()
    elseif cmd.args.event == Notification.event.emergency.PANIC_ALERT then
      event = capabilities.panicAlarm.panicAlarm.panic()
    end
  end

  if (event ~= nil) then
    device:emit_event(event)
  end
end

local function sensor_binary_report_handler(self, device, cmd)
  local sensorType = cmd.args.sensor_type
  local value = cmd.args.sensor_value
  local event

  local field_name = "initial_state_set_" .. sensorType

  if not device:get_field(field_name) then
      log.debug("sensor_binary_report_handler")
    -- MOLD
    if sensorType == SensorBinary.sensor_type.GENERAL then
      if value == SensorBinary.sensor_value.IDLE then
        event = capabilities.moldHealthConcern.moldHealthConcern.good()
      elseif value == SensorBinary.sensor_value.DETECTED_AN_EVENT then
        event = capabilities.moldHealthConcern.moldHealthConcern.moderate()
      end
    end

    -- WATER
    if sensorType == SensorBinary.sensor_type.WATER then
      if value == SensorBinary.sensor_value.IDLE then
        event = capabilities.waterSensor.water.dry()
      elseif value == SensorBinary.sensor_value.DETECTED_AN_EVENT then
        event = capabilities.waterSensor.water.wet()
      end
    end

    -- SMOKE
    if sensorType == SensorBinary.sensor_type.SMOKE then
      if value == SensorBinary.sensor_value.IDLE then
        event = capabilities.contactSensor.contact.closed()
      elseif value == SensorBinary.sensor_value.DETECTED_AN_EVENT then
        event = capabilities.contactSensor.contact.open()
      end
    end

    -- CO
    if sensorType == SensorBinary.sensor_type.CO then
      if value == SensorBinary.sensor_value.IDLE then
        event = capabilities.carbonMonoxideDetector.carbonMonoxide.clear()
      elseif value == SensorBinary.sensor_value.DETECTED_AN_EVENT then
        event = capabilities.carbonMonoxideDetector.carbonMonoxide.detected()
      end
    end

    -- CO2
    if sensorType == SensorBinary.sensor_type.CO2 then
      if value == SensorBinary.sensor_value.IDLE then
        event = capabilities.carbonDioxideHealthConcern.carbonDioxideHealthConcern.good()
      elseif value == SensorBinary.sensor_value.DETECTED_AN_EVENT then
        event = capabilities.carbonDioxideHealthConcern.carbonDioxideHealthConcern.moderate()
      end
    end

    -- DOOR_WINDOW/TILT
    if sensorType == SensorBinary.sensor_type.DOOR_WINDOW or sensorType == SensorBinary.sensor_type.TILT then
      if value == SensorBinary.sensor_value.IDLE then
        event = capabilities.contactSensor.contact.closed()
      elseif value == SensorBinary.sensor_value.DETECTED_AN_EVENT then
        event = capabilities.contactSensor.contact.open()
      end
    end

    -- MOTION
    if sensorType == SensorBinary.sensor_type.MOTION then
      if value == SensorBinary.sensor_value.IDLE then
        event = capabilities.carbonDioxideHealthConcern.carbonDioxideHealthConcern.good()
      elseif value == SensorBinary.sensor_value.DETECTED_AN_EVENT then
        event = capabilities.carbonDioxideHealthConcern.carbonDioxideHealthConcern.moderate()
      end
    end

    -- GLASS_BREAK
    if sensorType == SensorBinary.sensor_type.GLASS_BREAK then
      if value == SensorBinary.sensor_value.IDLE then
        event = capabilities.soundDetection.soundDetected.noSound()
      elseif value == SensorBinary.sensor_value.DETECTED_AN_EVENT then
        event = capabilities.soundDetection.soundDetected.glassBreaking()
      end
    end

    if (event ~= nil) then
      device:emit_event(event)
      device:set_field(field_name, true)
    end
  end
end

local function configuration_report_handler(self, device, cmd)
  local param_number = cmd.args.parameter_number
  local value = cmd.args.configuration_value
  log.info(string.format("Received Configuration Report #%d = %d", param_number, value))

  if param_number == 10 then
    local mapping =  DEVICE_PROFILES[value]
    if mapping then
      set_profile(device, mapping)
      device:send(SensorBinary:Get({ sensor_type = mapping.sensor_type }))
    end
  end
end


local aeotec_water_sensor_8 = {
  supported_capabilities = {
    capabilities.powerSource,
    capabilities.carbonMonoxideDetector,
    capabilities.carbonDioxideHealthConcern,
    capabilities.soundDetection,
    capabilities.panicAlarm
  },
  zwave_handlers = {
    [cc.CONFIGURATION] = {
      [Configuration.REPORT] = configuration_report_handler
    },
    [cc.NOTIFICATION] = {
      [Notification.REPORT] = notification_report_handler
    },
    [cc.SENSOR_BINARY] = {
      [SensorBinary.REPORT] = sensor_binary_report_handler
    },
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh
    }
  },
  lifecycle_handlers = {
    added = added_handler,
  },
  NAME = "Aeotec Water Sesnor  8",
  can_handle = can_handle_aeotec_water_sensor_8
}

return aeotec_water_sensor_8