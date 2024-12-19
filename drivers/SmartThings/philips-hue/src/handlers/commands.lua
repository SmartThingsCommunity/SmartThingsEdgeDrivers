local log = require "log"
local st_utils = require "st.utils"
-- trick to fix the VS Code Lua Language Server typechecking
---@type fun(val: any?, name: string?, multi_line: boolean?): string
st_utils.stringify_table = st_utils.stringify_table

local Consts = require "consts"
local Fields = require "fields"
local HueColorUtils = require "utils.cie_utils"

local utils = require "utils"

-- trick to fix the VS Code Lua Language Server typechecking
---@type fun(val: any?, name: string?, multi_line: boolean?): string
st_utils.stringify_table = st_utils.stringify_table

---@class CommandHandlers
local CommandHandlers = {}

---@param driver HueDriver
---@param device HueChildDevice
---@param args table
local function do_switch_action(driver, device, args)
  local on = args.command == "on"
  local id = device.parent_device_id or device:get_field(Fields.PARENT_DEVICE_ID)
  local bridge_device = utils.get_hue_bridge_for_device(driver, device, id)

  if not bridge_device then
    log.warn(
      "Couldn't get a bridge for light with Child Key " ..
      (device.parent_assigned_child_key or "unexpected nil parent_assigned_child_key"))
    return
  end

  local light_id = utils.get_hue_rid(device)
  local hue_api = bridge_device:get_field(Fields.BRIDGE_API) --[[@as PhilipsHueApi]]

  if not (light_id and hue_api) then
    log.warn(
      string.format(
        "Could not get a proper light resource ID or API instance for %s" ..
        "\n\tLight Resource ID: %s" ..
        "\n\tHue API nil? %s",
        (device.label or device.id or "unknown device"),
        light_id,
        (hue_api == nil)
      )
    )
    return
  end

  local resp, err = hue_api:set_light_on_state(light_id, on)

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
---@param device HueChildDevice
---@param args table
local function do_switch_level_action(driver, device, args)
  local level = st_utils.clamp_value(args.args.level, 1, 100)
  local id = device.parent_device_id or device:get_field(Fields.PARENT_DEVICE_ID)
  local bridge_device = utils.get_hue_bridge_for_device(driver, device, id)

  if not bridge_device then
    log.warn(
      "Couldn't get a bridge for light with Child Key " ..
      (device.parent_assigned_child_key or "unexpected nil parent_assigned_child_key"))
    return
  end

  local light_id = utils.get_hue_rid(device)
  local hue_api = bridge_device:get_field(Fields.BRIDGE_API) --[[@as PhilipsHueApi]]

  if not (light_id and hue_api) then
    log.warn(
      string.format(
        "Could not get a proper light resource ID or API instance for %s" ..
        "\n\tLight Resource ID: %s" ..
        "\n\tHue API nil? %s",
        (device.label or device.id or "unknown device"),
        light_id,
        (hue_api == nil)
      )
    )
    return
  end

  local is_off = device:get_field(Fields.SWITCH_STATE) == "off"

  if is_off then
    local resp, err = hue_api:set_light_on_state(light_id, true)
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

  local resp, err = hue_api:set_light_level(light_id, level)
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
---@param device HueChildDevice
---@param args table
local function do_color_action(driver, device, args)
  local hue, sat = (args.args.color.hue / 100), (args.args.color.saturation / 100)
  if hue == 1 then -- 0 and 360 degrees are equivalent in HSV, but not in our conversion function
    hue = 0
    device:set_field(Fields.WRAPPED_HUE, true)
  end
  local id = device.parent_device_id or device:get_field(Fields.PARENT_DEVICE_ID)
  local bridge_device = utils.get_hue_bridge_for_device(driver, device, id)

  if not bridge_device then
    log.warn(
      "Couldn't get a bridge for light with Child Key " ..
      (device.parent_assigned_child_key or "unexpected nil parent_assigned_child_key"))
    return
  end

  local light_id = utils.get_hue_rid(device)
  local hue_api = bridge_device:get_field(Fields.BRIDGE_API) --[[@as PhilipsHueApi]]

  if not (light_id and hue_api) then
    log.warn(
      string.format(
        "Could not get a proper light resource ID or API instance for %s" ..
        "\n\tLight Resource ID: %s" ..
        "\n\tHue API nil? %s",
        (device.label or device.id or "unknown device"),
        light_id,
        (hue_api == nil)
      )
    )
    return
  end

  local red, green, blue = st_utils.hsv_to_rgb(hue, sat)
  local xy = HueColorUtils.safe_rgb_to_xy(red, green, blue, device:get_field(Fields.GAMUT))

  local resp, err = hue_api:set_light_color_xy(light_id, xy)
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

