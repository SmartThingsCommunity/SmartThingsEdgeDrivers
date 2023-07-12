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

local capabilities = require "st.capabilities"
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.Notification
local Notification = (require "st.zwave.CommandClass.Notification")({ version = 3 })
--- @type st.zwave.CommandClass.Configuration
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version = 4 })
--- @type st.zwave.CommandClass.Battery
local Battery = (require "st.zwave.CommandClass.Battery")({ version = 1 })
--- @type st.zwave.CommandClass.SensorMultilevel
local SensorMultilevel = (require "st.zwave.CommandClass.SensorMultilevel")({ version = 5 })
local WakeUp = (require "st.zwave.CommandClass.WakeUp")({ version = 2 })

local preferences = require "preferences"

local AEOTEC_TRISENSOR_FINGERPRINTS = {
  { manufacturerId = 0x0371, productType = 0x0002, productId = 0x002D }, -- TriSensor 8 EU
  { manufacturerId = 0x0371, productType = 0x0102, productId = 0x002D },  -- TriSensor 8 US
  { manufacturerId = 0x0371, productType = 0x0202, productId = 0x002D }  -- TriSensor 8 AU
}

local function can_handle_aeotec_multisensor(opts, self, device)
  for _, fingerprint in ipairs(AEOTEC_TRISENSOR_FINGERPRINTS) do
    if device:id_match(fingerprint.manufacturerId, fingerprint.productType, fingerprint.productId) then
      return true
    end
  end
  return false
end

local function update_preferences(self, device, args)
  local prefs = preferences.get_device_parameters(device)
  if prefs ~= nil then
    for id, value in pairs(device.preferences) do
      local newParameterValue = preferences.to_numeric_value(device.preferences[id])
      local synchronized = device:get_field(id)
      if not (args and args.old_st_store) or (args.old_st_store.preferences[id] ~= value and prefs and prefs[id] or synchronized == false) then
        device:send(Configuration:Set({
          parameter_number = prefs[id].parameter_number,
          size = prefs[id].size,
          configuration_value = newParameterValue
        }))
        device:set_field(id, false, { persist = true })
        device:send(Configuration:Get({ parameter_number = prefs[id].parameter_number }))
      end
    end
  end
end

local function notification_report_handler(self, device, cmd)
  local event
  if cmd.args.notification_type == Notification.notification_type.HOME_SECURITY then
    if cmd.args.event == Notification.event.home_security.STATE_IDLE then
      event = capabilities.motionSensor.motion.inactive()
    elseif cmd.args.event == Notification.event.home_security.MOTION_DETECTION then
      event = capabilities.motionSensor.motion.active()
    end
  end

  if event ~= nil then
    device:emit_event(event)
  end
end

local function wakeup_notification(driver, device, cmd)
  device:refresh()
end

local function do_refresh(self, device)
  device:send(Battery:Get({}))
  device:send(SensorMultilevel:Get({ sensor_type = SensorMultilevel.sensor_type.TEMPERATURE }))
  device:send(SensorMultilevel:Get({ sensor_type = SensorMultilevel.sensor_type.LUMINANCE }))
  device:send(Notification:Get({ notification_type = Notification.notification_type.HOME_SECURITY }))
end

local function device_init(self, device)
  -- overwrite update_preferences function
  local preferences = preferences.get_device_parameters(device)
  if preferences then
    device:set_update_preferences_fn(update_preferences)
    for id, _ in pairs(preferences) do
      device:set_field(id, true, { persist = true })
    end
  end
end

local function device_added(driver, device)
    do_refresh(driver, device)
end

local function info_changed(self, device, event, args)
    if (device:is_cc_supported(cc.WAKE_UP)) then
        update_preferences(self, device, args)
    end
end

local aeotec_trisensor = {
  zwave_handlers = {
    [cc.NOTIFICATION] = {
      [Notification.REPORT] = notification_report_handler
    },
    [cc.WAKE_UP] = {
      [WakeUp.NOTIFICATION] = wakeup_notification
    }
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh
    }
  },
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
    infoChanged = info_changed
  },
  NAME = "Aeotec TriSensor 8",
  can_handle = can_handle_aeotec_multisensor
}

return aeotec_trisensor
