-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
--- @type st.zwave.CommandClass.SwitchMultilevel
local SwitchMultilevel = (require "st.zwave.CommandClass.SwitchMultilevel")({version=4})
--- @type st.zwave.CommandClass.Meter
local Meter = (require "st.zwave.CommandClass.Meter")({ version = 3 })
--- @type st.zwave.CommandClass.Association
local Association = (require "st.zwave.CommandClass.Association")({ version = 1 })
--- @type st.device
local st_device = require "st.device"

local supported_button_values = {
    ["button1"] = {"pushed","held","down_hold","pushed_2x","pushed_3x","pushed_4x","pushed_5x"},
    ["button2"] = {"pushed","held","down_hold","pushed_2x","pushed_3x","pushed_4x","pushed_5x"},
    ["button3"] = {"pushed"}
}

local LED_BAR_COMPONENT_NAME = "LEDColorConfiguration"

local function refresh_handler(driver, device)
  device:send(SwitchMultilevel:Get({}))
  device:send(Meter:Get({ scale = Meter.scale.electric_meter.WATTS }))
  device:send(Meter:Get({ scale = Meter.scale.electric_meter.KILOWATT_HOURS }))
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
      local ledBarComponent = device.profile.components[LED_BAR_COMPONENT_NAME]
      if ledBarComponent ~= nil then
        device:emit_component_event(ledBarComponent, capabilities.colorControl.hue(1))
        device:emit_component_event(ledBarComponent, capabilities.colorControl.saturation(1))
      end
    else
      device:emit_event(capabilities.colorControl.hue(1))
      device:emit_event(capabilities.colorControl.saturation(1))
      device:emit_event(capabilities.colorTemperature.colorTemperatureRange({ value = {minimum = 2700, maximum = 6500} }))
      device:emit_event(capabilities.switchLevel.level(100))
      device:emit_event(capabilities.switch.switch("off"))
    end
  end

local lzw31_sn = {
  NAME = "Inovelli LZW31-SN Z-Wave Dimmer",
  lifecycle_handlers = {
    added = device_added,
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = refresh_handler
    }
  },
  can_handle = require("inovelli.lzw31-sn.can_handle")
}

return lzw31_sn