-- Function to allow changes to "setHue" attribute to Philips Hue light devices
---@param driver HueDriver
---@param device HueChildDevice
---@param args table
local function do_setHue_action(driver, device, args)

  -- Use existing 'saturation' value for device or set to 0 and pass arg values to function 'do_color_action'
  local currentSaturation = device:get_field(Fields.COLOR_SATURATION) or 0
  args.args.color = {
    hue = args.args.hue,
    saturation = currentSaturation
  }
  do_color_action(driver, device, args)
end

-- Function to allow changes to "setSaturation" attribute to Philips Hue light devices
---@param driver HueDriver
---@param device HueChildDevice
---@param args table
local function do_setSaturation_action(driver, device, args)

  -- Use existing 'hue' value for device or set to 0 and pass arg values to function 'do_color_action'
  local currentHue = device:get_field(Fields.COLOR_HUE) or 0
  args.args.color = {
    hue = currentHue,
    saturation = args.args.saturation
  }
  do_color_action(driver, device, args)
end

---@param driver HueDriver
---@param device HueChildDevice
---@param args table
local function do_color_temp_action(driver, device, args)
  local kelvin = args.args.temperature
  local id = device.parent_device_id or device:get_field(Fields.PARENT_DEVICE_ID)
  local bridge_device = utils.get_hue_bridge_for_device(driver, device, id)

  if not bridge_device then
    log.warn(
      "Couldn't get a bridge for light with Child Key " ..
      (device.parent_assigned_child_key or "unexpected nil parent_assigned_child_key"))
    return
  end

  local light_id = utils.get_hue_rid(device)
  local hue_api = bridge_device:get_field(Fields.BRIDGE_API) --[[@as PhilipsHueApi]]

  if not (light_id and hue_api) then
    log.warn(
      string.format(
        "Could not get a proper light resource ID or API instance for %s" ..
        "\n\tLight Resource ID: %s" ..
        "\n\tHue API nil? %s",
        (device.label or device.id or "unknown device"),
        light_id,
        (hue_api == nil)
      )
    )
    return
  end

  local min = device:get_field(Fields.MIN_KELVIN) or Consts.MIN_TEMP_KELVIN_WHITE_AMBIANCE
  local clamped_kelvin = st_utils.clamp_value(kelvin, min, Consts.MAX_TEMP_KELVIN)
  local mirek = math.floor(utils.kelvin_to_mirek(clamped_kelvin))

  local resp, err = hue_api:set_light_color_temp(light_id, mirek)

  if not resp or (resp.errors and #resp.errors == 0) then
    if err ~= nil then
      log.error_with({ hub_logs = true }, "Error performing color temp action: " .. err)
    elseif resp and #resp.errors > 0 then
      for _, error in ipairs(resp.errors) do
        log.error_with({ hub_logs = true }, "Error returned in Hue response: " .. error.description)
      end
    end
  end
end

---@param driver HueDriver
---@param device HueChildDevice
---@param args table
function CommandHandlers.switch_on_handler(driver, device, args)
  do_switch_action(driver, device, args)
end

---@param driver HueDriver
---@param device HueChildDevice
---@param args table
function CommandHandlers.switch_off_handler(driver, device, args)
  do_switch_action(driver, device, args)
end

---@param driver HueDriver
---@param device HueChildDevice
---@param args table
function CommandHandlers.switch_level_handler(driver, device, args)
  do_switch_level_action(driver, device, args)
end

---@param driver HueDriver
---@param device HueChildDevice
---@param args table
function CommandHandlers.set_color_handler(driver, device, args)
  do_color_action(driver, device, args)
end

---@param driver HueDriver
---@param device HueChildDevice
---@param args table
function CommandHandlers.set_hue_handler(driver, device, args)
  do_setHue_action(driver, device, args)
end

---@param driver HueDriver
---@param device HueChildDevice
---@param args table
function CommandHandlers.set_saturation_handler(driver, device, args)
  do_setSaturation_action(driver, device, args)
end

---@param driver HueDriver
---@param device HueChildDevice
---@param args table
function CommandHandlers.set_color_temp_handler(driver, device, args)
  do_color_temp_action(driver, device, args)
end

local refresh_handlers = require "handlers.refresh_handlers"

---@param driver HueDriver
---@param device HueDevice
---@param cmd table?
---@return table? refreshed_device_info
function CommandHandlers.refresh_handler(driver, device, cmd)
  return refresh_handlers.handler_for_device_type(utils.determine_device_type(device))(driver, device, cmd)
end

return CommandHandlers
