local cosock = require "cosock"
local log = require "log"
local st_utils = require "st.utils"
-- trick to fix the VS Code Lua Language Server typechecking
---@type fun(val: any?, name: string?, multi_line: boolean?): string
st_utils.stringify_table = st_utils.stringify_table

local Fields = require "fields"
local HueDeviceTypes = require "hue_device_types"
local MultiServiceDeviceUtils = require "utils.hue_multi_service_device_utils"
local attribute_emitters = require "handlers.attribute_emitters"
local utils = require "utils"

---@class RefreshHandlers
local RefreshHandlers = {}

---@type table<HueDeviceTypes,fun(driver: HueDriver, device: HueDevice, ...)>
local device_type_refresh_handlers_map = {}

local function _refresh_zigbee(device, hue_api, zigbee_status)
  local hue_device_id = device:get_field(Fields.HUE_DEVICE_ID)
  local zigbee_resource_id
  if not zigbee_status then
    local rest_resp, rest_err = hue_api:get_device_by_id(hue_device_id)
    if rest_err ~= nil then
      log.error_with({ hub_logs = true }, rest_err)
      return
    end

    if rest_resp ~= nil then
      if #rest_resp.errors > 0 then
        for _, err in ipairs(rest_resp.errors) do
          log.error_with({ hub_logs = true }, "Error in Hue API response: " .. err.description)
        end
        return
      end

      for _, hue_device in ipairs(rest_resp.data) do
        for _, svc_info in ipairs(hue_device.services or {}) do
          if svc_info.rtype == "zigbee_connectivity" then
            zigbee_resource_id = svc_info.rid
          end
        end
      end
    end

    if not zigbee_resource_id then
      log.error_with({ hub_logs = true }, string.format("could not find zigbee_resource_id for device %s", (device and (device.label or device.id)) or "unknown device"))
      return
    end
    rest_resp, rest_err = hue_api:get_zigbee_connectivity_by_id(zigbee_resource_id)
      if rest_err ~= nil then
        log.error_with({ hub_logs = true }, rest_err)
        return
      end

      if rest_resp ~= nil then
        if #rest_resp.errors > 0 then
          for _, err in ipairs(rest_resp.errors) do
            log.error_with({ hub_logs = true }, "Error in Hue API response: " .. err.description)
          end
          return
        end

        for _, zigbee_svc in ipairs(rest_resp.data) do
          if zigbee_svc.owner and zigbee_svc.owner.rid == hue_device_id then
            zigbee_status = zigbee_svc
            break
          end
        end
      end
  end

  if zigbee_status and zigbee_status.status == "connected" then
    device.log.debug(string.format("Zigbee Status for %s is connected", device.label))
    device:online()
    device:set_field(Fields.IS_ONLINE, true)
  else
    device.log.debug(string.format("Zigbee Status for %s is not connected", device.label))
    device:set_field(Fields.IS_ONLINE, false)
    device:offline()
  end
end

