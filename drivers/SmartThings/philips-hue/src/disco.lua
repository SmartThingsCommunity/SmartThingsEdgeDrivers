local Fields = require "hue.fields"
local HueApi = require "hue.api"
local log = require "log"
local socket = require "cosock.socket"

local mdns = require "st.mdns"
local net_utils = require "st.net_utils"
local st_utils = require "st.utils"

local SERVICE_TYPE = "_hue._tcp"
local DOMAIN = "local"

local HueDiscovery = {
  api_keys = {},
  disco_api_instances = {},
  light_state_disco_cache = {}
}

local supported_resource_types = {
  light = true
}

local try_create_count = {}

-- "forward declarations"
local discovered_bridge_callback, discovered_device_callback, is_device_service_supported,
process_discovered_light

---comment
---@param driver HueDriver
---@param _ table
---@param should_continue function
function HueDiscovery.discover(driver, _, should_continue)
  log.info("Starting Hue discovery")
  try_create_count = {}

  while should_continue() do
    local known_dni_to_device_map = {}
    local computed_mac_addresses = {}
    for _, device in ipairs(driver:get_devices()) do
      -- the bridge won't have a parent assigned key so we give that boolean short circuit preference
      local dni = device.parent_assigned_child_key or device.device_network_id
      known_dni_to_device_map[dni] = device
      local ipv4 = device:get_field(Fields.IPV4);
      if ipv4 then
        computed_mac_addresses[ipv4] = dni
      end
    end

    HueDiscovery.search_for_bridges(driver, computed_mac_addresses, function(hue_driver, bridge_ip, bridge_id)
      discovered_bridge_callback(hue_driver, bridge_ip, bridge_id, known_dni_to_device_map)
    end)
  end
  log.trace(st_utils.stringify_table(try_create_count, "Try-Create Count", true))
  log.info("Ending Hue discovery")
end

