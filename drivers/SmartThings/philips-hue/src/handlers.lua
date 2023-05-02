local Fields = require "hue.fields"
local HueApi = require "hue.api"
local HueColorUtils = require "hue.cie_utils"
local log = require "log"

local capabilities = require "st.capabilities"
local st_utils = require "st.utils"

local handlers = {}

---@param driver HueDriver
---@param device HueChildDevice
local function do_switch_action(driver, device, args)
  local on = args.command == "on"
  local id = device.parent_device_id or device:get_field(Fields.PARENT_DEVICE_ID)
  local bridge_device = driver:get_device_info(id)

  if not bridge_device then
    log.warn("Couldn't get a bridge for light with Child Key " .. device.parent_assigned_child_key)
    return
  end

  local light_id = device:get_field(Fields.RESOURCE_ID)
  local hue_api = bridge_device:get_field(Fields.BRIDGE_API)

  if not (light_id or hue_api) then
    log.warn("Could not get a proper light resource ID or API instance for ", device.label)
    return
  end

  local resp, err = hue_api:set_light_on_state(light_id, on)

  if not resp or (resp.errors and #resp.errors == 0) then
    if err ~= nil then
      log.error("Error performing on/off action: " .. err)
    elseif resp and #resp.errors > 0 then
      for _, error in ipairs(resp.errors) do
        log.error("Error returned in Hue response: " .. error.description)
      end
    end
  end
end

---@param driver HueDriver
---@param device HueChildDevice
local function do_switch_level_action(driver, device, args)
  local level = st_utils.clamp_value(args.args.level, 1, 100)
  local id = device.parent_device_id or device:get_field(Fields.PARENT_DEVICE_ID)
  local bridge_device = driver:get_device_info(id)

  if not bridge_device then
    log.warn("Couldn't get a bridge for light with Child Key " .. device.parent_assigned_child_key)
    return
  end

  local light_id = device:get_field(Fields.RESOURCE_ID)
  local hue_api = bridge_device:get_field(Fields.BRIDGE_API)

  if not (light_id or hue_api) then
    log.warn("Could not get a proper light resource ID or API instance for ", device.label)
    return
  end

  local is_off = device:get_latest_state(
        "main", capabilities.switch.ID, capabilities.switch.switch.NAME) == "off"

  if is_off then
    local resp, err = hue_api:set_light_on_state(light_id, true)
    if not resp or (resp.errors and #resp.errors == 0) then
      if err ~= nil then
        log.error("Error performing on/off action: " .. err)
      elseif resp and #resp.errors > 0 then
        for _, error in ipairs(resp.errors) do
          log.error("Error returned in Hue response: " .. error.description)
        end
      end
    end
  end

  local resp, err = hue_api:set_light_level(light_id, level)
  if not resp or (resp.errors and #resp.errors == 0) then
    if err ~= nil then
      log.error("Error performing switch level action: " .. err)
    elseif resp and #resp.errors > 0 then
      for _, error in ipairs(resp.errors) do
        log.error("Error returned in Hue response: " .. error.description)
      end
    end
  end
end

---@param driver HueDriver
---@param device HueChildDevice
local function do_color_action(driver, device, args)
  local hue, sat = (args.args.color.hue / 100), (args.args.color.saturation / 100)
  if hue == 1 then -- 0 and 360 degrees are equivalent in HSV, but not in our conversion function
    hue = 0
    device:set_field(Fields.WRAPPED_HUE, true)
  end
  local id = device.parent_device_id or device:get_field(Fields.PARENT_DEVICE_ID)
  local bridge_device = driver:get_device_info(id)

  if not bridge_device then
    log.warn("Couldn't get a bridge for light with Child Key " .. device.parent_assigned_child_key)
    return
  end

  local light_id = device:get_field(Fields.RESOURCE_ID)
  local hue_api = bridge_device:get_field(Fields.BRIDGE_API)

  if not (light_id or hue_api) then
    log.warn("Could not get a proper light resource ID or API instance for ", device.label)
    return
  end

  local red, green, blue = st_utils.hsv_to_rgb(hue, sat)
  local xy = HueColorUtils.safe_rgb_to_xy(red, green, blue, device:get_field(Fields.GAMUT))

  local resp, err = hue_api:set_light_color_xy(light_id, xy)
  if not resp or (resp.errors and #resp.errors == 0) then
    if err ~= nil then
      log.error("Error performing color action: " .. err)
    elseif resp and #resp.errors > 0 then
      for _, error in ipairs(resp.errors) do
        log.error("Error returned in Hue response: " .. error.description)
      end
    end
  end
end

function handlers.kelvin_to_mirek(kelvin) return 1000000 / kelvin end

function handlers.mirek_to_kelvin(mirek) return 1000000 / mirek end

---@param driver HueDriver
---@param device HueChildDevice
local function do_color_temp_action(driver, device, args)
  local kelvin = args.args.temperature
  local id = device.parent_device_id or device:get_field(Fields.PARENT_DEVICE_ID)
  local bridge_device = driver:get_device_info(id)

  if not bridge_device then
    log.warn("Couldn't get a bridge for light with Child Key " .. device.parent_assigned_child_key)
    return
  end

  local light_id = device:get_field(Fields.RESOURCE_ID)
  local hue_api = bridge_device:get_field(Fields.BRIDGE_API)

  if not (light_id or hue_api) then
    log.warn("Could not get a proper light resource ID or API instance for ", device.label)
    return
  end

  local min = device:get_field(Fields.MIN_KELVIN) or HueApi.MIN_TEMP_KELVIN_WHITE_AMBIANCE
  local clamped_kelvin = st_utils.clamp_value(kelvin, min, HueApi.MAX_TEMP_KELVIN)
  local mirek = math.floor(handlers.kelvin_to_mirek(clamped_kelvin))

  local resp, err = hue_api:set_light_color_temp(light_id, mirek)

  if not resp or (resp.errors and #resp.errors == 0) then
    if err ~= nil then
      log.error("Error performing color temp action: " .. err)
    elseif resp and #resp.errors > 0 then
      for _, error in ipairs(resp.errors) do
        log.error("Error returned in Hue response: " .. error.description)
      end
    end
  end
end

---@param driver HueDriver
---@param device HueChildDevice
function handlers.switch_on_handler(driver, device, args)
  do_switch_action(driver, device, args)
end

---@param driver HueDriver
---@param device HueChildDevice
function handlers.switch_off_handler(driver, device, args)
  do_switch_action(driver, device, args)
end

---@param driver HueDriver
---@param device HueChildDevice
function handlers.switch_level_handler(driver, device, args)
  do_switch_level_action(driver, device, args)
end

---@param driver HueDriver
---@param device HueChildDevice
function handlers.set_color_handler(driver, device, args)
  do_color_action(driver, device, args)
end

---@param driver HueDriver
---@param device HueChildDevice
function handlers.set_color_temp_handler(driver, device, args)
  do_color_temp_action(driver, device, args)
end

---@param driver HueDriver
---@param light_device HueChildDevice
local function do_refresh_light(driver, light_device)
  local light_resource_id = light_device:get_field(Fields.RESOURCE_ID)
  local bridge_id = light_device.parent_device_id or light_device:get_field(Fields.PARENT_DEVICE_ID)
  local bridge_device = driver:get_device_info(bridge_id)

  if not bridge_device then
    log.warn("Couldn't get Hue bridge for light " .. light_device.label)
    return
  end

  if not bridge_device:get_field(Fields._INIT) then
    log.warn("Bridge for light not yet initialized, can't refresh yet.")
    driver._lights_pending_refresh[light_device.id] = light_device
    return
  end

  local hue_api = bridge_device:get_field(Fields.BRIDGE_API)
  local success = false
  local count = 0
  local num_attempts = 3
  repeat
    local light_resp, err = hue_api:get_light_by_id(light_resource_id)
    count = count + 1
    if err ~= nil then
      log.error(err)
    elseif light_resp ~= nil then
      if #light_resp.errors > 0 then
        for _, err in ipairs(light_resp.errors) do
          log.error("Error in Hue API response: " .. err.description)
        end
      else
        for _, light_info in ipairs(light_resp.data) do
          if light_info.id == light_resource_id then
            if light_info.color ~= nil and light_info.color.gamut then
              light_device:set_field(Fields.GAMUT, light_info.color.gamut_type, { persist = true })
            end
            driver.emit_light_status_events(light_device, light_info)
            success = true
          end
        end
      end
    end
  until success or count >= num_attempts
end

---@param driver HueDriver
---@param bridge_device HueBridgeDevice
local function do_refresh_all_for_bridge(driver, bridge_device)
  local child_devices = bridge_device:get_child_list() --[=[@as HueChildDevice[]]=]
  for _, device in ipairs(child_devices) do
    local device_type = device:get_field(Fields.DEVICE_TYPE)
    if device_type == "light" then
      do_refresh_light(driver, device)
    end
  end
end

---@param driver HueDriver
---@param device HueDevice
function handlers.refresh_handler(driver, device, cmd)
  if device:get_field(Fields.DEVICE_TYPE) == "bridge" then
    do_refresh_all_for_bridge(driver, device --[[@as HueBridgeDevice]])
  elseif device:get_field(Fields.DEVICE_TYPE) == "light" then
    do_refresh_light(driver, device --[[@as HueChildDevice]])
  end
end

return handlers
