local capabilities = require "st.capabilities"
local log = require "log"
local st_utils = require "st.utils"
-- trick to fix the VS Code Lua Language Server typechecking
---@type fun(val: any?, name: string?, multi_line: boolean?): string
st_utils.stringify_table = st_utils.stringify_table

local Consts = require "consts"
local Fields = require "fields"
local HueColorUtils = require "utils.cie_utils"
local HueDeviceTypes = require "hue_device_types"

local utils = require "utils"

local syncCapabilityId = "samsungim.hueSyncMode"
local hueSyncMode = capabilities[syncCapabilityId]

---@class AttributeEmitters
local AttributeEmitters = {}

---@type { [HueDeviceTypes]: fun(device: HueDevice, ...)}
local device_type_emitter_map = {}

---@param light_device HueChildDevice
---@param light_repr HueLightInfo
local function _emit_light_events_inner(light_device, light_repr)
  if light_device ~= nil then
    if light_device:get_field(Fields.IS_ONLINE) ~= true then
      return
    end

    if light_repr.mode then
      light_device:emit_event(hueSyncMode.mode(light_repr.mode))
    end

    if light_repr.on and light_repr.on.on then
      light_device:emit_event(capabilities.switch.switch.on())
      light_device:set_field(Fields.SWITCH_STATE, "on", {persist = true})
    elseif light_repr.on and not light_repr.on.on then
      light_device:emit_event(capabilities.switch.switch.off())
      light_device:set_field(Fields.SWITCH_STATE, "off", {persist = true})
    end

    if light_repr.dimming then
      local adjusted_level = st_utils.round(st_utils.clamp_value(light_repr.dimming.brightness, 1, 100))
      if utils.is_nan(adjusted_level) then
        light_device.log.warn(
          string.format(
            "Non numeric value %s computed for switchLevel Attribute Event, ignoring.",
            adjusted_level
          )
        )
      else
        light_device:emit_event(capabilities.switchLevel.level(adjusted_level))
      end
    end

    if light_repr.color_temperature then
      local mirek = Consts.DEFAULT_MIN_MIREK
      if light_repr.color_temperature.mirek_valid then
        mirek = light_repr.color_temperature.mirek
      end
      local mirek_schema = light_repr.color_temperature.mirek_schema or {
        mirek_minimum = Consts.DEFAULT_MIN_MIREK,
        mirek_maximum = Consts.DEFAULT_MAX_MIREK
      }

      -- See note in `src/handlers/lifecycle_handlers/light.lua` about min/max relationship
      -- if the below is not intuitive.
      local min_kelvin = light_device:get_field(Fields.MIN_KELVIN)
      local api_min_kelvin = math.floor(utils.mirek_to_kelvin(mirek_schema.mirek_maximum) or Consts.MIN_TEMP_KELVIN_COLOR_AMBIANCE)
      local max_kelvin = light_device:get_field(Fields.MAX_KELVIN)
      local api_max_kelvin = math.floor(utils.mirek_to_kelvin(mirek_schema.mirek_minimum) or Consts.MAX_TEMP_KELVIN)

      local update_range = false
      if min_kelvin ~= api_min_kelvin then
        update_range = true
        min_kelvin = api_min_kelvin
        light_device:set_field(Fields.MIN_KELVIN, min_kelvin, { persist = true })
      end

      if max_kelvin ~= api_max_kelvin then
        update_range = true
        max_kelvin = api_max_kelvin
        light_device:set_field(Fields.MAX_KELVIN, max_kelvin, { persist = true })
      end

      if update_range then
        light_device:emit_event(capabilities.colorTemperature.colorTemperatureRange({ minimum = min_kelvin, maximum = max_kelvin }))
      end

      -- local min =  or Consts.MIN_TEMP_KELVIN_WHITE_AMBIANCE
      local kelvin = math.floor(
        st_utils.clamp_value(utils.mirek_to_kelvin(mirek), min_kelvin, max_kelvin)
      )
      if utils.is_nan(kelvin) then
        light_device.log.warn(
          string.format(
            "Non numeric value %s computed for colorTemperature Attribute Event, ignoring.",
            kelvin
          )
        )
      else
        light_device:emit_event(capabilities.colorTemperature.colorTemperature(kelvin))
      end
    end

    if light_repr.color then
      light_device:set_field(Fields.GAMUT, light_repr.color.gamut, { persist = true })
      local r, g, b = HueColorUtils.safe_xy_to_rgb(light_repr.color.xy, light_repr.color.gamut)
      local hue, sat, _ = st_utils.rgb_to_hsv(r, g, b)
      -- We sent a command where hue == 100 and wrapped the value to 0, reverse that here
      if light_device:get_field(Fields.WRAPPED_HUE) == true and (hue + .05 >= 1 or hue - .05 <= 0) then
        hue = 1
        light_device:set_field(Fields.WRAPPED_HUE, false)
      end

      local adjusted_hue = st_utils.clamp_value(st_utils.round(hue * 100), 0, 100)
      local adjusted_sat = st_utils.clamp_value(st_utils.round(sat * 100), 0, 100)

      if utils.is_nan(adjusted_hue) then
        light_device.log.warn(
          string.format(
            "Non numeric value %s computed for colorControl.hue Attribute Event, ignoring.",
            adjusted_hue
          )
        )
      else
        light_device:emit_event(capabilities.colorControl.hue(adjusted_hue))
        light_device:set_field(Fields.COLOR_HUE, adjusted_hue, {persist = true})
      end

      if utils.is_nan(adjusted_sat) then
        light_device.log.warn(
          string.format(
            "Non numeric value %s computed for colorControl.saturation Attribute Event, ignoring.",
            adjusted_sat
          )
        )
      else
        light_device:emit_event(capabilities.colorControl.saturation(adjusted_sat))
        light_device:set_field(Fields.COLOR_SATURATION, adjusted_sat, {persist = true})
      end
    end
  end
