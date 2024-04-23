local capabilities = require "st.capabilities"
local log = require "log"
local st_utils = require "st.utils"
-- trick to fix the VS Code Lua Language Server typechecking
---@type fun(val: table, name: string?, multi_line: boolean?): string
st_utils.stringify_table = st_utils.stringify_table

local Consts = require "consts"
local Fields = require "fields"
local HueColorUtils = require "hue.cie_utils"
local HueDeviceTypes = require "hue_device_types"

local utils = require "utils"

local syncCapabilityId = "samsungim.hueSyncMode"
local hueSyncMode = capabilities[syncCapabilityId]

---@class AttributeEmitters
local AttributeEmitters = {}

local device_type_emitter_map = {}

---@param light_device HueChildDevice
---@param light_repr table
local function _emit_light_events_inner(light_device, light_repr)
  if light_device ~= nil then
    if light_repr.status then
      if light_repr.status == "connected" then
        light_device.log.info_with({hub_logs=true}, "Light status event, marking device online")
        light_device:online()
        light_device:set_field(Fields.IS_ONLINE, true)
      elseif light_repr.status == "connectivity_issue" then
        light_device.log.info_with({hub_logs=true}, "Light status event, marking device offline")
        light_device:set_field(Fields.IS_ONLINE, false)
        light_device:offline()
        return
      end
    end

    if light_device:get_field(Fields.IS_ONLINE) ~= true then
      return
    end

    if light_repr.mode then
      light_device:emit_event(hueSyncMode.mode(light_repr.mode))
    end

    if light_repr.on and light_repr.on.on then
      light_device:emit_event(capabilities.switch.switch.on())
    elseif light_repr.on and not light_repr.on.on then
      light_device:emit_event(capabilities.switch.switch.off())
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
      local mirek = Consts.DEFAULT_MIREK
      if light_repr.color_temperature.mirek_valid then
        mirek = light_repr.color_temperature.mirek
      end
      local min = light_device:get_field(Fields.MIN_KELVIN) or Consts.MIN_TEMP_KELVIN_WHITE_AMBIANCE
      local kelvin = math.floor(
        st_utils.clamp_value(utils.mirek_to_kelvin(mirek), min, Consts.MAX_TEMP_KELVIN)
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
      end
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
  local success, result = pcall(_emit_light_events_inner, light_device, light_repr)
  if not success then
    log.error_with({ hub_logs = true }, string.format("Failed to invoke emit light status handler. Reason: %s", result))
  end
  return result
end

local function noop_event_emitter(driver, device, ...)
  local label = (device and device.label) or "Unknown Device Name"
  local device_type = (device and device:get_field(Fields.DEVICE_TYPE)) or "Unknown Device Type"
  log.warn(string.format("Tried to find attribute event emitter for device [%s] of unsupported type [%s], ignoring", label, device_type))
end

function AttributeEmitters.emitter_for_device_type(device_type)
  return device_type_emitter_map[device_type] or noop_event_emitter
end

device_type_emitter_map[HueDeviceTypes.LIGHT] = AttributeEmitters.emit_light_attribute_events

return AttributeEmitters
