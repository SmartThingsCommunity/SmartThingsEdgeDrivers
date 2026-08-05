-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
--- @type st.zwave.CommandClass.SwitchMultilevel
local SwitchMultilevel = (require "st.zwave.CommandClass.SwitchMultilevel")({version=4})
--- @type st.zwave.CommandClass.SensorMultilevel
local SensorMultilevel = (require "st.zwave.CommandClass.SensorMultilevel")({ version = 7 })
--- @type st.zwave.CommandClass.Meter
local Meter = (require "st.zwave.CommandClass.Meter")({ version = 3 })
--- @type st.zwave.CommandClass.Notification
local Notification = (require "st.zwave.CommandClass.Notification")({ version = 3 })
--- @type st.zwave.CommandClass.Association
local Association = (require "st.zwave.CommandClass.Association")({ version = 1 })
--- @type st.device
local st_device = require "st.device"

local supported_button_values = {
  ["button1"] = {"pushed","held","down_hold","pushed_2x","pushed_3x","pushed_4x","pushed_5x"},
  ["button2"] = {"pushed","held","down_hold","pushed_2x","pushed_3x","pushed_4x","pushed_5x"},
  ["button3"] = {"pushed","held","down_hold","pushed_2x","pushed_3x","pushed_4x","pushed_5x"}
}

local function refresh_handler(driver, device)
  device:send(SwitchMultilevel:Get({}))
  device:send(SensorMultilevel:Get({sensor_type = SensorMultilevel.sensor_type.ILLUMINANCE}))
  device:send(Meter:Get({ scale = Meter.scale.electric_meter.WATTS }))
  device:send(Meter:Get({ scale = Meter.scale.electric_meter.KILOWATT_HOURS }))
  device:send(Notification:Get({notification_type = Notification.notification_type.HOME_SECURITY, event = Notification.event.home_security.MOTION_DETECTION}))
end

local function device_added(driver, device)
  if device.network_type ~= st_device.NETWORK_TYPE_CHILD then
    device:send(Association:Set({grouping_identifier = 1, node_ids = {driver.environment_info.hub_zwave_id}}))
    for _, component in pairs(device.profile.components) do
      if component.id ~= "main" and component.id ~= "LEDColorConfiguration" then
        device:emit_component_event(
          component,
          capabilities.button.supportedButtonValues(
            supported_button_values[component.id],
            { visibility = { displayed = false } }
          )
        )
        device:emit_component_event(
          component,
          capabilities.button.numberOfButtons({value = 1}, { visibility = { displayed = false } })
        )
      end
    end
    refresh_handler(driver, device)
  else
    device:emit_event(capabilities.colorControl.hue(1))
    device:emit_event(capabilities.colorControl.saturation(1))
    device:emit_event(capabilities.colorTemperature.colorTemperatureRange({ value = {minimum = 2700, maximum = 6500} }))
    device:emit_event(capabilities.switchLevel.level(100))
    device:emit_event(capabilities.switch.switch("off"))
  end
end

local vzw32_sn = {
  NAME = "Inovelli VZW32-SN mmWave Dimmer",
  lifecycle_handlers = {
    added = device_added,
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = refresh_handler
    }
  },
  can_handle = require("inovelli.vzw32-sn.can_handle")
}

return vzw32_sn