local log = require "log"
local socket = require "cosock.socket"

local mdns = require "st.mdns"
local net_utils = require "st.net_utils"
local st_utils = require "st.utils"

local Fields = require "fields"
local HueApi = require "hue.api"
local utils = require "utils"

local SERVICE_TYPE = "_hue._tcp"
local DOMAIN = "local"

-- This `api_keys` table is an in-memory fall-back table. It gets overwritten
-- with a reference to a driver datastore table before the Driver's `run` loop
-- can get spun up in `init.lua`.
local HueDiscovery = {
  api_keys = {},
  disco_api_instances = {},
  light_state_disco_cache = {},
  ServiceType = SERVICE_TYPE,
  Domain = DOMAIN,
  discovery_active = false
}

local supported_resource_types = {
  light = true
}

-- "forward declarations"
local discovered_bridge_callback, discovered_device_callback, is_device_service_supported,
process_discovered_light

---comment
---@param driver HueDriver
---@param _ table
---@param should_continue function
function HueDiscovery.discover(driver, _, should_continue)
  if HueDiscovery.discovery_active then
    log.info("Hue discovery already in progress, ignoring new discovery request")
    return
  end

  log.info_with({ hub_logs = true }, "Starting Hue discovery")
  HueDiscovery.discovery_active = true

  while should_continue() do
    local known_identifier_to_device_map = {}
    local computed_mac_addresses = {}
    for _, device in ipairs(driver:get_devices()) do
      -- the bridge won't have a parent assigned key so we give that boolean short circuit preference
      local dni = device.parent_assigned_child_key or device.device_network_id
      known_identifier_to_device_map[dni] = device
      local ipv4 = device:get_field(Fields.IPV4);
      if ipv4 then
        computed_mac_addresses[ipv4] = dni
      end
    end

    HueDiscovery.do_mdns_scan(driver)
    HueDiscovery.search_for_bridges(driver, computed_mac_addresses, function(hue_driver, bridge_ip, bridge_id)
      discovered_bridge_callback(hue_driver, bridge_ip, bridge_id, known_identifier_to_device_map)
    end)
    socket.sleep(1.0)
  end
  HueDiscovery.discovery_active = false
  log.info_with({ hub_logs = true }, "Ending Hue discovery")
end

---comment
---@param driver HueDriver
---@param computed_mac_addresses table<string,string>
---@param callback fun(driver: HueDriver, ip: string, id: string)
function HueDiscovery.search_for_bridges(driver, computed_mac_addresses, callback)
  local scanned_bridges = driver.datastore.bridge_netinfo or {}
  for bridge_id, bridge_info in pairs(scanned_bridges) do
    if type(callback) == "function" and bridge_info ~= nil then
      callback(driver, bridge_info.ip, bridge_id)
    else
      log.warn(
        "Argument passed in `callback` position for "
        .. "`HueDiscovery.search_for_bridges` is not a function"
      )
    end
  end
end

function HueDiscovery.scan_bridge_and_update_devices(driver, bridge_id)
  if driver.ignored_bridges[bridge_id] then return end

  local known_identifier_to_device_map = {}
  for _, device in ipairs(driver:get_devices()) do
    -- the bridge won't have a parent assigned key so we give that boolean short circuit preference
    local dni = device.parent_assigned_child_key or device.device_network_id
    known_identifier_to_device_map[dni] = device
  end

  local known_bridge_device = known_identifier_to_device_map[bridge_id]
  if known_bridge_device and known_bridge_device:get_field(HueApi.APPLICATION_KEY_HEADER) then
    HueDiscovery.api_keys[bridge_id] = known_bridge_device:get_field(HueApi.APPLICATION_KEY_HEADER)
  end

  HueDiscovery.search_bridge_for_supported_devices(driver, bridge_id, HueDiscovery.disco_api_instances[bridge_id],
    function(hue_driver, svc_info, device_info)
      discovered_device_callback(hue_driver, bridge_id, svc_info, device_info, known_identifier_to_device_map)
    end,
    "[Discovery: " ..
    (known_bridge_device.label or bridge_id or known_bridge_device.id or "unknown bridge") .. " bridge re-scan]",
    true
  )
end

