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

local INOVELLI_VZW32_SN_FINGERPRINTS = {
  { mfr = 0x031E, prod = 0x0017, model = 0x0001 }, -- Inovelli VZW32-SN
}

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
      if component.id ~= "main" and component.id ~= LED_BAR_COMPONENT_NAME then
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

local function can_handle_vzw32_sn(opts, driver, device, ...)
  for _, fingerprint in ipairs(INOVELLI_VZW32_SN_FINGERPRINTS) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      return true
    end
  end
  return false
end

local vzw32_sn = {
  NAME = "Inovelli VZW32-SN",
  lifecycle_handlers = {
    added = device_added,
  },
  can_handle = can_handle_vzw32_sn,
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = refresh_handler
    }
  }
}

return vzw32_sn