---@param driver HueDriver
---@param bridge_device HueBridgeDevice
function RefreshHandlers.do_refresh_all_for_bridge(driver, bridge_device)
  cosock.spawn(
    function()
      local child_devices = bridge_device:get_child_list()

      if not bridge_device:get_field(Fields._INIT) then
        log.warn("Bridge for devices not yet initialized, can't refresh yet.")
        return
      end

      local hue_api = bridge_device:get_field(Fields.BRIDGE_API) --[[@as PhilipsHueApi]]

      local conn_status, conn_rest_err = hue_api:get_connectivity_status()

      if conn_rest_err ~= nil or not conn_status then
        bridge_device.log.error(
          string.format(
            "Couldn't refresh device connectivity status for children of bridge [%s].\n" ..
            "get_connectivity_status error? %s\n",
            (bridge_device and bridge_device.label) or "Unknown Bridge",
            conn_rest_err
          )
        )
        return
      end

      if conn_status.errors and #conn_status.errors > 0 then
        bridge_device.log.error("Errors in connectivity status payload: " .. st_utils.stringify_table(conn_status.errors))
        return
      end

      local conn_status_cache = {}

      for _, zigbee_status in ipairs(conn_status.data) do
        conn_status_cache[zigbee_status.owner.rid] = zigbee_status
      end

      local statuses_by_device_type = {}
      for _, device in ipairs(child_devices) do
        local device_type = utils.determine_device_type(device)
        -- Query for the states of all devices for a device type for a given child device,
        -- but only the first time we encounter a device type. We cache them since we're refreshing
        -- everything.
        if
            device_type and
            type(device_type_refresh_handlers_map[device_type]) == "function" and
            statuses_by_device_type[device_type] == nil
        then
          local reprs, rest_err = hue_api:get_all_reprs_for_rtype(device_type)
          if reprs ~= nil and rest_err == nil then
            local cached_states = {}
            for _, repr_state in ipairs(reprs.data) do
              cached_states[repr_state.owner.rid] = repr_state
            end
            statuses_by_device_type[device_type] = cached_states
          else
            log.error("Error refreshing all for resource type [%s]", device_type)
          end
        end
        _refresh_zigbee(device, hue_api, conn_status_cache[device:get_field(Fields.HUE_DEVICE_ID)])
        RefreshHandlers.handler_for_device_type(device_type)(
          driver,
          device,
          statuses_by_device_type[device_type],
          true
        )
      end
    end,
    string.format("Refresh All Child Devices for Hue Bridge [%s]",
      (bridge_device and bridge_device.label) or "Unknown Bridge")
  )
