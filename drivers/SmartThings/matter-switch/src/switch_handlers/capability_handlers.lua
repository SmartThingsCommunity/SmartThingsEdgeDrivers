-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local st_utils = require "st.utils"
local version = require "version"
local switch_utils = require "switch_utils.utils"
local fields = require "switch_utils.fields"

local CapabilityHandlers = {}

-- Include driver-side definitions when lua libs api version is < 11
if version.api < 11 then
  clusters.ValveConfigurationAndControl = require "embedded_clusters.ValveConfigurationAndControl"
end

-- [[ SWITCH CAPABILITY COMMANDS ]] --

function CapabilityHandlers.handle_switch_on(driver, device, cmd)
  if type(device.register_native_capability_cmd_handler) == "function" then
    device:register_native_capability_cmd_handler(cmd.capability, cmd.command)
  end
  local endpoint_id = device:component_to_endpoint(cmd.component)
  --TODO use OnWithRecallGlobalScene for devices with the LT feature
  device:send(clusters.OnOff.server.commands.On(device, endpoint_id))
end

function CapabilityHandlers.handle_switch_off(driver, device, cmd)
  if type(device.register_native_capability_cmd_handler) == "function" then
    device:register_native_capability_cmd_handler(cmd.capability, cmd.command)
  end
  local endpoint_id = device:component_to_endpoint(cmd.component)
  device:send(clusters.OnOff.server.commands.Off(device, endpoint_id))
end


-- [[ SWITCH LEVEL CAPABILITY COMMANDS ]] --

function CapabilityHandlers.handle_switch_set_level(driver, device, cmd)
  if type(device.register_native_capability_cmd_handler) == "function" then
    device:register_native_capability_cmd_handler(cmd.capability, cmd.command)
  end
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local level = st_utils.round(cmd.args.level/100.0 * 254)
  device:send(clusters.LevelControl.server.commands.MoveToLevelWithOnOff(device, endpoint_id, level, cmd.args.rate, 0, 0))
end


-- [[ STATELESS SWITCH LEVEL STEP CAPABILITY COMMANDS ]] --

function CapabilityHandlers.handle_step_level(driver, device, cmd)
  local step_size = math.floor((cmd.args and cmd.args.stepSize or 0)/100.0 * 254)
  if step_size == 0 then return end
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local step_mode = step_size > 0 and clusters.LevelControl.types.StepMode.UP or clusters.LevelControl.types.StepMode.DOWN
  device:send(clusters.LevelControl.server.commands.Step(device, endpoint_id, step_mode, math.abs(step_size), fields.TRANSITION_TIME, fields.OPTIONS_MASK, fields.OPTIONS_OVERRIDE))
end


-- [[ COLOR CONTROL CAPABILITY COMMANDS ]] --

