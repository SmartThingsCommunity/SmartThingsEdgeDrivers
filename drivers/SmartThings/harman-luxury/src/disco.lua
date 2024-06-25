local mdns = require "st.mdns"
local socket = require "cosock.socket"
local log = require "log"

local api = require "api.apis"
local disco_helper = require "disco_helper"
local devices = require "devices"
local const = require "constants"

local Discovery = {}

local joined_device = {}

function Discovery.set_device_field(driver, device)
  log.info(string.format("set_device_field : dni=%s", device.device_network_id))
  local device_cache_value = driver.datastore.discovery_cache[device.device_network_id]

  -- persistent fields
  device:set_field(const.IP, device_cache_value.ip, {
    persist = true,
  })
  device:set_field(const.CREDENTIAL, device_cache_value.credential, {
    persist = true,
  })
  device:set_field(const.DEVICE_INFO, device_cache_value.device_info, {
    persist = true,
  })

  driver.datastore.discovery_cache[device.device_network_id] = nil
end

local function update_device_discovery_cache(driver, dni, params, credential)
  log.info(string.format("update_device_discovery_cache for device dni: dni=%s, ip=%s", dni, params.ip))
  local device_info = devices.get_device_info(dni, params)
  driver.datastore.discovery_cache[dni] = {
    ip = params.ip,
    credential = credential,
    device_info = device_info,
  }
end

local function try_add_device(driver, device_dni, device_params)
  log.trace(string.format("try_add_device : dni=%s, ip=%s", device_dni, device_params.ip))

  local credential, err = api.init_credential_token(device_params.ip)

  if not credential or err then
    log.error(string.format("failed to get credential. dni= %s, ip= %s. Error: %s", device_dni, device_params.ip, err))
    joined_device[device_dni] = nil
    return false
  end

  update_device_discovery_cache(driver, device_dni, device_params, credential)
  driver:try_create_device(driver.datastore.discovery_cache[device_dni].device_info)
  return true
end

function Discovery.device_added(driver, device)
  log.info(string.format("Device added: %s", device.label))

  Discovery.set_device_field(driver, device)
  joined_device[device.device_network_id] = nil
  driver.lifecycle_handlers.init(driver, device)
end

function Discovery.find_params_table()
  log.info("Discovery.find_params_table")

  local discovery_responses = mdns.discover(const.SERVICE_TYPE, const.DOMAIN) or {}

  local dni_params_table = disco_helper.get_dni_ip_table_from_mdns_responses(const.SERVICE_TYPE, discovery_responses)

  return dni_params_table
end

local function discovery_device(driver)
  local known_devices = {}

  log.debug("\n\n--- Initialising known devices list ---\n")
  for _, device in pairs(driver:get_devices()) do
    known_devices[device.device_network_id] = device
  end

  log.debug("\n\n--- Creating the parameters table ---\n")
  local params_table = Discovery.find_params_table()

  log.debug("\n\n--- Adding unknown devices ---\n")
  for dni, params in pairs(params_table) do
    if not known_devices or not known_devices[dni] then
      log.info(string.format("discovery_device unknown dni=%s, ip=%s", dni, params.ip))
      if not joined_device[dni] then
        if try_add_device(driver, dni, params_table[dni]) then
          joined_device[dni] = true
        end
      end
    else
      log.info(string.format("discovery_device known dni=%s, ip=%s", dni, params.ip))
    end
  end
end

function Discovery.discovery_handler(driver, _, should_continue)
  log.info("Starting Harman Luxury discovery")

  while should_continue() do
    discovery_device(driver)
    socket.sleep(0.5)
  end
  log.info("Ending Harman Luxury discovery")
end

function Discovery.update_device_ip(device)
  local dni = device.device_network_id
  local ip = device:get_device_info(const.IP)

  -- collect current parameters
  local params_table = Discovery.find_params_table()

  -- update device IPs
  if params_table[dni] then
    -- if device is still online
    local current_ip = params_table[dni].ip
    if ip ~= current_ip then
      device:set_field(const.IP, current_ip, {
        persist = true,
      })
      log.info(string.format("%s updated IP from %s to %s", dni, ip, current_ip))
    end
    return true
  else
    -- if device is no longer online
    device:offline()
    return false
  end
end

return Discovery
