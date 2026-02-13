local log = require "log"
local st_utils = require "st.utils"
local Consts = require "consts"
local Fields = require "fields"
local HueColorUtils = require "utils.cie_utils"
local grouped_utils = require "utils.grouped_utils"
local utils = require "utils"


---@class GroupedLightCommandHandlers
local GroupedLightCommandHandlers = {}

---@param driver HueDriver
---@param bridge_device HueBridgeDevice
---@param group table
---@param args table
local function do_switch_action(driver, bridge_device, group, args)
  local on = args.command == "on"

  local grouped_light_id = group.grouped_light_rid
  if not grouped_light_id then
    log.error(string.format("Couldn't find grouped light id for group %s",
      group.id or "unknown group id"))
    return
  end

  local hue_api = bridge_device:get_field(Fields.BRIDGE_API) --[[@as PhilipsHueApi]]
  if not hue_api then
    log.error(string.format("Couldn't find api instance for bridge %s",
      bridge_device.label or bridge_device.id or "unknown bridge"))
    return
  end

  local resp, err = hue_api:set_grouped_light_on_state(grouped_light_id, on)
  if not resp or (resp.errors and #resp.errors == 0) then
    if err ~= nil then
      log.error_with({ hub_logs = true }, "Error performing on/off action: " .. err)
    elseif resp and #resp.errors > 0 then
      for _, error in ipairs(resp.errors) do
        log.error_with({ hub_logs = true }, "Error returned in Hue response: " .. error.description)
      end
    end
  end
end

---@param driver HueDriver
---@param bridge_device HueBridgeDevice
---@param group table
---@param args table
local function do_switch_level_action(driver, bridge_device, group, args)
  local level = st_utils.clamp_value(args.args.level, 1, 100)

  local grouped_light_id = group.grouped_light_rid
  if not grouped_light_id then
    log.error(string.format("Couldn't find grouped light id for group %s",
      group.id or "unknown group id"))
    return
  end

  local hue_api = bridge_device:get_field(Fields.BRIDGE_API) --[[@as PhilipsHueApi]]
  if not hue_api then
    log.error(string.format("Couldn't find api instance for bridge %s",
      bridge_device.label or bridge_device.id or "unknown bridge"))
    return
  end

  -- An individual command checks the state of the device before doing this.
  -- It is probably not worth iterating through all the devices to check their state.
  local resp, err = hue_api:set_grouped_light_on_state(grouped_light_id, true)
  if not resp or (resp.errors and #resp.errors == 0) then
    if err ~= nil then
      log.error_with({ hub_logs = true }, "Error performing on/off action: " .. err)
    elseif resp and #resp.errors > 0 then
      for _, error in ipairs(resp.errors) do
        log.error_with({ hub_logs = true }, "Error returned in Hue response: " .. error.description)
      end
    end
  end

  local resp, err = hue_api:set_grouped_light_level(grouped_light_id, level)
  if not resp or (resp.errors and #resp.errors == 0) then
    if err ~= nil then
      log.error_with({ hub_logs = true }, "Error performing switch level action: " .. err)
    elseif resp and #resp.errors > 0 then
      for _, error in ipairs(resp.errors) do
        log.error_with({ hub_logs = true }, "Error returned in Hue response: " .. error.description)
      end
    end
  end
end


---@param driver HueDriver
---@param bridge_device HueBridgeDevice
---@param group table
---@param args table
---@param aux table auxiliary data needed for the command that the devices all had in common
local function do_color_action(driver, bridge_device, group, args, aux)
  local hue, sat = (args.args.color.hue / 100), (args.args.color.saturation / 100)
  if hue == 1 then -- 0 and 360 degrees are equivalent in HSV, but not in our conversion function
    hue = 0
    grouped_utils.set_field_on_group_devices(group, Fields.WRAPPED_HUE, true)
  end

  local grouped_light_id = group.grouped_light_rid
  if not grouped_light_id then
    log.error(string.format("Couldn't find grouped light id for group %s",
      group.id or "unknown group id"))
    return
  end

  local hue_api = bridge_device:get_field(Fields.BRIDGE_API) --[[@as PhilipsHueApi]]
  if not hue_api then
    log.error(string.format("Couldn't find api instance for bridge %s",
      bridge_device.label or bridge_device.id or "unknown bridge"))
    return
  end

  local red, green, blue = st_utils.hsv_to_rgb(hue, sat)
  local xy = HueColorUtils.safe_rgb_to_xy(red, green, blue, aux[Fields.GAMUT])

  local resp, err = hue_api:set_grouped_light_color_xy(grouped_light_id, xy)
  if not resp or (resp.errors and #resp.errors == 0) then
    if err ~= nil then
      log.error_with({ hub_logs = true }, "Error performing color action: " .. err)
    elseif resp and #resp.errors > 0 then
      for _, error in ipairs(resp.errors) do
        log.error_with({ hub_logs = true }, "Error returned in Hue response: " .. error.description)
      end
    end
  end
end

---@param driver HueDriver
---@param bridge_device HueBridgeDevice
---@param group table
---@param args table
---@param aux table auxiliary data needed for the command that the devices all had in common
local function do_setHue_action(driver, bridge_device, group, args, aux)
  local currentSaturation = aux[Fields.COLOR_SATURATION] or 0
  args.args.color = {
    hue = args.args.hue,
    saturation = currentSaturation
  }
  do_color_action(driver, bridge_device, group, args, aux)
end

---@param driver HueDriver
---@param bridge_device HueBridgeDevice
---@param group table
---@param args table
---@param aux table auxiliary data needed for the command that the devices all had in common
local function do_setSaturation_action(driver, bridge_device, group, args, aux)
  local currentHue = aux[Fields.COLOR_HUE] or 0
  args.args.color = {
    hue = currentHue,
    saturation = args.args.saturation
  }
  do_color_action(driver, bridge_device, group, args, aux)
end

---@param driver HueDriver
---@param bridge_device HueBridgeDevice
---@param group table
---@param args table
---@param aux table auxiliary data needed for the command that the devices all had in common
local function do_color_temp_action(driver, bridge_device, group, args, aux)
  local capabilities = require "st.capabilities"
  local kelvin = args.args.temperature

  local grouped_light_id = group.grouped_light_rid
  if not grouped_light_id then
    log.error(string.format("Couldn't find grouped light id for group %s",
      group.id or "unknown group id"))
    return
  end

  local hue_api = bridge_device:get_field(Fields.BRIDGE_API) --[[@as PhilipsHueApi]]
  if not hue_api then
    log.error(string.format("Couldn't find api instance for bridge %s",
      bridge_device.label or bridge_device.id or "unknown bridge"))
    return
  end

  local min = aux[Fields.MIN_KELVIN] or Consts.MIN_TEMP_KELVIN_WHITE_AMBIANCE
  local clamped_kelvin = st_utils.clamp_value(kelvin, min, Consts.MAX_TEMP_KELVIN)
  local mirek = math.floor(utils.kelvin_to_mirek(clamped_kelvin))

  for _, device in ipairs(group.devices) do
    local current_color_temp = device:get_latest_state("main", capabilities.colorTemperature.ID, capabilities.colorTemperature.colorTemperature.NAME)
    if current_color_temp then
      local current_mirek = math.floor(utils.kelvin_to_mirek(current_color_temp))
      if current_mirek == mirek then
        log.debug(string.format("Color temp change from %dK to %dK results in same mirek value (%d), emitting event directly", current_color_temp, clamped_kelvin, mirek))
        device:emit_event(capabilities.colorTemperature.colorTemperature(clamped_kelvin))
      end
    end
  end

  local resp, err = hue_api:set_grouped_light_color_temp(grouped_light_id, mirek)

  if not resp or (resp.errors and #resp.errors == 0) then
    if err ~= nil then
      log.error_with({ hub_logs = true }, "Error performing color temp action: " .. err)
    elseif resp and #resp.errors > 0 then
      for _, error in ipairs(resp.errors) do
        log.error_with({ hub_logs = true }, "Error returned in Hue response: " .. error.description)
      end
    end
  end
  grouped_utils.set_field_on_group_devices(group, Fields.COLOR_TEMP_SETPOINT, clamped_kelvin);
end

---@param driver HueDriver
---@param bridge_device HueBridgeDevice
---@param group table
---@param args table
---@param aux table auxiliary data needed for the command that the devices all had in common
function GroupedLightCommandHandlers.switch_on_handler(driver, bridge_device, group, args, aux)
  do_switch_action(driver, bridge_device, group, args)
end

---@param driver HueDriver
---@param bridge_device HueBridgeDevice
---@param group table
---@param args table
---@param aux table auxiliary data needed for the command that the devices all had in common
function GroupedLightCommandHandlers.switch_off_handler(driver, bridge_device, group, args, aux)
  do_switch_action(driver, bridge_device, group, args)
end

---@param driver HueDriver
---@param bridge_device HueBridgeDevice
---@param group table
---@param args table
---@param aux table auxiliary data needed for the command that the devices all had in common
function GroupedLightCommandHandlers.switch_level_handler(driver, bridge_device, group, args, aux)
  do_switch_level_action(driver, bridge_device, group, args)
end

---@param driver HueDriver
---@param bridge_device HueBridgeDevice
---@param group table
---@param args table
---@param aux table auxiliary data needed for the command that the devices all had in common
function GroupedLightCommandHandlers.set_color_handler(driver, bridge_device, group, args, aux)
  do_color_action(driver, bridge_device, group, args, aux)
end

---@param driver HueDriver
---@param bridge_device HueBridgeDevice
---@param group table
---@param args table
---@param aux table auxiliary data needed for the command that the devices all had in common
function GroupedLightCommandHandlers.set_hue_handler(driver, bridge_device, group, args, aux)
  do_setHue_action(driver, bridge_device, group, args, aux)
end

---@param driver HueDriver
---@param bridge_device HueBridgeDevice
---@param group table
---@param args table
---@param aux table auxiliary data needed for the command that the devices all had in common
function GroupedLightCommandHandlers.set_saturation_handler(driver, bridge_device, group, args, aux)
  do_setSaturation_action(driver, bridge_device, group, args, aux)
end

---@param driver HueDriver
---@param bridge_device HueBridgeDevice
---@param group table
---@param args table
---@param aux table auxiliary data needed for the command that the devices all had in common
function GroupedLightCommandHandlers.set_color_temp_handler(driver, bridge_device, group, args, aux)
  do_color_temp_action(driver, bridge_device, group, args, aux)
end


return GroupedLightCommandHandlers