end

function AttributeEmitters.connectivity_update(child_device, zigbee_status)
  if child_device == nil or (child_device and child_device.id == nil) then
    log.warn("Tried to emit attribute events for a device that has been deleted")
    return
  end

  if zigbee_status == nil then
    log.error_with({ hub_logs = true },
    string.format("nil zigbee_status sent to connectivity_update for %s",
        (child_device and (child_device.label or child_device.id)) or "unknown device"))
    return
  end

  if zigbee_status.status == "connected" then
    child_device.log.info_with({hub_logs=true}, "Device zigbee status event, marking device online")
    child_device:online()
    child_device:set_field(Fields.IS_ONLINE, true)
  elseif zigbee_status.status == "connectivity_issue" then
    child_device.log.info_with({hub_logs=true}, "Device zigbee status event, marking device offline")
    child_device:set_field(Fields.IS_ONLINE, false)
    child_device:offline()
  end
end

function AttributeEmitters.emit_button_attribute_events(button_device, button_info)
  if button_device == nil or (button_device and button_device.id == nil) then
    log.warn("Tried to emit attribute events for a device that has been deleted")
    return
  end

  if button_info == nil then
    log.error_with({ hub_logs = true },
    string.format("nil button info sent to emit_button_attribute_events for %s",
        (button_device and (button_device.label or button_device.id)) or "unknown device"))
    return
  end

  if button_info.power_state and type(button_info.power_state.battery_level) == "number" then
    log.debug("emit power")
    button_device:emit_event(
      capabilities.battery.battery(
        st_utils.clamp_value(button_info.power_state.battery_level, 0, 100)
      )
    )
  end

  local button_idx_map = button_device:get_field(Fields.BUTTON_INDEX_MAP)
  if not button_idx_map then
    log.error(
      string.format(
        "Button ID to Button Index map lost, " ..
        "cannot find componenet to emit attribute event on for button [%s]",
        (button_device and button_device.lable) or "unknown button"
      )
    )
    return
  end

  local idx = button_idx_map[button_info.id] or 1
  local component_idx
  if idx == 1 then
    component_idx = "main"
  else
    component_idx = string.format("button%s", idx)
  end

  local button_report = (button_info.button and button_info.button.button_report) or { event = "" }

  if button_report.event == "long_press" and not button_device:get_field("button_held") then
    button_device:set_field("button_held", true)
    button_device.profile.components[component_idx]:emit_event(
      capabilities.button.button.held({state_change = true})
    )
  end

  if button_report.event == "long_release" and button_device:get_field("button_held") then
    button_device:set_field("button_held", false)
  end

  if button_report.event == "short_release" and not button_device:get_field("button_held") then
    button_device.profile.components[component_idx]:emit_event(
      capabilities.button.button.pushed({state_change = true})
    )
  end
end

