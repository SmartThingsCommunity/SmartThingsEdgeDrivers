local log = require "log"
local socket = require "cosock".socket
local st_utils = require "st.utils"

local M = {}

---@param driver HueDriver
---@param bridge_id string
---@param api_instance PhilipsHueApi
---@param resource_id string
---@param device_info table
---@param device_state_disco_cache table<string, table>
---@param known_identifier_to_device_map table<string,HueDevice>
function M.process_discovered_light(driver, bridge_id, api_instance, resource_id, device_info, device_state_disco_cache, known_identifier_to_device_map)
  local light_resource, err, _ = api_instance:get_light_by_id(resource_id)
  if err ~= nil or not light_resource then
    log.error_with({ hub_logs = true },
      string.format("Error getting light info for %s: %s", device_info.product_data.product_name,
        (err or "unexpected nil in error position")))
    return
  end

  if light_resource.errors and #light_resource.errors > 0 then
    log.error_with({ hub_logs = true }, "Errors found in API response:")
    for idx, err in ipairs(light_resource.errors) do
      log.error_with({ hub_logs = true }, st_utils.stringify_table(err, "Error " .. idx, true))
    end
    return
  end

  for _, light in ipairs(light_resource.data or {}) do
    local profile_ref

    if light.color then
      if light.color_temperature then
        profile_ref = "white-and-color-ambiance"
      else
        profile_ref = "legacy-color"
      end
    elseif light.color_temperature then
      profile_ref = "white-ambiance" -- all color temp products support `white` (dimming)
    elseif light.dimming then
      profile_ref = "white"          -- `white` refers to dimmable and includes filament bulbs
    else
      log.warn(
        string.format(
          "Light resource [%s] does not seem to be A White/White-Ambiance/White-Color-Ambiance device, currently unsupported"
          ,
          resource_id
        )
      )
      goto continue
    end

    local bridge_device = known_identifier_to_device_map[bridge_id]

    local create_device_msg = {
      type = "EDGE_CHILD",
      label = light.metadata.name,
      vendor_provided_label = device_info.product_data.product_name,
      profile = profile_ref,
      manufacturer = device_info.product_data.manufacturer_name,
      model = device_info.product_data.model_id,
      parent_device_id = bridge_device.id,
      parent_assigned_child_key = string.format("%s:%s", light.type, light.id)
    }

    device_state_disco_cache[light.id] = {
      hue_provided_name = light.metadata.name,
      id = light.id,
      on = light.on,
      color = light.color,
      dimming = light.dimming,
      color_temperature = light.color_temperature,
      mode = light.mode,
      parent_device_id = bridge_device.id,
      hue_device_id = light.owner.rid,
      hue_device_data = device_info
    }

    driver:try_create_device(create_device_msg)
    -- rate limit ourself.
    socket.sleep(0.1)
    ::continue::
  end
end

return M
