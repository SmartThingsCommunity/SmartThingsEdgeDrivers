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
--- @type st.zwave.CommandClass.Configuration
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version = 4 })

local log = require "log"
local utils = require "st.utils"

local MoldHealthConcern = capabilities.moldHealthConcern
local CarbonDioxideHealthConcern = capabilities.carbonDioxideHealthConcern
local SoundDetection = capabilities.soundDetection
local SmokeDetector = capabilities.smokeDetector
local WaterSensor = capabilities.waterSensor
local CarbonMonoxideDetector = capabilities.carbonMonoxideDetector
local TamperAlert = capabilities.tamperAlert
local MotionSensor = capabilities.motionSensor
local PowerSource = capabilities.powerSource
local ContactSensor = capabilities.contactSensor
local PanicAlarm = capabilities.panicAlarm

local AEOTEC_WATER_SENSOR_8_FINGERPRINTS = {
  { manufacturerId = 0x0371, productId = 0x0038 } -- Aeotec Water Sensor 8 EU/US/AU
}

DEVICE_PROFILES = {
  [0] = { profile = "aeotec-water-sensor-8"},
  [1] = { profile = "aeotec-water-sensor-8-smoke"},
  [2] = { profile = "aeotec-water-sensor-8-co"},
  [3] = { profile = "aeotec-water-sensor-8-co2"},
  [4] = { profile = "aeotec-water-sensor-8-contact"},
  [5] = { profile = "aeotec-water-sensor-8-contact"},
  [6] = { profile = "aeotec-water-sensor-8-motion"},
  [7] = { profile = "aeotec-water-sensor-8-glass-break"},
  [8] = { profile = "aeotec-water-sensor-8-panic"}
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

    -- Set supported modes and default value based on profile
    if profile.profile == "aeotec-water-sensor-8" then
      device:emit_event(WaterSensor.water.dry())
    elseif profile.profile == "aeotec-water-sensor-8-glass-break" then
      device:emit_event(SoundDetection.supportedSoundTypes({"noSound", "glassBreaking"}))
      device:emit_event(SoundDetection.soundDetected.noSound())
    elseif profile.profile == "aeotec-water-sensor-8-co2" then
      device:emit_event(CarbonDioxideHealthConcern.supportedCarbonDioxideValues({"good", "moderate"}))
      device:emit_event(CarbonDioxideHealthConcern.carbonDioxideHealthConcern.good())
    elseif profile.profile == "aeotec-water-sensor-8-co" then
      device:emit_event(CarbonMonoxideDetector.carbonMonoxide.clear())
    elseif profile.profile == "aeotec-water-sensor-8-contact" then
      device:emit_event(ContactSensor.contact.closed())
    elseif profile.profile == "aeotec-water-sensor-8-motion" then
      device:emit_event(MotionSensor.motion.inactive())
    elseif profile.profile == "aeotec-water-sensor-8-panic" then
      device:emit_event(PanicAlarm.panicAlarm.clear())
    elseif profile.profile == "aeotec-water-sensor-8-smoke" then
      device:emit_event(SmokeDetector.smoke.clear())
    end
  end
end

local function added_handler(driver, device)
  -- Get parameter 10 to switch device profile bsaed on the parameter value
  device:send(Configuration:Get({ parameter_number = 10 }))

  device:emit_event(MoldHealthConcern.supportedMoldValues({"good", "moderate"}))
  -- Default value
  device:emit_event(MoldHealthConcern.moldHealthConcern.good())

  -- Default value
  device:emit_event(PowerSource.powerSource.battery())

  device:send(Battery:Get({}))
end

local function do_refresh(driver, device)
  device:send(Battery:Get({}))
end

local function notification_report_handler(self, device, cmd)
  local active_profile = device:get_field("active_profile")
  local event

  local event_parameter
  log.info("event_parameter", utils.stringify_table(cmd.args.event_parameter))

  if (0 ~= string.len(cmd.args.event_parameter)) then
    event_parameter = string.byte(cmd.args.event_parameter)
  end

  -- MOTION, GLASS_BREAK, TAMPER
  if cmd.args.notification_type == Notification.notification_type.HOME_SECURITY then
    -- TAMPER
    if cmd.args.event == Notification.event.home_security.STATE_IDLE and event_parameter == Notification.event.home_security.TAMPERING_PRODUCT_COVER_REMOVED then
      event = TamperAlert.tamper.clear()
    elseif active_profile == 'aeotec-water-sensor-8-motion' then -- MOTION
      if cmd.args.event == Notification.event.home_security.STATE_IDLE and event_parameter == Notification.event.home_security.MOTION_DETECTION then
        event = MotionSensor.motion.inactive()
      elseif cmd.args.event == Notification.event.home_security.MOTION_DETECTION then
        event = MotionSensor.motion.active()
      end
    elseif active_profile == 'aeotec-water-sensor-8-glass-break' then -- GLASS_BREAK
      if cmd.args.event == Notification.event.home_security.STATE_IDLE and event_parameter == Notification.event.home_security.GLASS_BREAKAGE then
        event = SoundDetection.soundDetected.noSound()
      elseif cmd.args.event == Notification.event.home_security.GLASS_BREAKAGE then
        event = SoundDetection.soundDetected.glassBreaking()
      end
    end
  end

  if cmd.args.notification_type == Notification.notification_type.POWER_MANAGEMENT then
    if cmd.args.event == Notification.event.power_management.AC_MAINS_DISCONNECTED then
      event = PowerSource.powerSource.battery()
    elseif cmd.args.event == Notification.event.power_management.AC_MAINS_RE_CONNECTED then
      event = PowerSource.powerSource.dc()
    elseif cmd.args.event == Notification.event.power_management.POWER_HAS_BEEN_APPLIED then
      device:send(Battery:Get({}))
    end
  end

  -- WATER
  if cmd.args.notification_type == Notification.notification_type.WATER then
    if cmd.args.event == Notification.event.water.STATE_IDLE then
      event = WaterSensor.water.dry()
    elseif cmd.args.event == Notification.event.water.LEAK_DETECTED then
      event = WaterSensor.water.wet()
    end
  end

  -- MOLD
  if cmd.args.notification_type == Notification.notification_type.WEATHER_ALARM then
    if cmd.args.event == Notification.event.weather_alarm.STATE_IDLE then
      event = MoldHealthConcern.moldHealthConcern.good()
    elseif cmd.args.event == Notification.event.weather_alarm.MOISTURE_ALARM then
      event = MoldHealthConcern.moldHealthConcern.moderate()
    end
  end

  -- SMOKE
  if cmd.args.notification_type == Notification.notification_type.SMOKE then
    if cmd.args.event == Notification.event.smoke.STATE_IDLE then
      event = SmokeDetector.smoke.clear()
    elseif cmd.args.event == Notification.event.smoke.DETECTED then
      event = SmokeDetector.smoke.detected()
    end
  end

  -- CO
  if cmd.args.notification_type == Notification.notification_type.CO then
    if cmd.args.event == Notification.event.co.STATE_IDLE then
      event = CarbonMonoxideDetector.carbonMonoxide.clear()
    elseif cmd.args.event == Notification.event.co.CARBON_MONOXIDE_DETECTED then
      event = CarbonMonoxideDetector.carbonMonoxide.detected()
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
      event = ContactSensor.contact.closed()
    elseif cmd.args.event == Notification.event.access_control.WINDOW_DOOR_IS_OPEN then
      event = ContactSensor.contact.open()
    end
  end

  -- PANIC
  if cmd.args.notification_type == Notification.notification_type.EMERGENCY then
    if cmd.args.event == Notification.event.emergency.STATE_IDLE then
      event = PanicAlarm.panicAlarm.clear()
    elseif cmd.args.event == Notification.event.emergency.PANIC_ALERT then
      event = PanicAlarm.panicAlarm.panic()
    end
  end

  if (event ~= nil) then
    device:emit_event(event)
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
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh
    }
  },
  lifecycle_handlers = {
    added = added_handler,
  },
  NAME = "Aeotec Water Sensor  8",
  can_handle = can_handle_aeotec_water_sensor_8
}

return aeotec_water_sensor_8