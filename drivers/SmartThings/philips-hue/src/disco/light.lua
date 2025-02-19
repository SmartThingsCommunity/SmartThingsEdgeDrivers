local log = require "log"
local socket = require "cosock".socket
local st_utils = require "st.utils"
-- trick to fix the VS Code Lua Language Server typechecking
---@type fun(val: any?, name: string?, multi_line: boolean?): string
st_utils.stringify_table = st_utils.stringify_table

local HueDeviceTypes = require "hue_device_types"

local function join_light(driver, light, device_service_info, parent_device_id, st_metadata_callback)
  local profile_ref
  if light.color then
    if light.color_temperature then
      profile_ref = "white-and-color-ambiance"
    else
      profile_ref = "legacy-color"
    end
  elseif light.color_temperature then
    profile_ref = "white-ambiance"   -- all color temp products support `white` (dimming)
  elseif light.dimming then
    profile_ref = "white"            -- `white` refers to dimmable and includes filament bulbs
  elseif light.on then               -- Case for plug which uses same category as 'light'
    profile_ref = "plug"
  else
    log.warn(
      string.format(
        "Light resource [%s] does not seem to be A White/White-Ambiance/White-Color-Ambiance/Plug device, currently unsupported"
        ,
        light.id
      )
    )
    return
  end

  local device_name
  if light.metadata.name == device_service_info.metadata.name then
    device_name = device_service_info.metadata.name
  else
    device_name = string.format("%s %s", device_service_info.metadata.name, light.metadata.name)
  end

  local parent_assigned_child_key = string.format("%s:%s", light.type, light.id)

  local st_metadata = {
    type = "EDGE_CHILD",
    label = device_name,
    vendor_provided_label = device_service_info.product_data.product_name,
    profile = profile_ref,
    manufacturer = device_service_info.product_data.manufacturer_name,
    model = device_service_info.product_data.model_id,
    parent_device_id = parent_device_id,
    parent_assigned_child_key = parent_assigned_child_key
  }

  log.debug(st_utils.stringify_table(st_metadata, "light create", true))
  st_metadata_callback(driver, st_metadata)
  -- rate limit ourself.
  socket.sleep(0.1)
end

local function get_light_state_table_and_update_cache(light, parent_device_id, device_service_info, cache)
  local light_resource_description = {
    hue_provided_name = light.metadata.name,
    id = light.id,
    on = light.on,
    color = light.color,
    dimming = light.dimming,
    color_temperature = light.color_temperature,
    mode = light.mode,
    parent_device_id = parent_device_id,
    hue_device_id = light.owner.rid,
    hue_device_data = device_service_info
  }

  if type(cache) == "table" then
    cache[light.id] = light_resource_description
    if device_service_info.id_v1 then
      cache[device_service_info.id_v1] = light_resource_description
    end
  end
  return light_resource_description
end

---@param driver HueDriver
---@param api_instance PhilipsHueApi
---@param services HueServiceInfo[]
---@param device_service_info HueDeviceInfo
---@param bridge_network_id string
---@param cache table<string, table>
---@param st_metadata_callback fun(driver: HueDriver, metadata: table)?
local function handle_compound_light(
    driver, api_instance, services,
    device_service_info, bridge_network_id, cache, st_metadata_callback
)
  ---@type HueLightInfo[]
  local all_lights = {}
  local main_light_resource_id
  for _, svc in ipairs(services) do
    local light_resource, err, _ = api_instance:get_light_by_id(svc.rid)
    if not light_resource or (light_resource and #light_resource.errors > 0) or err then
      log.error(string.format("Couldn't get light resource for rid %s, skipping", svc.rid))
      goto continue
    end
    table.insert(all_lights, light_resource.data[1])
    if light_resource.data[1].service_id and light_resource.data[1].service_id == 1 then
      main_light_resource_id = light_resource.data[1].id
    end
    ::continue::
  end

  if type(main_light_resource_id) ~= "string" then
    log.warn(
      string.format(
        "Couldn't determine the primary light for compound light [%s] from V1 ID, picking the first light service",
        device_service_info.metadata.name
      )
    )
    main_light_resource_id = services[1].rid
  end

    ---@type HueLightInfo[]
  local grandchild_lights = {}
  for _, light in pairs(all_lights) do
    if light.id == main_light_resource_id then
      local bridge_device = driver:get_device_by_dni(bridge_network_id) --[[@as HueBridgeDevice]]
      get_light_state_table_and_update_cache(light, bridge_device.id, device_service_info, cache)
      if type(st_metadata_callback) == "function" then
        join_light(
          driver, light, device_service_info, bridge_device.id, st_metadata_callback
        )
      end
    else
      table.insert(grandchild_lights, {
        waiting_resource_info = light,
        join_callback = function(driver, waiting_info, parent_device)
          get_light_state_table_and_update_cache(waiting_info, parent_device.id, device_service_info, cache)
          join_light(
            driver, waiting_info, device_service_info, parent_device.id, st_metadata_callback
          )
        end
      })
    end
  end

  driver:queue_grandchild_device_for_join(grandchild_lights, main_light_resource_id)
end

---@param driver HueDriver
---@param api_instance PhilipsHueApi
---@param resource_id string
---@param device_service_info HueDeviceInfo
---@param bridge_network_id string
---@param cache table<string, table>
---@param st_metadata_callback fun(driver: HueDriver, metadata: table)?
local function handle_simple_light(
    driver, api_instance, resource_id,
    device_service_info, bridge_network_id, cache, st_metadata_callback
)
  local light_resource, err, _ = api_instance:get_light_by_id(resource_id)
  if err ~= nil or not light_resource then
    log.error_with({ hub_logs = true },
      string.format("Error getting light info for %s: %s", device_service_info.product_data.product_name,
        (err or "unexpected nil in error position")))
    return
  end

  if light_resource.errors and #light_resource.errors > 0 then
    log.error_with({ hub_logs = true }, "Errors found in API response:")
    for idx, rest_err in ipairs(light_resource.errors) do
      log.error_with({ hub_logs = true }, st_utils.stringify_table(rest_err, "Error " .. idx, true))
    end
    return
  end

  local light = light_resource.data[1]
  local bridge_device = driver:get_device_by_dni(bridge_network_id) --[[@as HueBridgeDevice]]
  get_light_state_table_and_update_cache(light, bridge_device.id, device_service_info, cache)

  if type(st_metadata_callback) == "function" then
    join_light(
      driver, light, device_service_info, bridge_device.id, st_metadata_callback
    )
  end
end

---@class DiscoveredLightHandler: DiscoveredChildDeviceHandler
local M = {}

---@param driver HueDriver
---@param bridge_network_id string
---@param api_instance PhilipsHueApi
---@param primary_services table<HueDeviceTypes,HueServiceInfo[]>
---@param device_service_info HueDeviceInfo
---@param device_state_disco_cache table<string, table>
---@param st_metadata_callback fun(driver: HueDriver, metadata: table)?
function M.handle_discovered_device(
    driver, bridge_network_id, api_instance,
    primary_services, device_service_info,
    device_state_disco_cache, st_metadata_callback
)
  local light_services = primary_services[HueDeviceTypes.LIGHT]
  local is_compound_light = #light_services > 1
  if is_compound_light then
    handle_compound_light(
      driver, api_instance, light_services, device_service_info,
      bridge_network_id, device_state_disco_cache, st_metadata_callback
    )
  else
    handle_simple_light(
      driver, api_instance, light_services[1].rid, device_service_info,
      bridge_network_id, device_state_disco_cache, st_metadata_callback
    )
  end
end

return M
