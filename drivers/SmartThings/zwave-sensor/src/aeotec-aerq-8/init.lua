-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.Notification
local Notification = (require "st.zwave.CommandClass.Notification")({ version = 3 })
--- @type st.zwave.CommandClass.Battery
local Battery = (require "st.zwave.CommandClass.Battery")({ version = 1 })
--- @type st.zwave.CommandClass.Configuration
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version = 4 })

local MoldHealthConcern = capabilities.moldHealthConcern
local PowerSource = capabilities.powerSource
local TamperAlert = capabilities.tamperAlert

local AEOTEC_AERQ_FINGERPRINTS = {
  { manufacturerId = 0x0371, productId = 0x0039 } -- Aeotec aerQ 8 EU/US/AU
}

local function can_handle_aeotec_aerq(opts, driver, device, ...)
  for _, fingerprint in ipairs(AEOTEC_AERQ_FINGERPRINTS) do
    if device:id_match(fingerprint.manufacturerId, fingerprint.productType, fingerprint.productId) then
      local subdriver = require("aeotec-aerq-8")
      return true, subdriver
    end
  end
  return false
end

local function added_handler(driver, device)
  device:send(Configuration:Get({ parameter_number = 10 }))

  device:emit_event(MoldHealthConcern.supportedMoldValues({"good", "moderate"}))

  -- Default value
  device:emit_event(MoldHealthConcern.moldHealthConcern.good())

  -- Default value
  device:emit_event(PowerSource.powerSource.battery())

  device:send(Battery:Get({}))

  device:register_native_capability_attr_handler("temperatureMeasurement", "temperature")
end

local function notification_report_handler(self, device, cmd)
  local event

  -- POWER
  if cmd.args.notification_type == Notification.notification_type.POWER_MANAGEMENT then
    if cmd.args.event == Notification.event.power_management.AC_MAINS_DISCONNECTED then
      event = capabilities.powerSource.powerSource.battery()
    elseif cmd.args.event == Notification.event.power_management.AC_MAINS_RE_CONNECTED then
      event = capabilities.powerSource.powerSource.dc()
    elseif cmd.args.event == Notification.event.power_management.POWER_HAS_BEEN_APPLIED then
      device:send(Battery:Get({}))
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

  -- TAMPER
  if cmd.args.notification_type == Notification.notification_type.HOME_SECURITY then
    if cmd.args.event == Notification.event.home_security.STATE_IDLE then
      event = TamperAlert.tamper.clear()
    elseif cmd.args.event == Notification.event.home_security.TAMPERING_PRODUCT_COVER_REMOVED then
      event = TamperAlert.tamper.detected()
    end
  end

  if (event ~= nil) then
    device:emit_event(event)
  end
end

local aeotec_aerq_8 = {
  supported_capabilities = {
    capabilities.powerSource
  },
  zwave_handlers = {
    [cc.NOTIFICATION] = {
      [Notification.REPORT] = notification_report_handler
    },
  },
  lifecycle_handlers = {
    added = added_handler,
  },
  NAME = "Aeotec aerQ 8",
  can_handle = can_handle_aeotec_aerq
}

return aeotec_aerq_8