function AttributeEmitters.emit_contact_sensor_attribute_events(sensor_device, sensor_info)
  if sensor_device == nil or (sensor_device and sensor_device.id == nil) then
    log.warn("Tried to emit attribute events for a device that has been deleted")
    return
  end

  if sensor_info == nil then
    log.error_with({ hub_logs = true },
    string.format("nil sensor_info sent to emit_contact_sensor_attribute_events for %s",
        (sensor_device and (sensor_device.label or sensor_device.id)) or "unknown device"))
    return
  end

  if sensor_info.power_state  and type(sensor_info.power_state.battery_level) == "number" then
    log.debug("emit power")
    sensor_device:emit_event(capabilities.battery.battery(st_utils.clamp_value(sensor_info.power_state.battery_level, 0, 100)))
  end

  if sensor_info.tamper_reports then
    log.debug("emit tamper")
    local tampered = false
    for _, tamper in ipairs(sensor_info.tamper_reports) do
      if tamper.state == "tampered" then
        tampered = true
        break
      end
    end

    if tampered then
      sensor_device:emit_event(capabilities.tamperAlert.tamper.detected())
    else
      sensor_device:emit_event(capabilities.tamperAlert.tamper.clear())
    end
  end

  if sensor_info.contact_report then
    log.debug("emit contact")
    if sensor_info.contact_report.state == "contact" then
      sensor_device:emit_event(capabilities.contactSensor.contact.closed())
    else
      sensor_device:emit_event(capabilities.contactSensor.contact.open())
    end
  end
end

function AttributeEmitters.emit_motion_sensor_attribute_events(sensor_device, sensor_info)
  if sensor_device == nil or (sensor_device and sensor_device.id == nil) then
    log.warn("Tried to emit attribute events for a device that has been deleted")
    return
  end

  if sensor_info == nil then
    log.error_with({ hub_logs = true },
    string.format("nil sensor_info sent to emit_motion_sensor_attribute_events for %s",
        (sensor_device and (sensor_device.label or sensor_device.id)) or "unknown device"))
    return
  end

  if sensor_info.power_state  and type(sensor_info.power_state.battery_level) == "number" then
    log.debug("emit power")
    sensor_device:emit_event(capabilities.battery.battery(st_utils.clamp_value(sensor_info.power_state.battery_level, 0, 100)))
  end

  if sensor_info.temperature and sensor_info.temperature.temperature_valid then
    log.debug("emit temp")
    sensor_device:emit_event(capabilities.temperatureMeasurement.temperature({
      value = sensor_info.temperature.temperature,
      unit = "C"
    }))
  end

  if sensor_info.light and sensor_info.light.light_level_valid then
    log.debug("emit light")
    -- From the Hue docs: Light level in 10000*log10(lux) +1
    local raw_light_level = sensor_info.light.light_level
    -- Convert from the Hue value to lux
    local lux = st_utils.round(10^((raw_light_level - 1) / 10000))
    sensor_device:emit_event(capabilities.illuminanceMeasurement.illuminance(lux))
  end

  if sensor_info.motion and sensor_info.motion.motion_valid then
    log.debug("emit motion")
    if sensor_info.motion.motion then
      sensor_device:emit_event(capabilities.motionSensor.motion.active())
    else
      sensor_device:emit_event(capabilities.motionSensor.motion.inactive())
    end
  end
end

---@param light_device HueChildDevice
---@param light_repr table
function AttributeEmitters.emit_light_attribute_events(light_device, light_repr)
  if light_device == nil or (light_device and light_device.id == nil) then
    log.warn("Tried to emit light status event for device that has been deleted")
    return
  end

  if light_repr == nil then
    log.error_with({ hub_logs = true },
    string.format("nil light_repr sent to emit_light_attribute_events for %s",
        (light_device and (light_device.label or light_device.id)) or "unknown device"))
    return
  end
  local success, maybe_err = pcall(_emit_light_events_inner, light_device, light_repr)
  if not success then
    log.error_with({ hub_logs = true }, string.format("Failed to invoke emit light status handler. Reason: %s", maybe_err))
  end
end

local function noop_event_emitter(device, ...)
  local label = (device and device.label) or "Unknown Device Name"
  local device_type = (device and utils.determine_device_type(device)) or "Unknown Device Type"
  log.warn(string.format("Tried to find attribute event emitter for device [%s] of unsupported type [%s], ignoring", label, device_type))
end

function AttributeEmitters.emitter_for_device_type(device_type)
  return device_type_emitter_map[device_type] or noop_event_emitter
end

-- TODO: Generalize this like the other handlers, and maybe even separate out non-primary services
device_type_emitter_map[HueDeviceTypes.BUTTON] = AttributeEmitters.emit_button_attribute_events
device_type_emitter_map[HueDeviceTypes.CONTACT] = AttributeEmitters.emit_contact_sensor_attribute_events
device_type_emitter_map[HueDeviceTypes.LIGHT] = AttributeEmitters.emit_light_attribute_events
device_type_emitter_map[HueDeviceTypes.MOTION] = AttributeEmitters.emit_motion_sensor_attribute_events

return AttributeEmitters
