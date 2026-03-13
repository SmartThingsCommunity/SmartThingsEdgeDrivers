-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0



local capabilities = require "st.capabilities"
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.Basic
local Basic = (require "st.zwave.CommandClass.Basic")({ version = 1 })
--- @type st.zwave.CommandClass.WakeUp
local WakeUp = (require "st.zwave.CommandClass.WakeUp")({ version = 1 })
local SensorMultilevel = (require "st.zwave.CommandClass.SensorMultilevel")({version = 5})
local Battery = (require "st.zwave.CommandClass.Battery")({ version = 1})

local function basic_set_handler(self, device, cmd)
  if cmd.args.value ~= nil then
    device:emit_event(cmd.args.value == 0xFF and capabilities.motionSensor.motion.active() or capabilities.motionSensor.motion.inactive())
  end
end

local function added_handler(self, device)
  device:send(WakeUp:IntervalSet({node_id = self.environment_info.hub_zwave_id, seconds = 1200}))
end

local function update_preferences(self, device, args)
  if args.old_st_store.preferences.reportingInterval ~= device.preferences.reportingInterval then
    device:send(WakeUp:IntervalSet({node_id = self.environment_info.hub_zwave_id, seconds = device.preferences.reportingInterval * 60}))
  end
end

local function wakeup_notification(driver, device, cmd)
  --Note sending WakeUpIntervalGet the first time a device wakes up will happen by default in Lua libs 0.49.x and higher
  --This is done to help the hub correctly set the checkInterval for migrated devices.
  if not device:get_field("__wakeup_interval_get_sent") then
    device:send(WakeUp:IntervalGetV1({}))
    device:set_field("__wakeup_interval_get_sent", true)
  end
  local get_temp = SensorMultilevel:Get({sensor_type = SensorMultilevel.sensor_type.TEMPERATURE}, {dst_channels = {3}})
  device:send(get_temp)
  local get_luminance = SensorMultilevel:Get({sensor_type = SensorMultilevel.sensor_type.LUMINANCE}, {dst_channels = {2}})
  device:send(get_luminance)
  device:send(Battery:Get({}))
end

local function device_init(self, device)
  device:set_update_preferences_fn(update_preferences)
end

local homeseer_multi_sensor = {
  zwave_handlers = {
    [cc.BASIC] = {
      [Basic.SET] = basic_set_handler
    },
    [cc.WAKE_UP] = {
      [WakeUp.NOTIFICATION] = wakeup_notification
    }
  },
  lifecycle_handlers = {
    added = added_handler,
    init = device_init,
  },
  NAME = "homeseer multi sensor",
  can_handle = require("homeseer-multi-sensor.can_handle"),
}

return homeseer_multi_sensor
