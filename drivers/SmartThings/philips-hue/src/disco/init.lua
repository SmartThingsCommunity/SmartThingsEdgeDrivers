local log = require "log"
local socket = require "cosock.socket"

local mdns = require "st.mdns"
local net_utils = require "st.net_utils"
local st_utils = require "st.utils"
-- trick to fix the VS Code Lua Language Server typechecking
---@type fun(val: any?, name: string?, multi_line: boolean?): string
st_utils.stringify_table = st_utils.stringify_table

local Fields = require "fields"
local HueApi = require "hue.api"
local HueDeviceTypes = require "hue_device_types"

local utils = require "utils"

local SERVICE_TYPE = "_hue._tcp"
local DOMAIN = "local"

---@class DiscoveredChildDeviceHandler
---@field public handle_discovered_device fun(driver: HueDriver, bridge_network_id: string, api_instance: PhilipsHueApi, primary_services: { [HueDeviceTypes]: HueServiceInfo[] }, device_service_info: table, device_state_disco_cache: table<string, table>, st_metadata_callback: fun(driver: HueDriver, metadata: table)?)

-- This `api_keys` table is an in-memory fall-back table. It gets overwritten
-- with a reference to a driver datastore table before the Driver's `run` loop
-- can get spun up in `init.lua`.
---@class HueDiscovery
---@field public api_keys table<string,string>
---@field public disco_api_instances table<string,PhilipsHueApi>
---@field public device_state_disco_cache table<string,table<string,any>>
---@field public ServiceType string
---@field public Domain string
---@field public discovery_active boolean
local HueDiscovery = {
  api_keys = {},
  disco_api_instances = {},
  device_state_disco_cache = {},
  ServiceType = SERVICE_TYPE,
  Domain = DOMAIN,
  discovery_active = false
}

-- Lazy-load the discovered device handlers so we only load the code we need
---@type table<string,DiscoveredChildDeviceHandler>
local discovered_device_handlers = utils.lazy_handler_loader("disco")

---comment
---@param svc_info HueServiceInfo
---@return boolean
local function is_device_service_supported(svc_info)
  return discovered_device_handlers[svc_info.rtype or ""] ~= nil
end