end
-- TODO: [Rule of three](https://en.wikipedia.org/wiki/Rule_of_three_(computer_programming)), this can be generalized.
-- At this point I'm pretty confident that we can actually just have a single generic
-- "refresh device" function and a "refresh all devices" function.
---@param driver HueDriver
---@param button_device HueChildDevice
---@param _ any
---@param skip_zigbee boolean
---@return table<string, any>?
function RefreshHandlers.do_refresh_button(driver, button_device, _, skip_zigbee)
  local hue_device_id = button_device:get_field(Fields.HUE_DEVICE_ID)
  local bridge_id = button_device.parent_device_id or button_device:get_field(Fields.PARENT_DEVICE_ID)
  local bridge_device = utils.get_hue_bridge_for_device(driver, button_device, bridge_id)

  if not bridge_device then
    log.warn("Couldn't get Hue bridge for button device " .. (button_device.label or button_device.id or "unknown device"))
    return
  end

  if not bridge_device:get_field(Fields._INIT) then
    log.warn("Bridge for button device not yet initialized, can't refresh yet.")
    driver._devices_pending_refresh[button_device.id] = button_device
    return
  end

  local hue_api = bridge_device:get_field(Fields.BRIDGE_API) --[[@as PhilipsHueApi]]
  if skip_zigbee ~= true then
    _refresh_zigbee(button_device, hue_api)
  end

  local sensor_info, err = MultiServiceDeviceUtils.get_all_service_states(driver, HueDeviceTypes.BUTTON, hue_api, hue_device_id, bridge_device.device_network_id)
  if err then
    log.error(string.format("Error refreshing motion sensor %s: %s", (button_device and button_device.label), err))
  end

  attribute_emitters.emitter_for_device_type(HueDeviceTypes.BUTTON)(button_device, sensor_info)
  return sensor_info
end

-- TODO: Refresh handlers need to be optimized/generalized for devices with multiple services
---@param driver HueDriver
---@param sensor_device HueChildDevice
---@param _ any
---@param skip_zigbee boolean
---@return table<string, any>?
function RefreshHandlers.do_refresh_motion_sensor(driver, sensor_device, _, skip_zigbee)
  local hue_device_id = sensor_device:get_field(Fields.HUE_DEVICE_ID)
  local bridge_id = sensor_device.parent_device_id or sensor_device:get_field(Fields.PARENT_DEVICE_ID)
  local bridge_device = utils.get_hue_bridge_for_device(driver, sensor_device, bridge_id)

  if not bridge_device then
    log.warn("Couldn't get Hue bridge for motion_sensor " .. (sensor_device.label or sensor_device.id or "unknown device"))
    return
  end

  if not bridge_device:get_field(Fields._INIT) then
    log.warn("Bridge for motion_sensor not yet initialized, can't refresh yet.")
    driver._devices_pending_refresh[sensor_device.id] = sensor_device
    return
  end

  local hue_api = bridge_device:get_field(Fields.BRIDGE_API) --[[@as PhilipsHueApi]]
  if skip_zigbee ~= true then
    _refresh_zigbee(sensor_device, hue_api)
  end

  local sensor_info, err = MultiServiceDeviceUtils.get_all_service_states(driver, HueDeviceTypes.MOTION, hue_api, hue_device_id, bridge_device.device_network_id)
  if err then
    log.error(string.format("Error refreshing motion sensor %s: %s", (sensor_device and sensor_device.label), err))
  end

  attribute_emitters.emitter_for_device_type(HueDeviceTypes.MOTION)(sensor_device, sensor_info)
  return sensor_info
end

---@param driver HueDriver
---@param sensor_device HueChildDevice
---@param _ any
---@param skip_zigbee boolean
---@return table<string, any>?
function RefreshHandlers.do_refresh_contact_sensor(driver, sensor_device, _, skip_zigbee)
  local hue_device_id = sensor_device:get_field(Fields.HUE_DEVICE_ID)
  local bridge_id = sensor_device.parent_device_id or sensor_device:get_field(Fields.PARENT_DEVICE_ID)
  local bridge_device = utils.get_hue_bridge_for_device(driver, sensor_device, bridge_id)

  if not bridge_device then
    log.warn("Couldn't get Hue bridge for contact sensor " .. (sensor_device.label or sensor_device.id or "unknown device"))
    return
  end

  if not bridge_device:get_field(Fields._INIT) then
    log.warn("Bridge for contact sensor not yet initialized, can't refresh yet.")
    driver._devices_pending_refresh[sensor_device.id] = sensor_device
    return
  end

  local hue_api = bridge_device:get_field(Fields.BRIDGE_API) --[[@as PhilipsHueApi]]
  if skip_zigbee ~= true then
    _refresh_zigbee(sensor_device, hue_api)
  end

  local sensor_info, err = MultiServiceDeviceUtils.get_all_service_states(driver, HueDeviceTypes.CONTACT, hue_api, hue_device_id, bridge_device.device_network_id)
  if err then
    log.error(string.format("Error refreshing contact sensor %s: %s", (sensor_device and sensor_device.label), err))
  end

  attribute_emitters.emitter_for_device_type(HueDeviceTypes.CONTACT)(sensor_device, sensor_info)
  return sensor_info
end

---@param driver HueDriver
---@param light_device HueChildDevice
---@param light_status_cache table|nil
---@param skip_zigbee boolean?
---@return HueLightInfo? light_info
function RefreshHandlers.do_refresh_light(driver, light_device, light_status_cache, skip_zigbee)
  local light_resource_id = utils.get_hue_rid(light_device)
  local hue_device_id = light_device:get_field(Fields.HUE_DEVICE_ID)

  if not (light_resource_id and hue_device_id) then
    log.error(
      string.format(
        "Could not get light_resource_id or hue_device_id for light %s",
        (light_device and light_device.label) or "unknown light"
      )
    )
    return
  end
  local do_light_request = true

  if type(light_status_cache) == "table" then
    local light_info = light_status_cache[hue_device_id]
    if light_info ~= nil then
      if light_info.id == light_resource_id then
        if light_info.color ~= nil and light_info.color.gamut then
          light_device:set_field(Fields.GAMUT, light_info.color.gamut_type, { persist = true })
        end
        attribute_emitters.emit_light_attribute_events(light_device, light_info)
        do_light_request = false
      end
    end
  end

  local bridge_id = light_device.parent_device_id or light_device:get_field(Fields.PARENT_DEVICE_ID)
  local bridge_device = utils.get_hue_bridge_for_device(driver, light_device, bridge_id)

  if not bridge_device then
    log.warn("Couldn't get Hue bridge for light " .. (light_device.label or light_device.id or "unknown device"))
    return
  end

  if not bridge_device:get_field(Fields._INIT) then
    log.warn("Bridge for light not yet initialized, can't refresh yet.")
    driver._devices_pending_refresh[light_device.id] = light_device
    return
  end

  local hue_api = bridge_device:get_field(Fields.BRIDGE_API) --[[@as PhilipsHueApi]]
  if skip_zigbee ~= true then
    _refresh_zigbee(light_device, hue_api)
  end

  local success = not (do_light_request)
  local count = 0
  local num_attempts = 3
  local rest_resp, rest_err
  local backoff_generator = utils.backoff_builder(10, 0.1, 0.1)
  --- this loop is a rate-limit dodge.
  ---
  --- One of the various symptoms of hitting the Hue Bridge's rate limit is that you'll get a silent
  --- failure that takes the form of the bridge returning the last valid response it replied with.
  --- So we hit the bridge 2-3 times and check the IDs in the responses to verify that we're getting
  --- the information for the light that we expect to getting the info for.
  repeat
    count = count + 1
    if do_light_request and light_device:get_field(Fields.IS_ONLINE) then
      rest_resp, rest_err = hue_api:get_light_by_id(light_resource_id)
      if rest_err ~= nil then
        log.error_with({ hub_logs = true }, rest_err)
        goto continue
      end

      if rest_resp ~= nil then
        if #rest_resp.errors > 0 then
          for _, err in ipairs(rest_resp.errors) do
            log.error_with({ hub_logs = true }, "Error in Hue API response: " .. err.description)
          end
          goto continue
        end

        for _, light_info in ipairs(rest_resp.data) do
          if light_info.id == light_resource_id then
            if light_info.color ~= nil and light_info.color.gamut then
              light_device:set_field(Fields.GAMUT, light_info.color.gamut_type, { persist = true })
            end
            attribute_emitters.emit_light_attribute_events(light_device, light_info)
            return light_info
          end
        end
      end
    end
    ::continue::
    if not success then
      cosock.socket.sleep(backoff_generator())
    end
  until count >= num_attempts
end

local function noop_refresh_handler(driver, device, ...)
  local label = (device and device.label) or "Unknown Device Name"
  local device_type = (device and utils.determine_device_type(device)) or "Unknown Device Type"
  log.warn(string.format("Received Refresh capability for unknown device [%s] type [%s], ignoring", label, device_type))
end

function RefreshHandlers.handler_for_device_type(device_type)
  return device_type_refresh_handlers_map[device_type] or noop_refresh_handler
end

-- TODO: Generalize this like the other handlers, and maybe even separate out non-primary services
device_type_refresh_handlers_map[HueDeviceTypes.BRIDGE] = RefreshHandlers.do_refresh_all_for_bridge
device_type_refresh_handlers_map[HueDeviceTypes.BUTTON] = RefreshHandlers.do_refresh_button
device_type_refresh_handlers_map[HueDeviceTypes.CONTACT] = RefreshHandlers.do_refresh_contact_sensor
device_type_refresh_handlers_map[HueDeviceTypes.LIGHT] = RefreshHandlers.do_refresh_light
device_type_refresh_handlers_map[HueDeviceTypes.MOTION] = RefreshHandlers.do_refresh_motion_sensor

return RefreshHandlers