---@param driver HueDriver
---@param bridge_ip string
---@param bridge_id string
---@param known_identifier_to_device_map table<string,HueDevice>
discovered_bridge_callback = function(driver, bridge_ip, bridge_id, known_identifier_to_device_map)
  if driver.ignored_bridges[bridge_id] then return end

  local known_bridge_device = known_identifier_to_device_map[bridge_id]
  if known_bridge_device and known_bridge_device:get_field(HueApi.APPLICATION_KEY_HEADER) then
    HueDiscovery.api_keys[bridge_id] = known_bridge_device:get_field(HueApi.APPLICATION_KEY_HEADER)
  end

  if known_bridge_device ~= nil
      and driver.joined_bridges[bridge_id]
      and HueDiscovery.api_keys[bridge_id]
      and known_bridge_device:get_field(Fields._INIT)
  then
    log.info_with({ hub_logs = true }, string.format("Scanning bridge %s for devices...", bridge_id))

    HueDiscovery.disco_api_instances[bridge_id] = HueDiscovery.disco_api_instances[bridge_id]
        or HueApi.new_bridge_manager(
          "https://" .. bridge_ip,
          HueDiscovery.api_keys[bridge_id],
          utils.labeled_socket_builder((known_bridge_device.label or bridge_id or known_bridge_device.id or "unknown bridge"))
        )

    HueDiscovery.search_bridge_for_supported_devices(driver, bridge_id, HueDiscovery.disco_api_instances[bridge_id],
      function(hue_driver, svc_info, device_info)
        discovered_device_callback(hue_driver, bridge_id, svc_info, device_info, known_identifier_to_device_map)
      end,
      "[Discovery: " ..
      (known_bridge_device.label or bridge_id or known_bridge_device.id or "unknown bridge") .. " bridge scan]"
    )
    return
  end

  if not HueDiscovery.api_keys[bridge_id] then
    local socket_builder = utils.labeled_socket_builder(bridge_id)
    local api_key_response, err, _ = HueApi.request_api_key(bridge_ip, socket_builder)

    if err ~= nil or not api_key_response then
      log.warn(string.format(
        "Error while trying to request Bridge API Key for %s: %s",
        bridge_id,
        err
      )
      )
      return
    end

    for _, item in ipairs(api_key_response) do
      if item.error ~= nil then
        log.warn(string.format("Error payload in bridge %s API key response: %s", bridge_id, item.error.description))
      elseif item.success and item.success.username then
        log.info(string.format("API key received for Hue Bridge %s", bridge_id))

        local api_key = item.success.username
        local bridge_base_url = "https://" .. bridge_ip
        local api_instance = HueApi.new_bridge_manager(bridge_base_url, api_key, socket_builder)

        HueDiscovery.api_keys[bridge_id] = api_key
        HueDiscovery.disco_api_instances[bridge_id] = api_instance
      end
    end
  end

  if HueDiscovery.api_keys[bridge_id] and not driver.joined_bridges[bridge_id] then
    local bridge_info = driver.datastore.bridge_netinfo[bridge_id]

    if not bridge_info then
      log.debug(string.format("Bridge info for %s not yet available", bridge_id))
      return
    end

    if tonumber(bridge_info.swversion or "0", 10) < HueApi.MIN_CLIP_V2_SWVERSION then
      log.warn(string.format("Found bridge %s that does not support CLIP v2 API, ignoring", bridge_info.name))
      driver.ignored_bridges[bridge_id] = true
      return
    end

    driver.joined_bridges[bridge_id] = true

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

      driver:try_create_device(create_device_msg)
    end
  end
end

---@param driver HueDriver
---@param bridge_id string
---@param api_instance PhilipsHueApi
---@param callback fun(driver: HueDriver, svc_info: table, device_data: table)
function HueDiscovery.search_bridge_for_supported_devices(driver, bridge_id, api_instance, callback, log_prefix, do_delete)
  local prefix = ""
  if type(log_prefix) == "string" and #log_prefix > 0 then prefix = log_prefix .. " " end

  local devices, err, _ = api_instance:get_devices()
  if err ~= nil or not devices then
    log.error_with({ hub_logs = true },
      prefix .. "Error querying bridge for devices: " .. (err or "unexpected nil in error position"))
    return
  end

  if devices.errors and #devices.errors > 0 then
    log.error_with({ hub_logs = true }, prefix .. "Errors found in API response:")
    for idx, err in ipairs(devices.errors) do
      log.error_with({ hub_logs = true }, st_utils.stringify_table(err, "Error number " .. idx, true))
    end
    return
  end

  local device_is_joined_to_bridge = {}
  for _, device_data in ipairs(devices.data or {}) do
    for _, svc_info in ipairs(device_data.services or {}) do
      if is_device_service_supported(svc_info) then
        device_is_joined_to_bridge[device_data.id] = true
        log.info_with({ hub_logs = true }, string.format(
          prefix ..
          "Processing supported svc [rid: %s | type: %s] for Hue device [v2_id: %s | v1_id: %s], with Hue provided name: %s",
          svc_info.rid, svc_info.rtype, device_data.id, device_data.id_v1, device_data.metadata.name
        ))
        if type(callback) == "function" then
          callback(driver, svc_info, device_data)
        else
          log.warn(
            prefix .. "Argument passed in `callback` position for "
            .. "`HueDiscovery.search_bridge_for_supported_devices` is not a function"
          )
        end
      end
    end
  end

  if do_delete then
    for _, device in ipairs(driver:get_devices()) do ---@cast device HueDevice
      -- We're only interested in processing child/non-bridge devices here.
      if utils.is_bridge(driver, device) then goto continue end
      local not_known_to_bridge = device_is_joined_to_bridge[device:get_field(Fields.HUE_DEVICE_ID) or ""]
      local parent_device_id = device.parent_device_id or device:get_field(Fields.PARENT_DEVICE_ID) or ""
      local parent_bridge_device = driver:get_device_info(parent_device_id)
      local is_child_of_bridge = parent_bridge_device and (parent_bridge_device:get_field(Fields.BRIDGE_ID) == bridge_id)
      if parent_bridge_device and is_child_of_bridge and not not_known_to_bridge and device.id then
        device.log.info(string.format("Device is no longer joined to Hue Bridge %q, deleting", parent_bridge_device.label))
        driver:do_hue_light_delete(device)
      end
      ::continue::
    end
  end
