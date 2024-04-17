local cosock = require "cosock"
local log = require "log"
local st_utils = require "st.utils"

local Fields = require "fields"
local HueDeviceTypes = require "hue_device_types"
local utils = require "utils"

local M = {}

---@param driver HueDriver
---@param bridge_device HueBridgeDevice
function M.do_refresh_all_for_bridge(driver, bridge_device)
  cosock.spawn(
    function()
      local child_devices = bridge_device:get_child_list()

      if not bridge_device:get_field(Fields._INIT) then
        log.warn("Bridge for lights not yet initialized, can't refresh yet.")
        return
      end

      local hue_api = bridge_device:get_field(Fields.BRIDGE_API) --[[@as PhilipsHueApi]]

      local conn_status, conn_rest_err = hue_api:get_connectivity_status()
      local light_status, light_rest_err = hue_api:get_lights()

      if conn_rest_err ~= nil or light_rest_err ~= nil then
        bridge_device.log.error(
          string.format(
            "Couldn't refresh devices connected to bridge.\n" ..
            "get_connectivity_status error? %s\n" ..
            "get_lights error? %s\n",
            conn_rest_err,
            light_rest_err
          )
        )
        return
      end

      if (not conn_status) or (not light_status) then
        bridge_device.log.warn(
          string.format(
            "Received empty status payloads with no errors while refreshing, aborting refresh handler.\n" ..
            "Connectivity status nil? %s\n" ..
            "Light status nil? %s\n",
            (conn_status == nil),
            (light_status == nil)
          )
        )
        return
      end

      if conn_status.errors and #conn_status.errors > 0 then
        bridge_device.log.error("Errors in connectivity status payload: " .. st_utils.stringify_table(conn_status.errors))
        return
      end

      if light_status.errors and #light_status.errors > 0 then
        bridge_device.log.error("Errors in light status payload: " .. st_utils.stringify_table(light_status.errors))
        return
      end

      local conn_status_cache = {}
      local light_status_cache = {}

      for _, zigbee_status in ipairs(conn_status.data) do
        conn_status_cache[zigbee_status.owner.rid] = zigbee_status
      end

      for _, light_status in ipairs(light_status.data) do
        light_status_cache[light_status.owner.rid] = light_status
      end

      for _, device in ipairs(child_devices) do
        local device_type = device:get_field(Fields.DEVICE_TYPE)
        if device_type == "light" then
          M.do_refresh_light(driver, device, conn_status_cache, light_status_cache)
        end
      end
    end,
    string.format("Refresh All Child Devices for Hue Bridge [%s]", (bridge_device and bridge_device.label) or "Unknown Bridge")
  )
end

---@param driver HueDriver
---@param light_device HueChildDevice
---@param conn_status_cache table|nil
---@param light_status_cache table|nil
function M.do_refresh_light(driver, light_device, conn_status_cache, light_status_cache)
  local light_resource_id = light_device:get_field(Fields.RESOURCE_ID)
  local hue_device_id = light_device:get_field(Fields.HUE_DEVICE_ID)

  local do_zigbee_request = true
  local do_light_request = true

  if type(conn_status_cache) == "table" then
    local zigbee_status = conn_status_cache[hue_device_id]
    if zigbee_status ~= nil and zigbee_status.status ~= nil then
      do_zigbee_request = false
      if zigbee_status.status == "connected" then
        light_device.log.debug(string.format("Zigbee Status for %s is connected", light_device.label))
        light_device:online()
        light_device:set_field(Fields.IS_ONLINE, true)
      else
        light_device.log.debug(string.format("Zigbee Status for %s is not connected", light_device.label))
        light_device:set_field(Fields.IS_ONLINE, false)
        light_device:offline()
      end
    end
  end

  if type(light_status_cache) == "table" then
    local light_info = light_status_cache[hue_device_id]
    if light_info ~= nil then
      if light_info.id == light_resource_id then
        if light_info.color ~= nil and light_info.color.gamut then
          light_device:set_field(Fields.GAMUT, light_info.color.gamut_type, { persist = true })
        end
        driver.emit_light_status_events(light_device, light_info)
        do_light_request = false
      end
    end
  end

  local bridge_id = light_device.parent_device_id or light_device:get_field(Fields.PARENT_DEVICE_ID)
  local bridge_device = driver:get_device_info(bridge_id)

  if not bridge_device then
    log.warn("Couldn't get Hue bridge for light " .. (light_device.label or light_device.id or "unknown device"))
    return
  end

  if not bridge_device:get_field(Fields._INIT) then
    log.warn("Bridge for light not yet initialized, can't refresh yet.")
    driver._lights_pending_refresh[light_device.id] = light_device
    return
  end

  local hue_api = bridge_device:get_field(Fields.BRIDGE_API)
  local success = not (do_light_request or do_zigbee_request)
  local count = 0
  local num_attempts = 3
  local zigbee_resource_id
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
    if do_zigbee_request then
      rest_resp, rest_err = hue_api:get_device_by_id(hue_device_id)
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

        for _, hue_device in ipairs(rest_resp.data) do
          for _, svc_info in ipairs(hue_device.services or {}) do
            if svc_info.rtype == "zigbee_connectivity" then
              zigbee_resource_id = svc_info.rid
            end
          end
        end
      end

      if zigbee_resource_id ~= nil then
        rest_resp, rest_err = hue_api:get_zigbee_connectivity_by_id(zigbee_resource_id)
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

          for _, zigbee_svc in ipairs(rest_resp.data) do
            if zigbee_svc.owner and zigbee_svc.owner.rid == hue_device_id then
              if zigbee_svc.status and zigbee_svc.status == "connected" then
                light_device.log.debug(string.format("Zigbee Status for %s is connected", light_device.label))
                light_device:online()
                light_device:set_field(Fields.IS_ONLINE, true)
              else
                light_device.log.debug(string.format("Zigbee Status for %s is not connected", light_device.label))
                light_device:set_field(Fields.IS_ONLINE, false)
                light_device:offline()
              end
            end
          end
        end
      end
    end

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
            driver.emit_light_status_events(light_device, light_info)
            success = true
          end
        end
      end
    end
    ::continue::
    if not success then
      cosock.socket.sleep(backoff_generator())
    end
  until success or count >= num_attempts
end

local device_type_handlers_map = {}

device_type_handlers_map[HueDeviceTypes.BRIDGE] = M.do_refresh_all_for_bridge
device_type_handlers_map[HueDeviceTypes.LIGHT] = M.do_refresh_light

local function noop_refresh_handler(driver, device, ...)
  local label = (device and device.label) or "Unknown Device Name"
  local device_type = (device and device:get_field(Fields.DEVICE_TYPE)) or "Unknown Device Type"
  log.warn(string.format("Received Refresh capability for unknown device [%s] type [%s], ignoring", label, device_type))
end

function M.handler_for_device_type(device_type)
  return device_type_handlers_map[device_type] or noop_refresh_handler
end

return M