function CapabilityHandlers.handle_set_color(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local req
  local huesat_endpoints = device:get_endpoints(clusters.ColorControl.ID, {feature_bitmap = clusters.ColorControl.FeatureMap.HUE_AND_SATURATION})
  if switch_utils.tbl_contains(huesat_endpoints, endpoint_id) then
    local hue = switch_utils.convert_huesat_st_to_matter(cmd.args.color.hue)
    local sat = switch_utils.convert_huesat_st_to_matter(cmd.args.color.saturation)
    req = clusters.ColorControl.server.commands.MoveToHueAndSaturation(device, endpoint_id, hue, sat, fields.TRANSITION_TIME, fields.OPTIONS_MASK, fields.OPTIONS_OVERRIDE)
  else
    local x, y, _ = st_utils.safe_hsv_to_xy(cmd.args.color.hue, cmd.args.color.saturation)
    req = clusters.ColorControl.server.commands.MoveToColor(device, endpoint_id, x, y, fields.TRANSITION_TIME, fields.OPTIONS_MASK, fields.OPTIONS_OVERRIDE)
  end
  device:send(req)
end

function CapabilityHandlers.handle_set_hue(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local huesat_endpoints = device:get_endpoints(clusters.ColorControl.ID, {feature_bitmap = clusters.ColorControl.FeatureMap.HUE_AND_SATURATION})
  if switch_utils.tbl_contains(huesat_endpoints, endpoint_id) then
    local hue = switch_utils.convert_huesat_st_to_matter(cmd.args.hue)
    local req = clusters.ColorControl.server.commands.MoveToHue(device, endpoint_id, hue, 0, fields.TRANSITION_TIME, fields.OPTIONS_MASK, fields.OPTIONS_OVERRIDE)
    device:send(req)
  else
    device.log.warn("Device does not support huesat features on its color control cluster")
  end
end

function CapabilityHandlers.handle_set_saturation(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local huesat_endpoints = device:get_endpoints(clusters.ColorControl.ID, {feature_bitmap = clusters.ColorControl.FeatureMap.HUE_AND_SATURATION})
  if switch_utils.tbl_contains(huesat_endpoints, endpoint_id) then
    local sat = switch_utils.convert_huesat_st_to_matter(cmd.args.saturation)
    local req = clusters.ColorControl.server.commands.MoveToSaturation(device, endpoint_id, sat, fields.TRANSITION_TIME, fields.OPTIONS_MASK, fields.OPTIONS_OVERRIDE)
    device:send(req)
  else
    device.log.warn("Device does not support huesat features on its color control cluster")
  end
end


-- [[ COLOR TEMPERATURE CAPABILITY COMMANDS ]] --

function CapabilityHandlers.handle_set_color_temperature(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local temp_in_kelvin = cmd.args.temperature
  local min_temp_kelvin = switch_utils.get_field_for_endpoint(device, fields.COLOR_TEMP_BOUND_RECEIVED_KELVIN..fields.COLOR_TEMP_MIN, endpoint_id)
  local max_temp_kelvin = switch_utils.get_field_for_endpoint(device, fields.COLOR_TEMP_BOUND_RECEIVED_KELVIN..fields.COLOR_TEMP_MAX, endpoint_id)

  local temp_in_mired = st_utils.round(fields.MIRED_KELVIN_CONVERSION_CONSTANT/temp_in_kelvin)
  if min_temp_kelvin ~= nil and temp_in_kelvin <= min_temp_kelvin then
    temp_in_mired = switch_utils.get_field_for_endpoint(device, fields.COLOR_TEMP_BOUND_RECEIVED_MIRED..fields.COLOR_TEMP_MAX, endpoint_id)
  elseif max_temp_kelvin ~= nil and temp_in_kelvin >= max_temp_kelvin then
    temp_in_mired = switch_utils.get_field_for_endpoint(device, fields.COLOR_TEMP_BOUND_RECEIVED_MIRED..fields.COLOR_TEMP_MIN, endpoint_id)
  end
  local req = clusters.ColorControl.server.commands.MoveToColorTemperature(device, endpoint_id, temp_in_mired, fields.TRANSITION_TIME, fields.OPTIONS_MASK, fields.OPTIONS_OVERRIDE)
  device:set_field(fields.MOST_RECENT_TEMP, cmd.args.temperature, {persist = true})
  device:send(req)
end


-- [[ STATELESS COLOR TEMPERATURE STEP CAPABILITY COMMANDS ]] --

function CapabilityHandlers.handle_step_color_temperature_by_percent(driver, device, cmd)
  local step_percent_change = cmd.args and cmd.args.stepSize or 0
  if step_percent_change == 0 then return end
  local endpoint_id = device:component_to_endpoint(cmd.component)
  -- before the Matter 1.3 lua libs update (HUB FW 55), there was no ColorControl StepModeEnum type defined
  local step_mode = step_percent_change > 0 and (clusters.ColorControl.types.StepModeEnum and clusters.ColorControl.types.StepModeEnum.DOWN or 3) or (clusters.ColorControl.types.StepModeEnum and clusters.ColorControl.types.StepModeEnum.UP or 1)
  local min_mireds = switch_utils.get_field_for_endpoint(device, fields.COLOR_TEMP_BOUND_RECEIVED_MIRED..fields.COLOR_TEMP_MIN, endpoint_id) or fields.COLOR_TEMPERATURE_MIRED_MIN -- default min mireds
  local max_mireds = switch_utils.get_field_for_endpoint(device, fields.COLOR_TEMP_BOUND_RECEIVED_MIRED..fields.COLOR_TEMP_MAX, endpoint_id) or fields.COLOR_TEMPERATURE_MIRED_MAX -- default max mireds
  local step_size_in_mireds = (max_mireds - min_mireds) * st_utils.round((math.abs(step_percent_change)/100))
  device:send(clusters.ColorControl.server.commands.StepColorTemperature(device, endpoint_id, step_mode, step_size_in_mireds, fields.TRANSITION_TIME, min_mireds, max_mireds, fields.OPTIONS_MASK, fields.OPTIONS_OVERRIDE))
end


-- [[ VALVE CAPABILITY COMMANDS ]] --

function CapabilityHandlers.handle_valve_open(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  device:send(clusters.ValveConfigurationAndControl.server.commands.Open(device, endpoint_id))
end

function CapabilityHandlers.handle_valve_close(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  device:send(clusters.ValveConfigurationAndControl.server.commands.Close(device, endpoint_id))
end


-- [[ LEVEL CAPABILITY COMMANDS ]] --

function CapabilityHandlers.handle_set_level(driver, device, cmd)
  local commands = clusters.ValveConfigurationAndControl.server.commands
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local level = cmd.args.level
  if not level then
    return
  elseif level == 0 then
    device:send(commands.Close(device, endpoint_id))
  else
    device:send(commands.Open(device, endpoint_id, nil, level))
  end
end


-- [[ FAN MODE CAPABILITY COMMANDS ]] --

function CapabilityHandlers.handle_set_fan_mode(driver, device, cmd)
  local fan_mode_id
  if cmd.args.fanMode == capabilities.fanMode.fanMode.low.NAME then
    fan_mode_id = clusters.FanControl.attributes.FanMode.LOW
  elseif cmd.args.fanMode == capabilities.fanMode.fanMode.medium.NAME then
    fan_mode_id = clusters.FanControl.attributes.FanMode.MEDIUM
  elseif cmd.args.fanMode == capabilities.fanMode.fanMode.high.NAME then
    fan_mode_id = clusters.FanControl.attributes.FanMode.HIGH
  elseif cmd.args.fanMode == capabilities.fanMode.fanMode.auto.NAME then
    fan_mode_id = clusters.FanControl.attributes.FanMode.AUTO
  else
    fan_mode_id = clusters.FanControl.attributes.FanMode.OFF
  end
  if fan_mode_id then
    local fan_ep = device:get_endpoints(clusters.FanControl.ID)[1]
    device:send(clusters.FanControl.attributes.FanMode:write(device, fan_ep, fan_mode_id))
  end
end


-- [[ FAN SPEED PERCENT CAPABILITY COMMANDS ]] --

function CapabilityHandlers.handle_fan_speed_set_percent(driver, device, cmd)
  local speed = math.floor(cmd.args.percent)
  local fan_ep = device:get_endpoints(clusters.FanControl.ID)[1]
  device:send(clusters.FanControl.attributes.PercentSetting:write(device, fan_ep, speed))
end


-- [[ ENERGY METER CAPABILITY COMMANDS ]] --

---
--- If a Cumulative Reporting device, this will store the most recent energy meter reading, and all subsequent reports will have this value subtracted
--- from the value reported. Matter, like Zigbee and unlike Z-Wave, does not provide a way to reset the value to zero, so this is an attempt at a workaround.
--- In the case it is a Periodic Reporting device, the reports do not need to be offset, so setting the current energy to 0.0 will do the same thing.
---
function CapabilityHandlers.handle_reset_energy_meter(driver, device, cmd)
  local energy_meter_latest_state = device:get_latest_state(cmd.component, capabilities.energyMeter.ID, capabilities.energyMeter.energy.NAME) or 0.0
  if energy_meter_latest_state ~= 0.0 then
    device:emit_component_event(device.profile.components[cmd.component], capabilities.energyMeter.energy({value = 0.0, unit = "Wh"}))
    -- note: field containing cumulative reports supported is only set on the parent device
    local field_device = device:get_parent_device() or device
    if field_device:get_field(fields.CUMULATIVE_REPORTS_SUPPORTED) then
      local current_offset = device:get_field(fields.ENERGY_METER_OFFSET) or 0.0
      device:set_field(fields.ENERGY_METER_OFFSET, current_offset + energy_meter_latest_state, {persist=true})
    end
  end
end

return CapabilityHandlers