-- "forward declarations"
---@param driver HueDriver
---@param bridge_ip string
---@param bridge_network_id string
local function discovered_bridge_callback(driver, bridge_ip, bridge_network_id)
  if driver.ignored_bridges[bridge_network_id] then return end

  local known_bridge_device = driver:get_device_by_dni(bridge_network_id)
  if known_bridge_device and known_bridge_device:get_field(HueApi.APPLICATION_KEY_HEADER) then
    HueDiscovery.api_keys[bridge_network_id] = known_bridge_device:get_field(HueApi.APPLICATION_KEY_HEADER)
  end

  if known_bridge_device ~= nil
      and driver.joined_bridges[bridge_network_id]
      and HueDiscovery.api_keys[bridge_network_id]
  then
    log.info_with({ hub_logs = true }, string.format("Scanning bridge %s for devices...", bridge_network_id))

    HueDiscovery.disco_api_instances[bridge_network_id] = HueDiscovery.disco_api_instances[bridge_network_id]
        or HueApi.new_bridge_manager(
          "https://" .. bridge_ip,
          HueDiscovery.api_keys[bridge_network_id],
          utils.labeled_socket_builder((known_bridge_device.label or bridge_network_id or known_bridge_device.id or "unknown bridge"))
        )

    HueDiscovery.search_bridge_for_supported_devices(
      driver,
      bridge_network_id,
      HueDiscovery.disco_api_instances[bridge_network_id],
      HueDiscovery.handle_discovered_child_device,
      "[Discovery: " ..
      (known_bridge_device.label or bridge_network_id or known_bridge_device.id or "unknown bridge") ..
      " bridge scan]"
    )
    return
  end

  if not HueDiscovery.api_keys[bridge_network_id] then
    local socket_builder = utils.labeled_socket_builder(bridge_network_id)
    local api_key_response, err, _ = HueApi.request_api_key(bridge_ip, socket_builder)

    if err ~= nil or not api_key_response then
      log.warn(string.format(
        "Error while trying to request Bridge API Key for %s: %s",
        bridge_network_id,
        err
      )
      )
      return
    end

    for _, item in ipairs(api_key_response) do
      if item.error ~= nil then
        log.warn(string.format("Error payload in bridge %s API key response: %s", bridge_network_id, item.error.description))
      elseif item.success and item.success.username then
        log.info(string.format("API key received for Hue Bridge %s", bridge_network_id))

        local api_key = item.success.username
        local bridge_base_url = "https://" .. bridge_ip
        local api_instance = HueApi.new_bridge_manager(bridge_base_url, api_key, socket_builder)

        HueDiscovery.api_keys[bridge_network_id] = api_key
        HueDiscovery.disco_api_instances[bridge_network_id] = api_instance
      end
    end
  end

  if HueDiscovery.api_keys[bridge_network_id] and not driver.joined_bridges[bridge_network_id] then
    local bridge_info = driver.datastore.bridge_netinfo[bridge_network_id]

    if not bridge_info then
      log.debug(string.format("Bridge info for %s not yet available", bridge_network_id))
      return
    end

    if tonumber(bridge_info.swversion or "0", 10) < HueApi.MIN_CLIP_V2_SWVERSION then
      log.warn(string.format("Found bridge %s that does not support CLIP v2 API, ignoring", bridge_info.name))
      driver.ignored_bridges[bridge_network_id] = true
      return
    end

    driver.joined_bridges[bridge_network_id] = true

    if not known_bridge_device then
      local create_device_msg = {
        type = "LAN",
        device_network_id = bridge_network_id,
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
    HueDiscovery.do_mdns_scan(driver)
    HueDiscovery.search_for_bridges(
      driver,
      function(hue_driver, bridge_ip, bridge_network_id)
        discovered_bridge_callback(hue_driver, bridge_ip, bridge_network_id)
      end
    )
    socket.sleep(1.0)
  end
  HueDiscovery.discovery_active = false
  log.info_with({ hub_logs = true }, "Ending Hue discovery")
end

---@param driver HueDriver
---@param callback fun(driver: HueDriver, ip: string, id: string)
function HueDiscovery.search_for_bridges(driver, callback)
  local scanned_bridges = driver.datastore.bridge_netinfo or {}
  for bridge_network_id, bridge_info in pairs(scanned_bridges) do
    if type(callback) == "function" and bridge_info ~= nil then
      callback(driver, bridge_info.ip, bridge_network_id)
    else
      log.warn(
        "Argument passed in `callback` position for "
        .. "`HueDiscovery.search_for_bridges` is not a function"
      )
    end
  end
end

---@param driver HueDriver
---@param bridge_network_id string
function HueDiscovery.scan_bridge_and_update_devices(driver, bridge_network_id)
  if driver.ignored_bridges[bridge_network_id] then return end

  local known_bridge_device = driver:get_device_by_dni(bridge_network_id)
  if known_bridge_device then
    if known_bridge_device:get_field(HueApi.APPLICATION_KEY_HEADER) then
      HueDiscovery.api_keys[bridge_network_id] = known_bridge_device:get_field(HueApi.APPLICATION_KEY_HEADER)
    end

    HueDiscovery.search_bridge_for_supported_devices(
      driver,
      bridge_network_id,
      HueDiscovery.disco_api_instances[bridge_network_id],
      HueDiscovery.handle_discovered_child_device,
      "[Discovery: " ..
      (known_bridge_device.label or bridge_network_id or known_bridge_device.id or "unknown bridge") ..
      " bridge re-scan]",
      true
    )
  end
end

---@param driver HueDriver
---@param bridge_network_id string
---@param api_instance PhilipsHueApi
---@param callback fun(driver: HueDriver, bridge_network_id: string, primary_services: table<HueDeviceTypes,HueServiceInfo[]>, device_data: table)
---@param log_prefix string?
---@param do_delete boolean?
function HueDiscovery.search_bridge_for_supported_devices(driver, bridge_network_id, api_instance, callback, log_prefix, do_delete)
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
    device_is_joined_to_bridge[device_data.id] =
        HueDiscovery.process_device_service(driver, bridge_network_id, device_data, callback, log_prefix)
  end

  if do_delete then
    for _, device in ipairs(driver:get_devices()) do
      -- We're only interested in processing child/non-bridge devices here.
      if utils.is_bridge(driver, device) then goto continue end
      local not_known_to_bridge = device_is_joined_to_bridge[device:get_field(Fields.HUE_DEVICE_ID) or ""]
      local parent_device_id = device.parent_device_id or device:get_field(Fields.PARENT_DEVICE_ID) or ""
      local parent_bridge_device = utils.get_hue_bridge_for_device(driver, device, parent_device_id)
      local is_child_of_bridge = parent_bridge_device and (parent_bridge_device:get_field(Fields.BRIDGE_ID) == bridge_network_id)
      if parent_bridge_device and is_child_of_bridge and not not_known_to_bridge and device.id then
        device.log.info(string.format("Device is no longer joined to Hue Bridge %q, deleting", parent_bridge_device.label))
        driver:do_hue_child_delete(device)
      end
      ::continue::
    end
  end
end

---@param driver HueDriver
---@param bridge_network_id string
---@param device_data HueDeviceInfo
---@param callback fun(driver: HueDriver, bridge_network_id: string, primary_services: table<HueDeviceTypes,HueServiceInfo[]>, device_data: table, bridge_device: HueBridgeDevice?)?
---@param log_prefix string?
---@param bridge_device HueBridgeDevice?
---@return boolean device_joined_to_bridge true if device was sent through the join process
function HueDiscovery.process_device_service(driver, bridge_network_id, device_data, callback, log_prefix, bridge_device)
  local prefix = ""
  if type(log_prefix) == "string" and #log_prefix > 0 then prefix = log_prefix .. " " end
  local primary_device_services = {}

  local device_joined_to_bridge = false
  for _,
  svc_info in ipairs(device_data.services or {}) do
    if is_device_service_supported(svc_info) then
      driver.services_for_device_rid[device_data.id] = driver.services_for_device_rid[device_data.id] or {}
      driver.services_for_device_rid[device_data.id][svc_info.rid] = svc_info.rtype
      if HueDeviceTypes.can_join_device_for_service(svc_info.rtype) then
        local services_for_type = primary_device_services[svc_info.rtype] or {}
        table.insert(services_for_type, svc_info)
        primary_device_services[svc_info.rtype] = services_for_type
        device_joined_to_bridge = true
      end
    end
  end
  if next(primary_device_services) then
    if type(callback) == "function" then
      log.info_with(
        { hub_logs = true },
        string.format(
          prefix ..
          "Processing supported services [%s] for Hue device [v2_id: %s | v1_id: %s], with Hue provided name: %s",
          st_utils.stringify_table(primary_device_services), device_data.id, device_data.id_v1, device_data.metadata.name
        )
      )
      callback(driver, bridge_network_id, primary_device_services, device_data, bridge_device)
    else
      log.warn(
        prefix .. "Argument passed in `callback` position for "
        .. "`HueDiscovery.search_bridge_for_supported_devices` is not a function"
      )
    end
  else
    log.warn(string.format("No primary services for %s", device_data.metadata.name))
    log.warn(st_utils.stringify_table(device_data.services, "services", true))
  end

  return device_joined_to_bridge
end

---@param driver HueDriver
---@param bridge_network_id string
---@param primary_services table<HueDeviceTypes,HueServiceInfo[]> array of services that *can* map to device records. Multi-buttons wouldn't do so, but compound lights would.
---@param device_info table
---@param bridge_device HueBridgeDevice? If the parent bridge is known, it can be passed in here
function HueDiscovery.handle_discovered_child_device(driver, bridge_network_id, primary_services, device_info, bridge_device)
  local v1_dni = bridge_network_id .. "/" .. (device_info.id_v1 or "UNKNOWN"):gsub("/lights/", "")
  local primary_service_type = HueDeviceTypes.determine_main_service_rtype(device_info, primary_services)
  if not primary_service_type then
    log.error(
      string.format(
        "Couldn't determine primary service type for device %s, unable to join",
        (device_info.metadata.name)
      )
    )
    return
  end

  for _, svc_info in ipairs(primary_services[primary_service_type]) do
    local v2_resource_id = svc_info.rid or ""
    if driver:get_device_by_dni(v1_dni) or driver.hue_identifier_to_device_record[v2_resource_id] then return end
  end

  local api_instance =
      (bridge_device and bridge_device:get_field(Fields.BRIDGE_API)) or
      HueDiscovery.disco_api_instances[bridge_network_id]
  if not api_instance then
    log.warn("No API instance for bridge_network_id ", bridge_network_id)
    return
  end

  discovered_device_handlers[primary_service_type].handle_discovered_device(
    driver,
    bridge_network_id,
    api_instance,
    primary_services,
    device_info,
    HueDiscovery.device_state_disco_cache,
    driver.try_create_device
  )
end

---@param driver HueDriver
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
    local bridge_network_id = bridge_info.mac:gsub("-", ""):gsub(":", ""):upper()

    -- sanitize userdata nulls from JSON decode
    for k, v in pairs(bridge_info) do
      if type(v) == "userdata" then
        bridge_info[k] = nil
      end
    end

    ---@type boolean?
    local update_needed = false
    if not utils.deep_table_eq((bridge_netinfo[bridge_network_id] or {}), bridge_info) then
      bridge_netinfo[bridge_network_id] = bridge_info
      update_needed = true
    end

    if driver.joined_bridges[bridge_network_id] and not driver.ignored_bridges[bridge_network_id] then
      local bridge_device = driver:get_device_by_dni(bridge_network_id, true)
      update_needed = update_needed or (bridge_device and (bridge_device:get_field(Fields.IPV4) ~= bridge_info.ip))
      if update_needed then
        driver:update_bridge_netinfo(bridge_network_id, bridge_info)
      end
    end
    ::continue::
  end
end

return HueDiscovery