end

---@param driver HueDriver
---@param bridge_id string
---@param svc_info table
---@param device_info table
---@param known_identifier_to_device_map table<string,HueDevice>
discovered_device_callback = function(driver, bridge_id, svc_info, device_info, known_identifier_to_device_map)
  local v1_dni = bridge_id .. "/" .. (device_info.id_v1 or "UNKNOWN"):gsub("/lights/", "")
  local edge_dni = svc_info.rid or ""
  if known_identifier_to_device_map[v1_dni] or known_identifier_to_device_map[edge_dni] then return end
  if svc_info.rtype == "light" then
    process_discovered_light(driver, bridge_id, svc_info.rid, device_info, known_identifier_to_device_map)
  end
end

---@param driver HueDriver
---@param bridge_id string
---@param resource_id string
---@param device_info table
---@param known_identifier_to_device_map table<string,HueDevice>
process_discovered_light = function(driver, bridge_id, resource_id, device_info, known_identifier_to_device_map)
  local api_instance = HueDiscovery.disco_api_instances[bridge_id]
  if not api_instance then
    log.warn("No API instance for bridge_id ", bridge_id)
    return
  end

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
      parent_assigned_child_key = light.id,
    }

    HueDiscovery.light_state_disco_cache[light.id] = {
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

is_device_service_supported = function(svc_info)
  return supported_resource_types[svc_info.rtype or ""]
end

function HueDiscovery.do_mdns_scan(driver)
  local bridge_netinfo = driver.datastore.bridge_netinfo
  local mdns_responses, err = mdns.discover(HueDiscovery.ServiceType, HueDiscovery.Domain)

  if err ~= nil then
    log.error_with({ hub_logs = true }, "Error during service discovery: ", err)
    return
  end

  if not (mdns_responses and mdns_responses.found and #mdns_responses.found > 0) then
    log.warn("No mdns responses for Hue service this attempt, continuing...")
    return
  end

  for _, info in ipairs(mdns_responses.found) do
    if not net_utils.validate_ipv4_string(info.host_info.address) then -- we only care about the ipV4 types here.
      log.trace("Invalid IPv4 address: " .. info.host_info.address)
      goto continue
    end

    if info.service_info.service_type ~= HueDiscovery.ServiceType then -- response for a different service type. Shouldn't happen.
      log.warn("Unexpected service type response: " .. info.service_info.service_type)
      goto continue
    end

    if info.service_info.domain ~= HueDiscovery.Domain then -- response for a different domain. Shouldn't happen.
      log.warn("Unexpected domain response: " .. info.service_info.domain)
      goto continue
    end

    -- Hue *typically* formats the BridgeID as the uppercase MAC address, minus separators.
    -- However, it can be user overriden, set by a user, and may not be unique, so we want
    -- to stick to that format but make sure it's actually the mac address. Instead of pulling
    -- the bridge id out of the bridge info, we'll extract the MAC address and apply the above mentioned
    -- formatting rules. We also prefer the MAC because it makes for a good Device Network ID.
    local ip_addr = info.host_info.address;
    local bridge_info, rest_err, _ = HueApi.get_bridge_info(
      ip_addr,
      utils.labeled_socket_builder("[mDNS Scan: " .. ip_addr .. " Bridge Info Request]")
    )
    if rest_err ~= nil or not bridge_info then
      log.error_with({ hub_logs = true },
        string.format(
          "Error querying bridge info for discovered IP address %s: %s",
          ip_addr,
          (rest_err or "unexpected nil in error position")
        )
      )
      return
    end
    -- '-' and ':' or '::' are the accepted separators used for MAC address segments, so
    -- we strip thoes out and make the string uppercase
    if not bridge_info.mac then
      log.warn_with({ hub_logs = true },
        string.format(
          "No MAC address in returned Bridge Info for IP %s.", ip_addr
        )
      )
      return
    end

    bridge_info.ip = ip_addr
    local bridge_id = bridge_info.mac:gsub("-", ""):gsub(":", ""):upper()

    -- sanitize userdata nulls from JSON decode
    for k, v in pairs(bridge_info) do
      if type(v) == "userdata" then
        bridge_info[k] = nil
      end
    end

    local update_needed = false
    if not utils.deep_table_eq((bridge_netinfo[bridge_id] or {}), bridge_info) then
      bridge_netinfo[bridge_id] = bridge_info
      update_needed = true
    end

    if driver.joined_bridges[bridge_id] and not driver.ignored_bridges[bridge_id] then
      local bridge_device = driver:get_device_by_dni(bridge_id, true)
      update_needed = update_needed or (bridge_device and (bridge_device:get_field(Fields.IPV4) ~= bridge_info.ip))
      if update_needed then
        driver:update_bridge_netinfo(bridge_id, bridge_info)
      end
    end
    ::continue::
  end
end

return HueDiscovery