---comment
---@param driver HueDriver
---@param computed_mac_addresses table<string,string>
---@param callback fun(driver: HueDriver, ip: string, id: string)
function HueDiscovery.search_for_bridges(driver, computed_mac_addresses, callback)
  local mdns_responses, err = mdns.discover(SERVICE_TYPE, DOMAIN)

  if err ~= nil then
    log.error("Error during service discovery: ", err)
    return
  end

  if not (mdns_responses and mdns_responses.found and #mdns_responses.found > 0) then
    log.debug("No mdns responses for Hue service this attempt, continuing...")
    return
  end

  for _, info in ipairs(mdns_responses.found) do
    if not net_utils.validate_ipv4_string(info.host_info.address) then -- we only care about the ipV4 types here.
      log.debug("Invalid IPv4 address: " .. info.host_info.address)
      goto continue
    end
    if info.service_info.service_type ~= SERVICE_TYPE then -- response for a different service type. Shouldn't happen.
      log.debug("Unexpected service type response: " .. info.service_info.service_type)
      goto continue
    end
    if info.service_info.domain ~= DOMAIN then -- response for a different domain. Shouldn't happen.
      log.debug("Unexpected domain response: " .. info.service_info.domain)
      goto continue
    end

    local ip_addr = info.host_info.address;

    if not computed_mac_addresses[ip_addr] then
      -- Hue *typically* formats the BridgeID as the uppercase MAC address, minus separators.
      -- However, it can be user overriden, set by a user, and may not be unique, so we want
      -- to stick to that format but make sure it's actually the mac address. Instead of pulling
      -- the bridge id out of the bridge info, we'll extract the MAC address and apply the above mentioned
      -- formatting rules. We also prefer the MAC because it makes for a good Device Network ID.
      local bridge_info, rest_err, _ = HueApi.get_bridge_info(ip_addr)
      if rest_err ~= nil or not bridge_info then
        log.error("Error querying bridge info: ", rest_err)
        goto continue
      end

      -- '-' and ':' or '::' are the accepted separators used for MAC address segments, so
      -- we strip thoes out and make the string uppercase
      if bridge_info.mac then
        local bridge_id = bridge_info.mac:gsub("-", ""):gsub(":", ""):upper()
        computed_mac_addresses[ip_addr] = bridge_id
      end
    end

    if type(callback) == "function" then
      callback(driver, ip_addr, computed_mac_addresses[ip_addr])
    else
      log.warn(
        "Argument passed in `callback` position for "
        .. "`HueDiscovery.search_for_bridges` is not a function"
      )
    end

    ::continue::
  end
end

---@param driver HueDriver
---@param bridge_ip string
---@param bridge_id string
---@param known_dni_to_device_map table<string,HueDevice>
discovered_bridge_callback = function(driver, bridge_ip, bridge_id, known_dni_to_device_map)
  if driver.ignored_bridges[bridge_id] then return end

  local known_bridge_device = known_dni_to_device_map[bridge_id]
  if known_bridge_device and known_bridge_device:get_field(Fields.API_KEY) then
    HueDiscovery.api_keys[bridge_id] = known_bridge_device:get_field(Fields.API_KEY)
  end

  if known_bridge_device ~= nil
      and driver.joined_bridges[bridge_id]
      and HueDiscovery.api_keys[bridge_id]
      and known_bridge_device:get_field(Fields._INIT) then
    log.trace(string.format("Scanning bridge %s for devices...", bridge_id))

    HueDiscovery.disco_api_instances[bridge_id] = HueDiscovery.disco_api_instances[bridge_id]
        or
        HueApi.new_bridge_manager("https://" .. bridge_ip, HueDiscovery.api_keys[bridge_id])

    HueDiscovery.search_bridge_for_supported_devices(driver, HueDiscovery.disco_api_instances[bridge_id],
      function(hue_driver, svc_info, device_info)
        discovered_device_callback(hue_driver, bridge_id, svc_info, device_info, known_dni_to_device_map)
      end)
    return
  end

  if not HueDiscovery.api_keys[bridge_id] then
    local api_key_response, err, _ = HueApi.request_api_key(bridge_ip)

    if err ~= nil or not api_key_response then
      log.warn("Error while trying to request Bridge API Key: ", err)
      return
    end

    for _, item in ipairs(api_key_response) do
      if item.error ~= nil then
        log.warn("Error payload in bridge API key response: " .. item.error.description)
      elseif item.success and item.success.username then
        log.debug("API key received for Hue Bridge")

        local api_key = item.success.username
        local bridge_base_url = "https://" .. bridge_ip
        local api_instance = HueApi.new_bridge_manager(bridge_base_url, api_key)

        HueDiscovery.api_keys[bridge_id] = api_key
        HueDiscovery.disco_api_instances[bridge_id] = api_instance
      end
    end
  end

  if HueDiscovery.api_keys[bridge_id] and not driver.joined_bridges[bridge_id] then
    local bridge_info, err, _ = HueApi.get_bridge_info(bridge_ip)
    if err ~= nil or not bridge_info then
      log.error("Error querying bridge info: ", err)
      return
    end

    if tonumber(bridge_info.swversion or "0", 10) < HueApi.MIN_CLIP_V2_SWVERSION then
      log.warn("Found bridge that does not support CLIP v2 API, ignoring")
      driver.ignored_bridges[bridge_id] = true
      return
    end

    bridge_info.ip = bridge_ip
    driver.joined_bridges[bridge_id] = bridge_info

    if not known_bridge_device then
      local create_device_msg = {
        type = "LAN",
        device_network_id = bridge_id,
        label = (bridge_info.name or "Philips Hue Bridge"),
        profile = "hue-bridge",
        manufacturer = "Signify Netherlands B.V.",
        model = bridge_info.modelid or "BSB002",
        vendor_provided_label = (bridge_info.name or "Philips Hue Bridge"),
      }

      local count = try_create_count[create_device_msg.label] or 0
      try_create_count[create_device_msg.label] = count + 1
      driver:try_create_device(create_device_msg)
    end
  end
end

---@param driver HueDriver
---@param api_instance PhilipsHueApi
---@param callback fun(driver: HueDriver, svc_info: table, device_data: table)
function HueDiscovery.search_bridge_for_supported_devices(driver, api_instance, callback)
  local devices, err, _ = api_instance:get_devices()

  if err ~= nil or not devices then
    log.error("Error querying bridge for devices: ", err)
    return
  end

  if devices.errors and #devices.errors > 0 then
    log.error("Errors found in API response:")
    for idx, err in ipairs(devices.errors) do
      log.error(st_utils.stringify_table(err, "Error " .. idx, true))
    end
    return
  end

  for _, device_data in ipairs(devices.data or {}) do
    for _, svc_info in ipairs(device_data.services or {}) do
      if is_device_service_supported(svc_info) then
        if type(callback) == "function" then
          callback(driver, svc_info, device_data)
        else
          log.warn(
            "Argument passed in `callback` position for "
            .. "`HueDiscovery.search_bridge_for_supported_devices` is not a function"
          )
        end
      end
    end
  end
end

---@param driver HueDriver
---@param bridge_id string
---@param svc_info table
---@param device_info table
---@param known_dni_to_device_map table<string,boolean>
discovered_device_callback = function(driver, bridge_id, svc_info, device_info, known_dni_to_device_map)
  local v1_dni = bridge_id .. "/" .. (device_info.id_v1 or "UNKNOWN"):gsub("/lights/", "")
  local edge_dni = svc_info.rid or ""
  if known_dni_to_device_map[v1_dni] or known_dni_to_device_map[edge_dni] then return end
  if svc_info.rtype == "light" then
    process_discovered_light(driver, bridge_id, svc_info.rid, device_info, known_dni_to_device_map)
  end
end

---@param driver HueDriver
---@param bridge_id string
---@param resource_id string
---@param device_info table
---@param known_dni_to_device_map table<string,boolean>
process_discovered_light = function(driver, bridge_id, resource_id, device_info, known_dni_to_device_map)
  local api_instance = HueDiscovery.disco_api_instances[bridge_id]
  if not api_instance then
    log.warn("No API instance for bridge_id ", bridge_id)
    return
  end

  local light_resource, err, _ = api_instance:get_light_by_id(resource_id)
  if err ~= nil or not light_resource then
    log.error("Error getting light info: ", error)
    return
  end

  if light_resource.errors and #light_resource.errors > 0 then
    log.error("Errors found in API response:")
    for idx, err in ipairs(light_resource.errors) do
      log.error(st_utils.stringify_table(err, "Error " .. idx, true))
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

    local bridge_device = known_dni_to_device_map[bridge_id]

    local create_device_msg = {
      type = "EDGE_CHILD",
      label = light.metadata.name,
      vendor_provided_label = device_info.product_data.product_name,
      profile = profile_ref,
      manufacturer = device_info.product_data.manufacturer_name,
      model = device_info.product_data.model_id,
      parent_device_id = bridge_device.id,
      parent_assigned_child_key = light.id,
    }

    HueDiscovery.light_state_disco_cache[light.id] = {
      on = light.on,
      color = light.color,
      dimming = light.dimming,
      color_temp = light.color_temperature,
      mode = light.mode,
      parent_device_id = bridge_device.id,
      hue_device_id = light.owner.rid
    }

    local count = try_create_count[create_device_msg.label] or 0
    try_create_count[create_device_msg.label] = count + 1
    driver:try_create_device(create_device_msg)
    -- rate limit ourself.
    socket.sleep(0.1)
    ::continue::
  end
end

is_device_service_supported = function(svc_info)
  return supported_resource_types[svc_info.rtype or ""]
end

return HueDiscovery
