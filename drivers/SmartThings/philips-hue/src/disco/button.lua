local log = require "logjam"
local socket = require "cosock".socket
local st_utils = require "st.utils"

local HueDeviceTypes = require "hue_device_types"

---@class DiscoveredButtonHandler: DiscoveredChildDeviceHandler
local M = {}

---@param api_instance PhilipsHueApi
---@param device_service_info HueDeviceInfo
---@param bridge_id string
---@param resource_id string
---@param cache table?
---@return table<string,any>? description nil on error
---@return string? err nil on success
local function _do_update(api_instance, device_service_info, bridge_id, resource_id, cache)
  local rid_by_rtype = {}
  local button_services = {}
  local num_buttons = 0

  for _, svc in ipairs(device_service_info.services) do
    if svc.rtype == HueDeviceTypes.BUTTON then
      num_buttons = num_buttons + 1
      table.insert(button_services, svc.rid)
    else
      rid_by_rtype[svc.rtype] = svc.rid
    end
  end

  local button_remote_description = {
    hue_provided_name = device_service_info.metadata.name,
    parent_device_id = bridge_id,
    hue_device_id = device_service_info.id,
    hue_device_data = device_service_info,
    id = resource_id,
    num_buttons = num_buttons
  }

  for _, button_rid in ipairs(button_services) do
    local button_repr, err = api_instance:get_button_by_id(button_rid)
    if err or not button_repr then
      log.error("Error getting button representation: " .. tostring(err or "unknown error"))
    else
      local control_id = button_repr.data[1].metadata.control_id
      local button_key = string.format("button%s", control_id)
      local button_id_key = string.format("%s_id", button_key)
      button_remote_description[button_key] = button_repr.data[1].button
      button_remote_description[button_id_key] = button_repr.data[1].id

      if control_id == 1 and button_remote_description.id == nil then
        button_remote_description.id = button_repr.data[1].id
      end
    end
  end

  local battery, battery_err = api_instance:get_device_power_by_id(rid_by_rtype[HueDeviceTypes.DEVICE_POWER])
  if battery_err then return nil, battery_err end

  if battery and battery.data and battery.data[1] then
    button_remote_description.power_id = battery.data[1].id
    button_remote_description.power_state = battery.data[1].power_state
  end

  if type(cache) == "table" then
    cache[resource_id] = button_remote_description
    if device_service_info.id_v1 then
      cache[device_service_info.id_v1] = button_remote_description
    end
  end

  return button_remote_description
end

---@param api_instance PhilipsHueApi
---@param device_service_id string
---@param bridge_id string
---@param primary_button_resource_id string
---@param cache table?
---@return table<string,any>? description nil on error
---@return string? err nil on success
function M.update_state_for_all_device_services(api_instance, device_service_id, bridge_id, primary_button_resource_id, cache)
  log.debug("----------- Calling REST API")
  local device_service_info, err = api_instance:get_device_by_id(device_service_id)
  if err or not (device_service_info and device_service_info.data) then
    log.error("Couldn't get device info for button, error: " .. st_utils.stringify_table(err))
    return
  end

  log.debug("------------ _do_update")
  return _do_update(api_instance, device_service_info.data[1], bridge_id, primary_button_resource_id, cache)
end

---@param driver HueDriver
---@param bridge_id string
---@param api_instance PhilipsHueApi
---@param resource_id string
---@param device_service_info HueDeviceInfo
---@param device_state_disco_cache table<string, table>
---@param st_metadata_callback fun(driver: HueDriver, metadata: table)?
function M.handle_discovered_device(
    driver, bridge_id, api_instance,
    resource_id, device_service_info,
    device_state_disco_cache, st_metadata_callback
)
  local button_description, err = _do_update(
    api_instance, device_service_info, bridge_id, resource_id, device_state_disco_cache
  )
  if err then
    log.error("Error updating contact button initial state: " .. st_utils.stringify_table(err))
    return
  end

  if type(st_metadata_callback) == "function" then
    if not (button_description and HueDeviceTypes.supports_button_configuration(button_description)) then
      button_description = button_description or {num_buttons = "unknown"}
      log.error(
        string.format(
          "Driver does not currently support remotes with %s buttons, cannot create device", button_description.num_buttons
        )
      )
      return
    end

    local button_profile_ref = ""
    -- For Philips Hue Smart Button device which contains only 1 button
    if button_description.num_buttons == 1 then
      button_profile_ref = "HueSmartButton"
      -- For Philips Hue Dimmer Remote which contains 4 buttons
    elseif button_description.num_buttons == 4 then
      button_profile_ref = "4-button-remote"
    end

    local bridge_device = driver:get_device_by_dni(bridge_id) or {}
    local st_metadata = {
      type = "EDGE_CHILD",
      label = device_service_info.metadata.name,
      vendor_provided_label = device_service_info.product_data.product_name,
      profile = button_profile_ref,
      manufacturer = device_service_info.product_data.manufacturer_name,
      model = device_service_info.product_data.model_id,
      parent_device_id = bridge_device.id,
      parent_assigned_child_key = string.format("%s:%s", HueDeviceTypes.BUTTON, resource_id)
    }

    log.debug(st_utils.stringify_table(st_metadata, "button create", true))

    st_metadata_callback(driver, st_metadata)
    -- rate limit ourself.
    socket.sleep(0.1)
  end
end

return M
